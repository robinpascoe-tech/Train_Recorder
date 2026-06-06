#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
PULSE_SERVER="${PULSE_SERVER:-unix:/run/pulse/native}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
MAX_RECORDING_AGE_MINUTES="${MAX_RECORDING_AGE_MINUTES:-1440}"
CHECK_RECENT_LOCAL_RECORDINGS="${CHECK_RECENT_LOCAL_RECORDINGS:-false}"
CHECK_VOX1_RECENT_SAVE="${CHECK_VOX1_RECENT_SAVE:-true}"
MAX_VOX1_SAVE_AGE_MINUTES="${MAX_VOX1_SAVE_AGE_MINUTES:-1440}"
CHECK_VOX2_RECENT_SAVE="${CHECK_VOX2_RECENT_SAVE:-false}"
MAX_VOX2_SAVE_AGE_MINUTES="${MAX_VOX2_SAVE_AGE_MINUTES:-4320}"
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

check_recent_journal() {
  local unit="$1"
  local minutes="$2"
  local pattern="$3"
  local label="$4"
  local severity="${5:-warn}"
  local logs

  logs="$(journalctl -u "$unit" --since "$minutes minutes ago" --no-pager 2>/dev/null || true)"

  if grep -Eq "$pattern" <<<"$logs"; then
    echo "ok recent $label within ${minutes} minutes"
  elif [[ "$severity" == "fail" ]]; then
    echo "fail no recent $label within ${minutes} minutes" >&2
    status=1
  else
    echo "warn no recent $label within ${minutes} minutes" >&2
  fi
}

check_service pulseaudio.service
check_service rtl_airband.service
check_service vox.service
check_service vox2.service

check_path "$OUTPUT_ROOT"
check_path "$TEMP_DIR"

check_pulse_source myfreq1sink.monitor
check_pulse_source myfreq2sink.monitor

if is_true "$CHECK_VOX1_RECENT_SAVE"; then
  check_recent_journal vox.service "$MAX_VOX1_SAVE_AGE_MINUTES" 'Saved .*_160\.545\.mp3' '160.545 recording save'
else
  echo "ok recent 160.545 recording save check disabled"
fi

if is_true "$CHECK_VOX2_RECENT_SAVE"; then
  check_recent_journal vox2.service "$MAX_VOX2_SAVE_AGE_MINUTES" 'Saved .*_161\.265\.mp3' '161.265 recording save'
else
  echo "ok recent 161.265 recording save check disabled"
fi

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
