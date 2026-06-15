#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"
RUN_USER="${RUN_USER:-pi}"
PULSE_SERVER="${PULSE_SERVER:-unix:/run/pulse/native}"

if [[ -f "$CONFIG_DIR/common.env" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/common.env"
fi

if [[ -f "$CONFIG_DIR/sync.env" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/sync.env"
fi

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
CHECK_RECENT_SYNC_SUCCESS="${CHECK_RECENT_SYNC_SUCCESS:-true}"
MAX_SYNC_SUCCESS_AGE_MINUTES="${MAX_SYNC_SUCCESS_AGE_MINUTES:-30}"
DOCTOR_LOG_WINDOW_MINUTES="${DOCTOR_LOG_WINDOW_MINUTES:-1440}"

failures=0
warnings=0

ok() {
  printf 'ok   %s\n' "$*"
}

warn() {
  printf 'warn %s\n' "$*" >&2
  warnings=$((warnings + 1))
}

fail() {
  printf 'fail %s\n' "$*" >&2
  failures=$((failures + 1))
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

channels_list() {
  local channels="${VOX_CHANNELS//,/ }"
  local channel_array=()

  read -r -a channel_array <<<"$channels"
  printf '%s\n' "${channel_array[@]}"
}

check_service_active() {
  local service="$1"
  local state

  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then
    ok "$service is active"
  else
    fail "$service is $state"
  fi
}

check_timer_active() {
  local timer="$1"
  local required="${2:-true}"
  local state

  state="$(systemctl is-active "$timer" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then
    ok "$timer is active"
  elif is_true "$required"; then
    fail "$timer is $state"
  else
    warn "$timer is $state"
  fi
}

check_path_writable() {
  local path="$1"

  if [[ -d "$path" && -w "$path" ]]; then
    ok "$path is writable"
  else
    fail "$path is not a writable directory"
  fi
}

check_user_group() {
  local user="$1"
  local group="$2"
  local required="${3:-true}"

  if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$group"; then
    ok "$user is in $group"
  elif is_true "$required"; then
    fail "$user is not in $group"
  else
    warn "$user is not in $group"
  fi
}

check_root_group() {
  local group="$1"
  local required="${2:-true}"

  if id -nG root 2>/dev/null | tr ' ' '\n' | grep -Fxq "$group"; then
    ok "root is in $group"
  elif is_true "$required"; then
    fail "root is not in $group"
  else
    warn "root is not in $group"
  fi
}

check_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name is installed"
  else
    fail "$command_name is not installed"
  fi
}

check_package() {
  local package="$1"
  local required="${2:-true}"

  if dpkg-query -W "$package" >/dev/null 2>&1; then
    ok "$package package is installed"
  elif is_true "$required"; then
    fail "$package package is not installed"
  else
    warn "$package package is not installed"
  fi
}

check_pulse_source() {
  local source="$1"

  if PULSE_SERVER="$PULSE_SERVER" pactl list short sources 2>/dev/null | awk '{print $2}' | grep -Fxq "$source"; then
    ok "PulseAudio source $source exists"
  else
    fail "PulseAudio source $source is missing"
  fi
}

check_legacy_service() {
  local service="$1"
  local enabled active

  enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
  active="$(systemctl is-active "$service" 2>/dev/null || true)"

  case "$enabled:$active" in
    not-found:inactive|masked:inactive|disabled:inactive)
      ok "legacy $service is not running ($enabled)"
      ;;
    *)
      fail "legacy $service is enabled=$enabled active=$active"
      ;;
  esac
}

check_user_pulseaudio() {
  local uid enabled_service enabled_socket active_service active_socket
  local user_systemd_dir home_dir

  if ! id "$RUN_USER" >/dev/null 2>&1; then
    warn "run user does not exist: $RUN_USER"
    return
  fi

  uid="$(id -u "$RUN_USER")"
  home_dir="$(getent passwd "$RUN_USER" | cut -d: -f6)"
  user_systemd_dir="$home_dir/.config/systemd/user"

  if [[ -L "$user_systemd_dir/pulseaudio.service" && "$(readlink "$user_systemd_dir/pulseaudio.service")" == "/dev/null" ]] \
    && [[ -L "$user_systemd_dir/pulseaudio.socket" && "$(readlink "$user_systemd_dir/pulseaudio.socket")" == "/dev/null" ]]; then
    ok "per-user PulseAudio is masked for $RUN_USER"
  else
    warn "per-user PulseAudio is not masked for $RUN_USER"
  fi

  if [[ -d "/run/user/$uid" ]]; then
    enabled_service="$(sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-enabled pulseaudio.service 2>/dev/null || true)"
    enabled_socket="$(sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-enabled pulseaudio.socket 2>/dev/null || true)"
    active_service="$(sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active pulseaudio.service 2>/dev/null || true)"
    active_socket="$(sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active pulseaudio.socket 2>/dev/null || true)"
    if [[ "$active_service" == "inactive" && "$active_socket" == "inactive" ]]; then
      ok "per-user PulseAudio is inactive for $RUN_USER"
    else
      warn "per-user PulseAudio state for $RUN_USER: service enabled=$enabled_service active=$active_service, socket enabled=$enabled_socket active=$active_socket"
    fi
  else
    ok "no active user runtime for $RUN_USER"
  fi
}

check_recording_permissions() {
  local root_owned_mp3 root_owned_dirs

  root_owned_mp3="$(find "$OUTPUT_ROOT" -type f -name '*.mp3' -user root 2>/dev/null | wc -l | awk '{print $1}')"
  root_owned_dirs="$(find "$OUTPUT_ROOT" -type d -user root 2>/dev/null | wc -l | awk '{print $1}')"

  if [[ "$root_owned_mp3" == "0" ]]; then
    ok "no root-owned MP3s under $OUTPUT_ROOT"
  else
    fail "$root_owned_mp3 root-owned MP3 files under $OUTPUT_ROOT"
  fi

  if [[ "$root_owned_dirs" == "0" ]]; then
    ok "no root-owned recording directories under $OUTPUT_ROOT"
  else
    fail "$root_owned_dirs root-owned recording directories under $OUTPUT_ROOT"
  fi
}

check_filesystem_usage() {
  local path="$1"
  local label="$2"
  local warn_pct="${3:-85}"
  local fail_pct="${4:-95}"
  local used used_num

  used="$(df -P "$path" 2>/dev/null | awk 'NR == 2 {print $5}')"
  if [[ -z "$used" ]]; then
    warn "cannot read filesystem usage for $label ($path)"
    return
  fi

  used_num="${used%%%}"
  if ((used_num >= fail_pct)); then
    fail "$label filesystem is ${used} used"
  elif ((used_num >= warn_pct)); then
    warn "$label filesystem is ${used} used"
  else
    ok "$label filesystem is ${used} used"
  fi
}

check_recent_journal() {
  local unit="$1"
  local minutes="$2"
  local pattern="$3"
  local label="$4"
  local required="${5:-true}"

  if journalctl -u "$unit" --since "$minutes minutes ago" --no-pager 2>/dev/null | grep -E "$pattern" >/dev/null; then
    ok "recent $label within ${minutes} minutes"
  elif is_true "$required"; then
    fail "no recent $label within ${minutes} minutes"
  else
    warn "no recent $label within ${minutes} minutes"
  fi
}

check_rclone() {
  if [[ -z "${RCLONE_REMOTE:-}" ]]; then
    warn "RCLONE_REMOTE is not configured"
    return
  fi

  check_command rclone
  if sudo -u "$RUN_USER" rclone lsd "$RCLONE_REMOTE" >/dev/null 2>&1; then
    ok "rclone remote is reachable"
  else
    fail "rclone remote is not reachable as $RUN_USER"
  fi
}

check_pcp() {
  local active_any=0
  local service state

  for service in pmcd pmlogger pmie pmproxy; do
    state="$(systemctl is-active "$service" 2>/dev/null || true)"
    if [[ "$state" == "active" || "$state" == "activating" ]]; then
      active_any=1
      warn "PCP service $service is $state"
    fi
  done

  if [[ "$active_any" -eq 0 ]]; then
    ok "PCP services are inactive"
  fi
}

check_raspibackup() {
  local config="/usr/local/etc/raspiBackup.conf"

  if [[ ! -f "$config" ]]; then
    ok "raspiBackup config not present"
    return
  fi

  if grep -Eq "systemctl (start|stop) '?vox|systemctl (start|stop) '?vox2|systemctl (start|stop) '?rtl_airband|systemctl (start|stop) '?pulseaudio" "$config"; then
    fail "raspiBackup config still starts/stops recorder services"
  else
    ok "raspiBackup does not start/stop recorder services"
  fi

  if grep -q -- "--exclude=/mnt/ramdisk" "$config" && grep -q -- "--exclude=/home/pi/Recordings" "$config"; then
    ok "raspiBackup excludes volatile recorder paths"
  else
    warn "raspiBackup does not exclude both /mnt/ramdisk and /home/pi/Recordings"
  fi
}

check_config_files() {
  local channel env_file

  if [[ -f "$CONFIG_DIR/site.yaml" ]]; then
    ok "$CONFIG_DIR/site.yaml exists"
  else
    warn "$CONFIG_DIR/site.yaml is missing"
  fi

  if [[ -f "$CONFIG_DIR/common.env" ]]; then
    ok "$CONFIG_DIR/common.env exists"
  else
    fail "$CONFIG_DIR/common.env is missing"
  fi

  if [[ -f /usr/local/etc/rtl_airband.conf ]]; then
    ok "/usr/local/etc/rtl_airband.conf exists"
  else
    fail "/usr/local/etc/rtl_airband.conf is missing"
  fi

  if [[ -f /etc/pulse/system.pa ]]; then
    ok "/etc/pulse/system.pa exists"
  else
    fail "/etc/pulse/system.pa is missing"
  fi

  for channel in $(channels_list); do
    env_file="$CONFIG_DIR/$channel.env"
    if [[ -f "$env_file" ]]; then
      ok "$env_file exists"
    else
      fail "$env_file is missing"
    fi
  done
}

check_channel() {
  local channel="$1"
  local env_file="$CONFIG_DIR/$channel.env"
  local PULSE_MONITOR=""
  local service="vox@${channel}.service"

  if [[ ! -f "$env_file" ]]; then
    fail "$env_file is missing"
    return
  fi

  # shellcheck disable=SC1090
  source "$env_file"

  check_service_active "$service"
  if [[ -n "$PULSE_MONITOR" ]]; then
    check_pulse_source "$PULSE_MONITOR"
  else
    fail "$channel has no PULSE_MONITOR"
  fi
}

section() {
  printf '\n%s\n' "$1"
}

echo "Train Recorder Doctor"
echo "Generated: $(date)"
echo "Host:      $(hostname)"

section "Core Services"
check_service_active pulseaudio.service
check_service_active rtl_airband.service
check_timer_active train-recorder-health.timer true
check_timer_active train-recorder-cleanup.timer true
if [[ -n "${RCLONE_REMOTE:-}" ]]; then
  check_timer_active train-recorder-sync.timer true
else
  check_timer_active train-recorder-sync.timer false
fi

section "Configured Channels"
while IFS= read -r channel; do
  [[ -n "$channel" ]] && check_channel "$channel"
done < <(channels_list)

section "Config and Runtime Paths"
check_config_files
check_path_writable "$OUTPUT_ROOT"
check_path_writable "$TEMP_DIR"
check_recording_permissions
check_filesystem_usage "$OUTPUT_ROOT" "recording/root"
check_filesystem_usage "$TEMP_DIR" "temp"
if mountpoint -q /var/log 2>/dev/null; then
  check_filesystem_usage /var/log "/var/log"
fi

section "PulseAudio"
check_user_group "$RUN_USER" pulse false
check_user_group "$RUN_USER" pulse-access
check_user_group "$RUN_USER" audio
check_root_group pulse false
check_root_group pulse-access
check_user_pulseaudio

section "Packages and Tools"
check_command rtl_airband
check_command sox
check_command pactl
check_package libsox-fmt-mp3 true
check_package libsox-fmt-pulse true

section "Sync and Recent Activity"
if is_true "$CHECK_RECENT_SYNC_SUCCESS"; then
  check_recent_journal train-recorder-sync.service "$MAX_SYNC_SUCCESS_AGE_MINUTES" 'Finished train-recorder-sync\.service' "sync service success" true
else
  ok "recent sync success check disabled"
fi
check_rclone

section "Known Pitfalls"
check_legacy_service vox.service
check_legacy_service vox2.service
check_pcp
check_raspibackup

section "Recent Warnings"
clipping_count="$(journalctl --since "$DOCTOR_LOG_WINDOW_MINUTES minutes ago" --no-pager 2>/dev/null | grep -c 'balancing clipped' || true)"
if [[ "$clipping_count" == "0" ]]; then
  ok "no SOX clipping warnings in ${DOCTOR_LOG_WINDOW_MINUTES} minutes"
else
  warn "$clipping_count SOX clipping warnings in ${DOCTOR_LOG_WINDOW_MINUTES} minutes"
fi

echo
printf 'Doctor summary: %s failure(s), %s warning(s)\n' "$failures" "$warnings"
if ((failures > 0)); then
  exit 1
fi
exit 0
