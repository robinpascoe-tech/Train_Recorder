#!/usr/bin/env bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/home/pi/Recordings}"
RCLONE_REMOTE="${RCLONE_REMOTE:-onedrive:ONR/ONR_Tower3_NewLiskeard}"
RCLONE_MIN_AGE="${RCLONE_MIN_AGE:-15s}"

# rclone move preserves the dated directory structure under RECORDINGS_DIR and
# removes local files only after successful transfer. The min-age guard keeps
# rclone from touching a file that SOX has only just closed.
rclone move -v --min-age "$RCLONE_MIN_AGE" "$RECORDINGS_DIR" "$RCLONE_REMOTE"
