#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/train-recorder}"
CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"
SITE_CONFIG="${SITE_CONFIG:-$CONFIG_DIR/site.yaml}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/home/pi/Recordings}"
RAMDISK_DIR="${RAMDISK_DIR:-/mnt/ramdisk}"
VARLOG_TMPFS_SIZE="${VARLOG_TMPFS_SIZE:-64m}"
RUN_USER="${RUN_USER:-pi}"
RUN_GROUP="${RUN_GROUP:-pi}"
VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
RTL_AIRBAND_REPO="${RTL_AIRBAND_REPO:-https://github.com/rtl-airband/RTLSDR-Airband.git}"
RTL_AIRBAND_REF="${RTL_AIRBAND_REF:-v5.2.0}"
RTL_AIRBAND_PLATFORM="${RTL_AIRBAND_PLATFORM:-native}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APT_UPDATED=0

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix answer

  case "$default" in
    y|Y) suffix='[Y/n]' ;;
    *) suffix='[y/N]' ;;
  esac

  read -r -p "$prompt $suffix " answer
  answer="${answer:-$default}"

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_apt_update() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    "${SUDO[@]}" apt-get update
    APT_UPDATED=1
  fi
}

install_packages() {
  local packages=("$@")
  run_apt_update
  "${SUDO[@]}" apt-get install -y "${packages[@]}"
}

copy_if_missing() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"

  if [[ -e "$dest" ]]; then
    echo "keep existing $dest"
  else
    "${SUDO[@]}" install -D -m "$mode" "$src" "$dest"
    echo "installed $dest"
  fi
}

install_with_backup() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"
  local backup

  if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest"; then
    backup="${dest}.bak-$(date +%Y%m%d-%H%M%S)"
    "${SUDO[@]}" cp "$dest" "$backup"
    echo "backed up $dest to $backup"
  fi

  "${SUDO[@]}" install -D -m "$mode" "$src" "$dest"
  echo "installed $dest"
}

