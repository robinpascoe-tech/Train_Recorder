#!/usr/bin/env bash
set -euo pipefail

RECORDINGS_DIR="${RECORDINGS_DIR:-/home/pi/Recordings}"
RCLONE_REMOTE="${RCLONE_REMOTE:-onedrive:ONR/ONR_Tower3_NewLiskeard}"

rclone move -v "$RECORDINGS_DIR" "$RCLONE_REMOTE"
