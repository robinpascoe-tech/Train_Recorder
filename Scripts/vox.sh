#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Channel defaults. systemd EnvironmentFile values can override any of these.
export CHANNEL_NAME="${CHANNEL_NAME:-freq160545}"
export PULSE_MONITOR="${PULSE_MONITOR:-myfreq1sink.monitor}"
export OUTPUT_SUFFIX="${OUTPUT_SUFFIX:-_160.545}"
export START_DURATION="${START_DURATION:-0.2}"
export MIN_BYTES="${MIN_BYTES:-700}"

exec "$SCRIPT_DIR/vox_record.sh"
