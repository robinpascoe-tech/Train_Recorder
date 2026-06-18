#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TRAIN_RECORDER_SCRIPT_DIR="$script_dir" python3 "$script_dir/site_config.py" "$@"
