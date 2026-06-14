#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"

if [[ -f "$CONFIG_DIR/common.env" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/common.env"
fi

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
PULSE_SERVER="${PULSE_SERVER:-unix:/run/pulse/native}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
MAX_RECORDING_AGE_MINUTES="${MAX_RECORDING_AGE_MINUTES:-1440}"
CHECK_RECENT_LOCAL_RECORDINGS="${CHECK_RECENT_LOCAL_RECORDINGS:-false}"
CHECK_RECENT_SYNC_SUCCESS="${CHECK_RECENT_SYNC_SUCCESS:-true}"
MAX_SYNC_SUCCESS_AGE_MINUTES="${MAX_SYNC_SUCCESS_AGE_MINUTES:-30}"

status=0

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

check_service() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    echo "ok service $service"
  else
    echo "fail service $service is not active" >&2
    status=1
  fi
}

check_path() {
  local path="$1"
  if [[ -d "$path" && -w "$path" ]]; then
    echo "ok writable $path"
  else
    echo "fail $path is not a writable directory" >&2
    status=1
  fi
}

check_pulse_source() {
  local source="$1"
  if PULSE_SERVER="$PULSE_SERVER" pactl list short sources 2>/dev/null | awk '{print $2}' | grep -Fxq "$source"; then
    echo "ok pulse source $source"
  else
    echo "fail pulse source $source not found" >&2
    status=1
  fi
}

regex_escape() {
  sed -E 's/[][(){}.^$*+?|\\]/\\&/g' <<<"$1"
}

check_recent_journal() {
  local units="$1"
  local minutes="$2"
  local pattern="$3"
  local label="$4"
  local severity="${5:-warn}"
  local logs="" unit

  for unit in $units; do
    logs+="$(journalctl -u "$unit" --since "$minutes minutes ago" --no-pager 2>/dev/null || true)"
    logs+=$'\n'
  done

  if grep -Eq "$pattern" <<<"$logs"; then
    echo "ok recent $label within ${minutes} minutes"
  elif [[ "$severity" == "fail" ]]; then
    echo "fail no recent $label within ${minutes} minutes" >&2
    status=1
  else
    echo "warn no recent $label within ${minutes} minutes" >&2
  fi
}

channels_list() {
  local channels="${VOX_CHANNELS//,/ }"
  local channel_array=()

  read -r -a channel_array <<<"$channels"
  printf '%s\n' "${channel_array[@]}"
}

legacy_recent_save_default() {
  local channel="$1"

  case "$channel" in
    freq160545) printf '%s\n' "${CHECK_VOX1_RECENT_SAVE:-true}" ;;
    freq161265) printf '%s\n' "${CHECK_VOX2_RECENT_SAVE:-false}" ;;
    *) printf 'true\n' ;;
  esac
}

legacy_max_save_age_default() {
  local channel="$1"

  case "$channel" in
    freq160545) printf '%s\n' "${MAX_VOX1_SAVE_AGE_MINUTES:-1440}" ;;
    freq161265) printf '%s\n' "${MAX_VOX2_SAVE_AGE_MINUTES:-4320}" ;;
    *) printf '1440\n' ;;
  esac
}

legacy_journal_units() {
  local channel="$1"
  local service="$2"

  case "$channel" in
    freq160545) printf '%s vox.service\n' "$service" ;;
    freq161265) printf '%s vox2.service\n' "$service" ;;
    *) printf '%s\n' "$service" ;;
  esac
}

check_channel() {
  local channel="$1"
  local PULSE_MONITOR=""
  local OUTPUT_SUFFIX="_$channel"
  local FREQUENCY_MHZ=""
  local HEALTH_CHECK_RECENT_SAVE=""
  local MAX_SAVE_AGE_MINUTES=""
  local JOURNAL_UNITS=""
  local env_file="$CONFIG_DIR/$channel.env"
  local service="vox@${channel}.service"
  local label pattern

  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  else
    echo "fail channel env file missing: $env_file" >&2
    status=1
    return
  fi

  label="${FREQUENCY_MHZ:-${OUTPUT_SUFFIX#_}}"
  HEALTH_CHECK_RECENT_SAVE="${HEALTH_CHECK_RECENT_SAVE:-$(legacy_recent_save_default "$channel")}"
  MAX_SAVE_AGE_MINUTES="${MAX_SAVE_AGE_MINUTES:-$(legacy_max_save_age_default "$channel")}"
  JOURNAL_UNITS="${JOURNAL_UNITS:-$(legacy_journal_units "$channel" "$service")}"

  check_service "$service"

  if [[ -n "$PULSE_MONITOR" ]]; then
    check_pulse_source "$PULSE_MONITOR"
  else
    echo "fail $channel has no PULSE_MONITOR" >&2
    status=1
  fi

  if is_true "$HEALTH_CHECK_RECENT_SAVE"; then
    pattern="Saved .*$(regex_escape "$OUTPUT_SUFFIX")\\.mp3"
    check_recent_journal "$JOURNAL_UNITS" "$MAX_SAVE_AGE_MINUTES" "$pattern" "$label recording save"
  else
    echo "ok recent $label recording save check disabled"
  fi
}

check_service pulseaudio.service
check_service rtl_airband.service

check_path "$OUTPUT_ROOT"
check_path "$TEMP_DIR"

while IFS= read -r channel; do
  [[ -n "$channel" ]] && check_channel "$channel"
done < <(channels_list)

if is_true "$CHECK_RECENT_SYNC_SUCCESS"; then
  check_recent_journal train-recorder-sync.service "$MAX_SYNC_SUCCESS_AGE_MINUTES" 'Finished train-recorder-sync\.service' 'sync service success' fail
else
  echo "ok recent sync success check disabled"
fi

# In the production layout, rclone moves completed files out of OUTPUT_ROOT every
# few minutes. Keep the local-recency check opt-in so normal sync behavior does
# not look like a recorder problem.
case "$CHECK_RECENT_LOCAL_RECORDINGS" in
  true|TRUE|1|yes|YES)
    if find "$OUTPUT_ROOT" -type f -name '*.mp3' -mmin "-$MAX_RECORDING_AGE_MINUTES" -print -quit | grep -q .; then
      echo "ok recent local recording within ${MAX_RECORDING_AGE_MINUTES} minutes"
    else
      echo "warn no recent local recordings within ${MAX_RECORDING_AGE_MINUTES} minutes" >&2
    fi
    ;;
  *)
    echo "ok recent local recording check disabled"
    ;;
esac

df -h "$OUTPUT_ROOT" "$TEMP_DIR"

exit "$status"
