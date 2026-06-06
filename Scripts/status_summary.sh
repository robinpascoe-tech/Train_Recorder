#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
CLIPPING_WINDOW_MINUTES="${CLIPPING_WINDOW_MINUTES:-1440}"
JOURNAL_WINDOW_MINUTES="${JOURNAL_WINDOW_MINUTES:-10080}"
VOX1_SERVICE="${VOX1_SERVICE:-vox@freq160545.service}"
VOX2_SERVICE="${VOX2_SERVICE:-vox@freq161265.service}"
VOX1_JOURNAL_UNITS="${VOX1_JOURNAL_UNITS:-$VOX1_SERVICE vox.service}"
VOX2_JOURNAL_UNITS="${VOX2_JOURNAL_UNITS:-$VOX2_SERVICE vox2.service}"

if [[ -f /etc/train-recorder/common.env ]]; then
  # shellcheck disable=SC1091
  source /etc/train-recorder/common.env
fi

if [[ -f /etc/train-recorder/sync.env ]]; then
  # shellcheck disable=SC1091
  source /etc/train-recorder/sync.env
fi

now_epoch="$(date +%s)"

age_text() {
  local epoch="$1"
  local age=$((now_epoch - epoch))

  if (( age < 60 )); then
    printf '%ss ago' "$age"
  elif (( age < 3600 )); then
    printf '%sm ago' "$((age / 60))"
  elif (( age < 86400 )); then
    printf '%sh %sm ago' "$((age / 3600))" "$(((age % 3600) / 60))"
  else
    printf '%sd %sh ago' "$((age / 86400))" "$(((age % 86400) / 3600))"
  fi
}

last_matching_journal() {
  local units="$1"
  local pattern="$2"
  local logs="" unit

  for unit in $units; do
    logs+="$(journalctl -u "$unit" --since "$JOURNAL_WINDOW_MINUTES minutes ago" --no-pager -o short-unix 2>/dev/null || true)"
    logs+=$'\n'
  done

  grep -E "$pattern" <<<"$logs" | sort -n | tail -1 || true
}

last_event_summary() {
  local label="$1"
  local unit="$2"
  local pattern="$3"
  local line epoch message

  line="$(last_matching_journal "$unit" "$pattern")"
  if [[ -z "$line" ]]; then
    printf '%-18s none found in %s minutes\n' "$label:" "$JOURNAL_WINDOW_MINUTES"
    return
  fi

  epoch="${line%% *}"
  epoch="${epoch%%.*}"
  message="${line#*]: }"
  if [[ "$message" == "$line" ]]; then
    message="${line#* }"
  fi

  printf '%-18s %s (%s)\n' "$label:" "$(age_text "$epoch")" "$message"
}

service_summary() {
  local services=(
    pulseaudio.service
    rtl_airband.service
    "$VOX1_SERVICE"
    "$VOX2_SERVICE"
    train-recorder-sync.timer
    train-recorder-health.timer
    train-recorder-cleanup.timer
  )
  local failures=()
  local service state

  for service in "${services[@]}"; do
    state="$(systemctl is-active "$service" 2>/dev/null || true)"
    if [[ "$state" != "active" ]]; then
      failures+=("$service=$state")
    fi
  done

  if ((${#failures[@]} == 0)); then
    echo "Services:          ok"
  else
    echo "Services:          attention ${failures[*]}"
  fi
}

pending_recordings_summary() {
  local count total_bytes

  count="$(find "$OUTPUT_ROOT" -type f -name '*.mp3' 2>/dev/null | wc -l | awk '{print $1}')"
  total_bytes="$(find "$OUTPUT_ROOT" -type f -name '*.mp3' -printf '%s\n' 2>/dev/null | awk '{sum += $1} END {print sum + 0}')"

  printf 'Pending local MP3s:%7s files (%s bytes)\n' "$count" "$total_bytes"
}

clipping_summary() {
  local label="$1"
  local units="$2"
  local logs="" unit count max

  for unit in $units; do
    logs+="$(journalctl -u "$unit" --since "$CLIPPING_WINDOW_MINUTES minutes ago" --no-pager 2>/dev/null || true)"
    logs+=$'\n'
  done

  count="$(grep -c 'balancing clipped' <<<"$logs" || true)"
  max="$(grep 'balancing clipped' <<<"$logs" \
    | sed -E 's/.*balancing clipped ([0-9]+) samples.*/\1/' \
    | sort -n \
    | tail -1 || true)"
  max="${max:-0}"

  printf '%-18s %s warnings, max %s samples in %s minutes\n' "$label:" "$count" "$max" "$CLIPPING_WINDOW_MINUTES"
}

disk_summary() {
  local root_line temp_line

  root_line="$(df -h "$OUTPUT_ROOT" 2>/dev/null | awk 'NR == 2 {print $5 " used, " $4 " free on " $6}')"
  temp_line="$(df -h "$TEMP_DIR" 2>/dev/null | awk 'NR == 2 {print $5 " used, " $4 " free on " $6}')"

  printf '%-18s %s\n' "Disk:" "${root_line:-unavailable}"
  printf '%-18s %s\n' "RAM disk:" "${temp_line:-unavailable}"
}

echo "Train Recorder Status"
echo "Generated:         $(date)"
echo
service_summary
last_event_summary "Last 160.545 save" "$VOX1_JOURNAL_UNITS" 'Saved .*_160\.545\.mp3'
last_event_summary "Last 161.265 save" "$VOX2_JOURNAL_UNITS" 'Saved .*_161\.265\.mp3'
last_event_summary "Last sync" train-recorder-sync.service 'Finished train-recorder-sync\.service'
last_event_summary "Last cleanup" train-recorder-cleanup.service 'Finished train-recorder-cleanup\.service'
pending_recordings_summary
clipping_summary "Clipping 160.545" "$VOX1_JOURNAL_UNITS"
clipping_summary "Clipping 161.265" "$VOX2_JOURNAL_UNITS"
disk_summary
