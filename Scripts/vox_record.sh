#!/usr/bin/env bash
set -euo pipefail

CHANNEL_NAME="${CHANNEL_NAME:?Set CHANNEL_NAME, for example freq160545}"
PULSE_MONITOR="${PULSE_MONITOR:?Set PULSE_MONITOR, for example myfreq1sink.monitor}"

AUDIO_FORMAT="${AUDIO_FORMAT:-mp3}"
MIN_BYTES="${MIN_BYTES:-700}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
OUTPUT_SUFFIX="${OUTPUT_SUFFIX:-_$CHANNEL_NAME}"
RECORDING_UMASK="${RECORDING_UMASK:-0022}"
SOX_VOLUME="${SOX_VOLUME:-5}"
START_DURATION="${START_DURATION:-0.2}"
START_THRESHOLD="${START_THRESHOLD:-0.1%}"
STOP_DURATION="${STOP_DURATION:-13.0}"
STOP_THRESHOLD="${STOP_THRESHOLD:-0.1%}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"

temp_file=""
umask "$RECORDING_UMASK"

cleanup() {
  if [[ -n "$temp_file" ]]; then
    rm -f -- "$temp_file"
  fi
}

trap 'cleanup; exit 0' INT TERM

mkdir -p "$TEMP_DIR" "$OUTPUT_ROOT"

while true; do
  temp_file="$(mktemp "$TEMP_DIR/${CHANNEL_NAME}.XXXXXX.${AUDIO_FORMAT}")"
  rm -f -- "$temp_file"

  if sox -q -v "$SOX_VOLUME" -t pulseaudio "$PULSE_MONITOR" -t "$AUDIO_FORMAT" "$temp_file" \
    silence -l 1 "$START_DURATION" "$START_THRESHOLD" 1 "$STOP_DURATION" "$STOP_THRESHOLD"; then

    if [[ ! -e "$temp_file" ]]; then
      echo "sox did not produce an output file for $PULSE_MONITOR" >&2
      temp_file=""
      sleep 2
      continue
    fi

    bytes="$(stat -c %s "$temp_file")"
    if [[ "$bytes" -ge "$MIN_BYTES" ]]; then
      name="$(date +%Y-%m-%d_%H-%M-%S)"
      rec_path="$OUTPUT_ROOT/$(date +%Y)/$(date +%m-%b)/$(date +%d-%a)"
      mkdir -p "$rec_path"
      final_file="$rec_path/${name}${OUTPUT_SUFFIX}.${AUDIO_FORMAT}"
      mv -- "$temp_file" "$final_file"
      echo "Saved $final_file ($bytes bytes)"
      temp_file=""
    else
      echo "Discarded short recording from $PULSE_MONITOR ($bytes bytes)"
      cleanup
    fi
  else
    echo "sox exited with an error while recording $PULSE_MONITOR" >&2
    cleanup
    sleep 2
  fi
done
