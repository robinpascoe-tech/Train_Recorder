#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
PULSE_SERVER="${PULSE_SERVER:-unix:/run/pulse/native}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
MAX_RECORDING_AGE_MINUTES="${MAX_RECORDING_AGE_MINUTES:-1440}"

status=0

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

check_service pulseaudio.service
check_service rtl_airband.service
check_service vox.service
check_service vox2.service

check_path "$OUTPUT_ROOT"
check_path "$TEMP_DIR"

check_pulse_source myfreq1sink.monitor
check_pulse_source myfreq2sink.monitor

if find "$OUTPUT_ROOT" -type f -name '*.mp3' -mmin "-$MAX_RECORDING_AGE_MINUTES" -print -quit | grep -q .; then
  echo "ok recent recording within ${MAX_RECORDING_AGE_MINUTES} minutes"
else
  echo "warn no recent recordings within ${MAX_RECORDING_AGE_MINUTES} minutes" >&2
fi

df -h "$OUTPUT_ROOT" "$TEMP_DIR"

exit "$status"
