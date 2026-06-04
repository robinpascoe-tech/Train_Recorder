#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Channel defaults. systemd EnvironmentFile values can override any of these.
export CHANNEL_NAME="${CHANNEL_NAME:-freq161265}"
export PULSE_MONITOR="${PULSE_MONITOR:-myfreq2sink.monitor}"
export OUTPUT_SUFFIX="${OUTPUT_SUFFIX:-_161.265}"
export START_DURATION="${START_DURATION:-0.5}"
export MIN_BYTES="${MIN_BYTES:-800}"

exec "$SCRIPT_DIR/vox_record.sh"