install_repo_files() {
  echo
  echo "Installing project files to $INSTALL_DIR"

  "${SUDO[@]}" mkdir -p "$INSTALL_DIR"

  if [[ "$(cd "$REPO_ROOT" && pwd -P)" != "$(cd "$INSTALL_DIR" 2>/dev/null && pwd -P || true)" ]]; then
    if ! command -v rsync >/dev/null 2>&1; then
      echo "rsync is required for project file installation; installing it now."
      install_packages rsync
    fi

    "${SUDO[@]}" rsync -a \
      --exclude '.git/' \
      --exclude 'Config/rtl_airband.conf' \
      "$REPO_ROOT"/ "$INSTALL_DIR"/
  else
    echo "repo already appears to be at $INSTALL_DIR"
  fi

  "${SUDO[@]}" chmod +x "$INSTALL_DIR"/Scripts/*.sh "$INSTALL_DIR"/Scripts/*.py
  "${SUDO[@]}" chown -R "$RUN_USER:$RUN_GROUP" "$INSTALL_DIR"
}

install_pulseaudio_config() {
  local src="$INSTALL_DIR/Config/system.pa"
  local dest="/etc/pulse/system.pa"
  local sample="/etc/pulse/system.pa.train-recorder.example"

  if [[ ! -e "$dest" ]]; then
    copy_if_missing "$src" "$dest"
  elif cmp -s "$src" "$dest"; then
    echo "keep existing $dest; already matches train-recorder config"
  elif ask_yes_no "$dest already exists. Back it up and replace it with the train-recorder PulseAudio system config?"; then
    install_with_backup "$src" "$dest"
  else
    "${SUDO[@]}" install -D -m 0644 "$src" "$sample"
    echo "kept existing $dest"
    echo "wrote train-recorder sample to $sample"
  fi
}

install_local_configs() {
  echo
  echo "Installing local config files without overwriting existing files"

  "${SUDO[@]}" mkdir -p "$CONFIG_DIR"
  copy_if_missing "$INSTALL_DIR/Config/common.env.example" "$CONFIG_DIR/common.env"
  copy_if_missing "$INSTALL_DIR/Config/freq160545.env.example" "$CONFIG_DIR/freq160545.env"
  copy_if_missing "$INSTALL_DIR/Config/freq161265.env.example" "$CONFIG_DIR/freq161265.env"
  copy_if_missing "$INSTALL_DIR/Config/sync.env.example" "$CONFIG_DIR/sync.env"
  copy_if_missing "$INSTALL_DIR/Config/rtl_airband.conf.example" "/usr/local/etc/rtl_airband.conf"
  install_pulseaudio_config
}

prepare_directories() {
  echo
  echo "Preparing runtime directories"

  "${SUDO[@]}" mkdir -p "$RECORDINGS_DIR" "$RAMDISK_DIR" /usr/local/etc
  "${SUDO[@]}" chown -R "$RUN_USER:$RUN_GROUP" "$RECORDINGS_DIR" "$RAMDISK_DIR"
  "${SUDO[@]}" chmod 775 "$RECORDINGS_DIR"
}

install_systemd_units() {
  echo
  echo "Installing systemd units"

  local unit

  for unit in "$INSTALL_DIR"/Service_Files/*.service "$INSTALL_DIR"/Service_Files/*.timer; do
    install_with_backup "$unit" "/etc/systemd/system/$(basename "$unit")"
  done

  "${SUDO[@]}" systemctl daemon-reload
}

configured_vox_channels() {
  local channels="$VOX_CHANNELS"
  local channel_array=()

  if [[ -f "$CONFIG_DIR/common.env" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_DIR/common.env"
    channels="$VOX_CHANNELS"
  fi

  channels="${channels//,/ }"
  read -r -a channel_array <<<"$channels"
  printf '%s\n' "${channel_array[@]}"
}

install_sox() {
  install_packages sox libsox-fmt-mp3 libsox-fmt-pulse
}

install_pulseaudio() {
  install_packages pulseaudio pulseaudio-utils
}

configure_pulseaudio_access() {
  echo
  echo "Configuring PulseAudio system-mode access groups"

  if id "$RUN_USER" >/dev/null 2>&1; then
    "${SUDO[@]}" usermod -aG pulse,pulse-access,audio "$RUN_USER"
    echo "added $RUN_USER to pulse, pulse-access, and audio"
  else
    echo "warning: run user does not exist yet: $RUN_USER"
  fi

  "${SUDO[@]}" usermod -aG pulse,pulse-access root
  echo "added root to pulse and pulse-access for rtl_airband.service"
  echo "group changes apply to newly started services; restart PulseAudio/RTLSDR-Airband after configuration."
}

disable_user_pulseaudio() {
  local uid home_dir user_systemd_dir

  if ! id "$RUN_USER" >/dev/null 2>&1; then
    echo "warning: run user does not exist yet: $RUN_USER"
    return
  fi

  uid="$(id -u "$RUN_USER")"
  home_dir="$(getent passwd "$RUN_USER" | cut -d: -f6)"
  user_systemd_dir="$home_dir/.config/systemd/user"

  echo
  echo "Disabling per-user PulseAudio for $RUN_USER"
  "${SUDO[@]}" install -d -o "$RUN_USER" -g "$RUN_GROUP" "$user_systemd_dir"
  "${SUDO[@]}" ln -sfn /dev/null "$user_systemd_dir/pulseaudio.service"
  "${SUDO[@]}" ln -sfn /dev/null "$user_systemd_dir/pulseaudio.socket"
  "${SUDO[@]}" chown -h "$RUN_USER:$RUN_GROUP" "$user_systemd_dir/pulseaudio.service" "$user_systemd_dir/pulseaudio.socket"

  if [[ -d "/run/user/$uid" ]]; then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      runuser -u "$RUN_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user disable --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
      runuser -u "$RUN_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
    else
      sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user disable --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
      sudo -u "$RUN_USER" XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
    fi
  fi

  "${SUDO[@]}" pkill -u "$RUN_USER" -x pulseaudio 2>/dev/null || true
  echo "system-mode pulseaudio.service should be the only PulseAudio daemon used by Train Recorder."
}

install_rclone() {
  install_packages rclone
}

install_dashboard() {
  install_packages python3-flask
}

ensure_dashboard_dependencies() {
  if python3 -c "import flask" >/dev/null 2>&1; then
    return
  fi

  echo "Flask is required for train-recorder-dashboard.service; installing python3-flask."
  install_dashboard
}

install_rtlsdr_runtime() {
  install_packages rtl-sdr librtlsdr-dev
}

disable_pcp_if_installed() {
  if ! dpkg-query -W pcp >/dev/null 2>&1 && ! dpkg-query -W pcp-conf >/dev/null 2>&1; then
    echo "PCP packages not detected"
    return
  fi

  echo
  echo "Disabling Performance Co-Pilot services"
  "${SUDO[@]}" systemctl disable --now pmcd pmlogger pmie pmproxy 2>/dev/null || true
  "${SUDO[@]}" rm -rf /var/log/pcp
  echo "disabled PCP services and removed /var/log/pcp"
}

fstab_has_mount() {
  local mountpoint="$1"
  grep -Eq "^[[:space:]]*[^#][^[:space:]]+[[:space:]]+${mountpoint}[[:space:]]+" /etc/fstab
}

add_fstab_line_if_missing() {
  local mountpoint="$1"
  local line="$2"

  if fstab_has_mount "$mountpoint"; then
    echo "keep existing /etc/fstab entry for $mountpoint"
    return
  fi

  printf '%s\n' "$line" | "${SUDO[@]}" tee -a /etc/fstab >/dev/null
  echo "added /etc/fstab entry for $mountpoint"
}

configure_tmpfs_mounts() {
  echo
  echo "Configuring optional tmpfs mounts"

  if ask_yes_no "Add $RAMDISK_DIR tmpfs to /etc/fstab if missing?" y; then
    add_fstab_line_if_missing "$RAMDISK_DIR" "tmpfs $RAMDISK_DIR tmpfs nodev,nosuid,size=50M 0 0"
    "${SUDO[@]}" mount "$RAMDISK_DIR" 2>/dev/null || true
  fi

  if ask_yes_no "Add /var/log tmpfs to /etc/fstab if missing?"; then
    add_fstab_line_if_missing "/var/log" "tmpfs /var/log tmpfs defaults,noatime,nosuid,size=$VARLOG_TMPFS_SIZE 0 0"
    echo "Mount /var/log tmpfs after reviewing current logs, or reboot during a planned maintenance window."
  fi
}

build_rtlsdr_airband() {
  local build_root source_dir build_dir

  build_root="$(mktemp -d /tmp/rtlsdr-airband-build.XXXXXX)"
  source_dir="$build_root/source"
  build_dir="$source_dir/build"

  echo
  echo "Building RTLSDR-Airband from $RTL_AIRBAND_REPO ($RTL_AIRBAND_REF)"
  echo "This will install or replace /usr/local/bin/rtl_airband."

  install_packages \
    git \
    build-essential \
    cmake \
    pkg-config \
    libmp3lame-dev \
    libshout3-dev \
    'libconfig++-dev' \
    libfftw3-dev \
    librtlsdr-dev \
    libpulse-dev

  git clone "$RTL_AIRBAND_REPO" "$source_dir"
  git -C "$source_dir" checkout "$RTL_AIRBAND_REF"
  mkdir -p "$build_dir"

  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPLATFORM="$RTL_AIRBAND_PLATFORM" \
    -DRTLSDR=ON \
    -DMIRISDR=OFF \
    -DSOAPYSDR=OFF \
    -DNFM=ON \
    -DPULSEAUDIO=ON

  cmake --build "$build_dir" --parallel "$(nproc)"
  "${SUDO[@]}" cmake --install "$build_dir"

  if command -v rtl_airband >/dev/null 2>&1; then
    rtl_airband -h >/dev/null 2>&1 || true
    echo "rtl_airband installed at $(command -v rtl_airband)"
  fi

  echo "source build left at $build_root for review"
}

enable_core_services() {
  local channel

  "${SUDO[@]}" systemctl enable pulseaudio.service rtl_airband.service

  for channel in $(configured_vox_channels); do
    "${SUDO[@]}" systemctl enable "vox@${channel}.service"
  done
}

start_core_services() {
  local channel

  "${SUDO[@]}" systemctl start pulseaudio.service
  "${SUDO[@]}" systemctl start rtl_airband.service

  for channel in $(configured_vox_channels); do
    "${SUDO[@]}" systemctl start "vox@${channel}.service"
  done
}

enable_optional_timers() {
  "${SUDO[@]}" systemctl enable --now train-recorder-health.timer
  "${SUDO[@]}" systemctl enable --now train-recorder-sync.timer
  "${SUDO[@]}" systemctl enable --now train-recorder-cleanup.timer
}

enable_dashboard_service() {
  ensure_dashboard_dependencies
  "${SUDO[@]}" systemctl enable --now train-recorder-dashboard.service
}

enable_wifi_check_timer() {
  "${SUDO[@]}" mkdir -p /var/lib/train-recorder
  "${SUDO[@]}" systemctl enable --now train-recorder-wifi-check.timer
}

site_config_exists() {
  [[ -f "$SITE_CONFIG" ]]
}

run_install_validation() {
  if [[ -x "$INSTALL_DIR/Scripts/site_config.sh" ]]; then
    "${SUDO[@]}" "$INSTALL_DIR/Scripts/site_config.sh" doctor
  elif [[ -x "$INSTALL_DIR/Scripts/doctor.sh" ]]; then
    "${SUDO[@]}" "$INSTALL_DIR/Scripts/doctor.sh"
  else
    echo "doctor command is not installed at $INSTALL_DIR/Scripts"
    return 1
  fi
}

echo "Train Recorder installer"
echo "Repo root:    $REPO_ROOT"
echo "Install dir:  $INSTALL_DIR"
echo "Config dir:   $CONFIG_DIR"
echo
echo "This installer is conservative: it does not overwrite existing env files,"
echo "RTLSDR-Airband config, PulseAudio config, or rclone credentials without asking."

if ask_yes_no "Install/update apt helper packages used by the installer?"; then
  install_packages rsync git ca-certificates
fi

if ask_yes_no "Install SOX with MP3 support?"; then
  install_sox
fi

if ask_yes_no "Install PulseAudio packages?"; then
  install_pulseaudio
  configure_pulseaudio_access
fi

if ask_yes_no "Install rclone from apt?"; then
  install_rclone
fi

if ask_yes_no "Install Flask for the optional read-only web dashboard?"; then
  install_dashboard
fi

if ask_yes_no "Install RTL-SDR runtime and development packages?"; then
  install_rtlsdr_runtime
fi

if ask_yes_no "Build and install RTLSDR-Airband from source with RTLSDR, NFM, PulseAudio, libshout, and LAME support?"; then
  build_rtlsdr_airband
fi

install_repo_files
prepare_directories
install_local_configs
install_systemd_units
configure_tmpfs_mounts

if ask_yes_no "Disable per-user PulseAudio for $RUN_USER? Recommended for recorder appliances using system-mode PulseAudio." y; then
  disable_user_pulseaudio
fi

echo
if ask_yes_no "Disable Performance Co-Pilot (PCP) services if installed? Recommended for small /var/log tmpfs." y; then
  disable_pcp_if_installed
fi

if site_config_exists; then
  echo
  echo "Site config found at $SITE_CONFIG."
  echo "You can start services here, or use site_config.sh apply to reconcile config and services."

  if ask_yes_no "Enable core recorder services at boot?"; then
    enable_core_services
  fi

  if ask_yes_no "Start core recorder services now?"; then
    start_core_services
  fi

  if ask_yes_no "Enable health, sync, and cleanup timers now?"; then
    enable_optional_timers
  fi

  if ask_yes_no "Enable the optional read-only web dashboard now?"; then
    enable_dashboard_service
    echo "dashboard will listen on DASHBOARD_HOST/DASHBOARD_PORT, default http://<pi-address>:8080/"
  fi

  if ask_yes_no "Enable the optional Wi-Fi/network health check timer now?"; then
    enable_wifi_check_timer
  fi

  if ask_yes_no "Run read-only install validation with site_config.sh doctor now?"; then
    if ! run_install_validation; then
      echo "doctor reported one or more failures; review the output above and rerun after fixing them."
    fi
  fi
else
  echo
  echo "Skipping service start prompts because $SITE_CONFIG does not exist yet."
  echo "Run site_config.sh wizard/generate/plan/diff/apply after configuring rclone and site settings."
  echo "site_config.sh apply will enable/start the configured recorder services and train-recorder timers."
  echo "After apply, run site_config.sh doctor to validate the install."
  echo "After validation, optionally install python3-flask and enable train-recorder-dashboard.service."
  echo "After validation, optionally enable train-recorder-wifi-check.timer."
fi

echo
echo "Install pass complete."
echo
echo "Next manual steps:"
echo "  1. Configure rclone as $RUN_USER if using OneDrive offload."
echo "  2. Run: sudo $INSTALL_DIR/Scripts/site_config.sh wizard"
echo "  3. Run: sudo $INSTALL_DIR/Scripts/site_config.sh generate"
echo "  4. Run: sudo $INSTALL_DIR/Scripts/site_config.sh plan"
echo "  5. Run: sudo $INSTALL_DIR/Scripts/site_config.sh diff"
echo "  6. Run: sudo $INSTALL_DIR/Scripts/site_config.sh apply"
echo "  7. Validate the install:"
echo "     sudo $INSTALL_DIR/Scripts/site_config.sh doctor"
echo "  8. Optional quick status views:"
echo "     sudo $INSTALL_DIR/Scripts/status_summary.sh"
echo "     sudo $INSTALL_DIR/Scripts/health_check.sh"
echo "     $INSTALL_DIR/Scripts/status_json.py"
echo "  9. Optional dashboard:"
echo "     sudo apt install python3-flask"
echo "     sudo systemctl enable --now train-recorder-dashboard.service"
echo " 10. Optional Wi-Fi/network check timer:"
echo "     sudo systemctl enable --now train-recorder-wifi-check.timer"
