#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"
INSTALL_DIR="${INSTALL_DIR:-/opt/train-recorder}"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:8080}"
JOURNAL_SINCE="${JOURNAL_SINCE:-today}"

failures=0
warnings=0

section() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  printf 'ok   %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'warn %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'fail %s\n' "$1"
}

run_required() {
  local label="$1"
  shift

  if "$@"; then
    ok "$label"
  else
    fail "$label"
  fi
}

run_optional() {
  local label="$1"
  shift

  if "$@"; then
    ok "$label"
  else
    warn "$label"
  fi
}

run_doctor() {
  local label="$1"
  shift
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  printf '%s\n' "$output"
  if ((status == 0)); then
    ok "$label"
  else
    fail "$label"
  fi

  if [[ "$output" =~ Doctor[[:space:]]summary:[[:space:]]([0-9]+)[[:space:]]failure\(s\),[[:space:]]([0-9]+)[[:space:]]warning\(s\) ]]; then
    warnings=$((warnings + BASH_REMATCH[2]))
  fi
}

source_env() {
  if [[ -f "$CONFIG_DIR/common.env" ]]; then
    # shellcheck disable=SC1091
    source "$CONFIG_DIR/common.env"
  fi
  if [[ -f "$CONFIG_DIR/sync.env" ]]; then
    # shellcheck disable=SC1091
    source "$CONFIG_DIR/sync.env"
  fi

  VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
}

channels_list() {
  local channels="${VOX_CHANNELS//,/ }"
  local channel_array=()

  read -r -a channel_array <<<"$channels"
  printf '%s\n' "${channel_array[@]}"
}

service_active() {
  systemctl is-active --quiet "$1"
}

timer_active() {
  systemctl is-active --quiet "$1"
}

dashboard_enabled() {
  systemctl is-enabled --quiet train-recorder-dashboard.service 2>/dev/null
}

wifi_timer_enabled() {
  systemctl is-enabled --quiet train-recorder-wifi-check.timer 2>/dev/null
}

status_history_timer_enabled() {
  systemctl is-enabled --quiet train-recorder-status-history.timer 2>/dev/null
}

http_ok() {
  local url="$1"
  python3 - "$url" <<'PY'
import sys
from urllib.request import urlopen

with urlopen(sys.argv[1], timeout=10) as response:
    raise SystemExit(0 if 200 <= response.status < 300 else 1)
PY
}

source_env

echo "RailWave Pi Deploy Validation"
echo "Generated: $(date)"
echo "Host:      $(hostname)"

section "Git"
if git -C "$INSTALL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$INSTALL_DIR" status --short --branch || true
  printf 'commit: %s\n' "$(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
  if [[ -z "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    ok "worktree is clean"
  else
    fail "worktree has uncommitted changes"
  fi
else
  fail "$INSTALL_DIR is not a git worktree"
fi

section "Services"
run_required "pulseaudio.service active" service_active pulseaudio.service
run_required "rtl_airband.service active" service_active rtl_airband.service
while IFS= read -r channel; do
  [[ -n "$channel" ]] && run_required "vox@${channel}.service active" service_active "vox@${channel}.service"
done < <(channels_list)

section "Timers"
run_required "train-recorder-health.timer active" timer_active train-recorder-health.timer
run_required "train-recorder-cleanup.timer active" timer_active train-recorder-cleanup.timer
if [[ -n "${RCLONE_REMOTE:-}" ]]; then
  run_required "train-recorder-sync.timer active" timer_active train-recorder-sync.timer
else
  run_optional "train-recorder-sync.timer active" timer_active train-recorder-sync.timer
fi
if wifi_timer_enabled; then
  run_required "train-recorder-wifi-check.timer active" timer_active train-recorder-wifi-check.timer
else
  warn "train-recorder-wifi-check.timer not enabled"
fi
if status_history_timer_enabled; then
  run_required "train-recorder-status-history.timer active" timer_active train-recorder-status-history.timer
else
  warn "train-recorder-status-history.timer not enabled"
fi

section "Doctor"
if [[ -x "$INSTALL_DIR/Scripts/site_config.sh" ]]; then
  run_doctor "site_config.sh doctor" "$INSTALL_DIR/Scripts/site_config.sh" doctor
elif [[ -x "$INSTALL_DIR/Scripts/doctor.sh" ]]; then
  run_doctor "doctor.sh" "$INSTALL_DIR/Scripts/doctor.sh"
else
  fail "doctor command missing"
fi

section "Dashboard"
if dashboard_enabled; then
  run_required "train-recorder-dashboard.service active" service_active train-recorder-dashboard.service
  run_required "dashboard HTML responds" http_ok "$DASHBOARD_URL/"
  run_required "dashboard API responds" http_ok "$DASHBOARD_URL/api/status"
else
  warn "train-recorder-dashboard.service not enabled"
fi

section "Wi-Fi And Network"
if [[ -x "$INSTALL_DIR/Scripts/wifi_check.py" ]]; then
  run_optional "wifi_check.py --json --no-write-state" "$INSTALL_DIR/Scripts/wifi_check.py" --json --no-write-state
else
  warn "wifi_check.py missing"
fi

section "Dashboard History"
if [[ -x "$INSTALL_DIR/Scripts/status_history.py" ]]; then
  run_optional "status_history.py --json --no-write" "$INSTALL_DIR/Scripts/status_history.py" --json --no-write
  if dashboard_enabled; then
    run_required "dashboard history API responds" http_ok "$DASHBOARD_URL/api/history"
  fi
else
  warn "status_history.py missing"
fi

section "Recording Diagnostics"
if [[ -x "$INSTALL_DIR/Scripts/recording_diagnostics.py" ]]; then
  run_optional "recording_diagnostics.py --lookback-hours 24 --max-files 5" "$INSTALL_DIR/Scripts/recording_diagnostics.py" --lookback-hours 24 --max-files 5
else
  warn "recording_diagnostics.py missing"
fi

section "Operator Summary"
if [[ -x "$INSTALL_DIR/Scripts/status_summary.sh" ]]; then
  "$INSTALL_DIR/Scripts/status_summary.sh" || warn "status_summary.sh reported attention"
else
  warn "status_summary.sh missing"
fi

section "Recent Logs"
journalctl \
  -u rtl_airband.service \
  -u train-recorder-sync.service \
  -u train-recorder-health.service \
  -u train-recorder-cleanup.service \
  -u train-recorder-dashboard.service \
  -u train-recorder-wifi-check.service \
  --since "$JOURNAL_SINCE" \
  --no-pager \
  -p warning || true

section "Summary"
printf 'failures=%s warnings=%s\n' "$failures" "$warnings"

if ((failures > 0)); then
  exit 1
fi
