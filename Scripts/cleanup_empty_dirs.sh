#!/usr/bin/env bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/home/pi/Recordings}"

if [[ ! -d "$RECORDINGS_DIR" ]]; then
  echo "fail recordings directory does not exist: $RECORDINGS_DIR" >&2
  exit 1
fi

# rclone intentionally leaves the date folder tree behind after moving files.
# Clean empty folders separately so the frequent sync job does not churn the
# current day's directories after every transmission. Walk deepest-first so an
# empty day/month/year branch can be removed in one cleanup run.
mapfile -d '' deleted_dirs < <(find "$RECORDINGS_DIR" -mindepth 1 -depth -type d -empty -print0 -delete)

echo "ok cleanup removed ${#deleted_dirs[@]} empty directories under $RECORDINGS_DIR"
