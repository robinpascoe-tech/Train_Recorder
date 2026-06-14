#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"
INSTALL_DIR="${INSTALL_DIR:-/opt/train-recorder}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
RUN_USER="${RUN_USER:-pi}"
SINCE="${SINCE:-24 hours ago}"
OUT_DIR="${OUT_DIR:-/tmp}"

timestamp="$(date +%Y%m%d-%H%M%S)"
hostname_short="$(hostname -s 2>/dev/null || hostname)"
bundle_dir="$OUT_DIR/train-recorder-diagnostics-${hostname_short}-${timestamp}"
bundle_tar="${bundle_dir}.tar.gz"

mkdir -p "$bundle_dir"/{commands,configs,logs}
chmod 700 "$bundle_dir"

write_file() {
  local relpath="$1"
  shift
  {
    printf '# Generated: %s\n' "$(date)"
    printf '# Command: %s\n\n' "$*"
    "$@" 2>&1 || true
  } >"$bundle_dir/$relpath"
}

copy_file() {
  local src="$1"
  local dest="$2"

  if [[ -f "$src" ]]; then
    cp "$src" "$bundle_dir/$dest"
  else
    printf 'missing: %s\n' "$src" >"$bundle_dir/$dest"
  fi
}

redact_stream() {
  sed -E \
    -e 's/(password[[:space:]]*=[[:space:]]*)("[^"]*"|[^;[:space:]]+)/\1"REDACTED"/Ig' \
    -e 's/(mountpoint[[:space:]]*=[[:space:]]*)("[^"]*"|[^;[:space:]]+)/\1"REDACTED"/Ig' \
    -e 's/(client_secret[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(token[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(access_token[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(refresh_token[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(api[_-]?key[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(secret[[:space:]]*[:=][[:space:]]*)[^[:space:]#]+/\1REDACTED/Ig' \
    -e 's/(password:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(mountpoint:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(client_secret:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(token:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(access_token:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(refresh_token:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(api[_-]?key:[[:space:]]*).*/\1REDACTED/Ig' \
    -e 's/(secret:[[:space:]]*).*/\1REDACTED/Ig'
}

copy_redacted() {
  local src="$1"
  local dest="$2"

  if [[ -f "$src" ]]; then
    redact_stream <"$src" >"$bundle_dir/$dest"
  else
    printf 'missing: %s\n' "$src" >"$bundle_dir/$dest"
  fi
}

source_runtime_env() {
  if [[ -f "$CONFIG_DIR/common.env" ]]; then
    # shellcheck disable=SC1091
    source "$CONFIG_DIR/common.env"
  fi
  if [[ -f "$CONFIG_DIR/sync.env" ]]; then
    # shellcheck disable=SC1091
    source "$CONFIG_DIR/sync.env"
  fi
  OUTPUT_ROOT="${OUTPUT_ROOT:-/home/pi/Recordings}"
  TEMP_DIR="${TEMP_DIR:-/mnt/ramdisk}"
  VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
}

source_runtime_env

cat >"$bundle_dir/README.txt" <<EOF
Train Recorder diagnostics bundle
Generated: $(date)
Host: $hostname_short

This bundle is intended for support and troubleshooting.
Known sensitive config fields are redacted from copied configs, but review
the bundle before sharing it publicly.

Journal lookback: $SINCE
EOF

write_file commands/os-release cat /etc/os-release
write_file commands/uname uname -a
write_file commands/uptime uptime
write_file commands/date date
write_file commands/git-status git -C "$INSTALL_DIR" status --short --branch
write_file commands/git-log git -C "$INSTALL_DIR" log --oneline -n 20
write_file commands/service-active systemctl is-active \
  pulseaudio.service rtl_airband.service train-recorder-sync.timer \
  train-recorder-health.timer train-recorder-cleanup.timer
write_file commands/service-enabled systemctl is-enabled \
  pulseaudio.service rtl_airband.service train-recorder-sync.timer \
  train-recorder-health.timer train-recorder-cleanup.timer
write_file commands/vox-units systemctl list-units 'vox@*.service' --all --no-pager
write_file commands/train-recorder-timers systemctl list-timers --all --no-pager
write_file commands/legacy-vox systemctl status --no-pager --full vox.service vox2.service
write_file commands/processes ps -eo user,group,pid,ppid,stime,cmd
write_file commands/df df -h
write_file commands/df-inodes df -ih
write_file commands/var-log-usage sh -c 'df -h /var/log 2>/dev/null; du -h --max-depth=2 /var/log 2>/dev/null | sort -h | tail -40'
write_file commands/journal-usage journalctl --disk-usage
# shellcheck disable=SC2016
write_file commands/packages dpkg-query -W -f='${Package}\t${Version}\n' \
  git rsync sox libsox-fmt-mp3 libsox-fmt-pulse pulseaudio pulseaudio-utils \
  rclone rtl-sdr librtlsdr-dev libpulse-dev libmp3lame-dev libshout3-dev \
  'libconfig++-dev' libfftw3-dev
write_file commands/user-groups sh -c "id $RUN_USER; id root; getent group pulse pulse-access audio || true"
write_file commands/pulse-sinks pactl -s "${PULSE_SERVER:-unix:/run/pulse/native}" list short sinks
write_file commands/pulse-sources pactl -s "${PULSE_SERVER:-unix:/run/pulse/native}" list short sources
write_file commands/user-pulseaudio sh -c "uid=\$(id -u $RUN_USER 2>/dev/null || true); if [ -n \"\$uid\" ] && [ -d \"/run/user/\$uid\" ]; then sudo -u $RUN_USER XDG_RUNTIME_DIR=/run/user/\$uid systemctl --user status --no-pager --full pulseaudio.service pulseaudio.socket; else echo 'no active user runtime for $RUN_USER'; fi"
write_file commands/pcp-state systemctl is-active pmcd pmlogger pmie pmproxy
write_file commands/raspibackup-state sh -c "systemctl list-timers --all --no-pager | grep -i raspibackup || true; systemctl status --no-pager --full raspiBackup.service raspiBackup.timer 2>/dev/null || true"
write_file commands/recording-tree sh -c "find '$OUTPUT_ROOT' -maxdepth 4 -printf '%M %u:%g %p\n' 2>/dev/null | head -200"
write_file commands/recording-counts sh -c "printf 'mp3_count='; find '$OUTPUT_ROOT' -type f -name '*.mp3' 2>/dev/null | wc -l; printf 'root_owned_mp3_count='; find '$OUTPUT_ROOT' -type f -name '*.mp3' -user root 2>/dev/null | wc -l; du -sh '$OUTPUT_ROOT' '$TEMP_DIR' 2>/dev/null || true"

if [[ -x "$INSTALL_DIR/Scripts/status_summary.sh" ]]; then
  write_file commands/status-summary "$INSTALL_DIR/Scripts/status_summary.sh"
fi
if [[ -x "$INSTALL_DIR/Scripts/site_config.sh" ]]; then
  write_file commands/doctor "$INSTALL_DIR/Scripts/site_config.sh" doctor
elif [[ -x "$INSTALL_DIR/Scripts/doctor.sh" ]]; then
  write_file commands/doctor "$INSTALL_DIR/Scripts/doctor.sh"
fi
if [[ -x "$INSTALL_DIR/Scripts/health_check.sh" ]]; then
  write_file commands/health-check "$INSTALL_DIR/Scripts/health_check.sh"
fi

if [[ -n "${RCLONE_REMOTE:-}" ]]; then
  write_file commands/rclone-about sudo -u "$RUN_USER" rclone about "$RCLONE_REMOTE"
  write_file commands/rclone-lsd sudo -u "$RUN_USER" rclone lsd "$RCLONE_REMOTE"
else
  printf 'RCLONE_REMOTE is not configured.\n' >"$bundle_dir/commands/rclone-about"
  printf 'RCLONE_REMOTE is not configured.\n' >"$bundle_dir/commands/rclone-lsd"
fi

for unit in \
  pulseaudio.service rtl_airband.service \
  train-recorder-sync.service train-recorder-health.service train-recorder-cleanup.service \
  train-recorder-sync.timer train-recorder-health.timer train-recorder-cleanup.timer \
  raspiBackup.service raspiBackup.timer; do
  write_file "logs/${unit}.journal" journalctl -u "$unit" --since "$SINCE" --no-pager
done

channels="${VOX_CHANNELS//,/ }"
for channel in $channels; do
  write_file "logs/vox@${channel}.service.journal" journalctl -u "vox@${channel}.service" --since "$SINCE" --no-pager
done

copy_redacted "$CONFIG_DIR/site.yaml" configs/site.yaml.redacted
copy_redacted "$CONFIG_DIR/common.env" configs/common.env.redacted
copy_redacted "$CONFIG_DIR/sync.env" configs/sync.env.redacted
for channel in $channels; do
  copy_redacted "$CONFIG_DIR/$channel.env" "configs/${channel}.env.redacted"
done
copy_redacted /usr/local/etc/rtl_airband.conf configs/rtl_airband.conf.redacted
copy_file /etc/pulse/system.pa configs/system.pa
copy_file /etc/systemd/system/vox@.service configs/vox@.service
copy_file /etc/systemd/system/pulseaudio.service configs/pulseaudio.service
copy_file /etc/systemd/system/rtl_airband.service configs/rtl_airband.service
copy_redacted /usr/local/etc/raspiBackup.conf configs/raspiBackup.conf.redacted

find "$bundle_dir" -type f -exec chmod 600 {} +
tar -C "$OUT_DIR" -czf "$bundle_tar" "$(basename "$bundle_dir")"
rm -rf "$bundle_dir"
chmod 600 "$bundle_tar"
if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
  chown "$SUDO_UID:$SUDO_GID" "$bundle_tar" 2>/dev/null || true
fi

echo "Diagnostics bundle written to:"
echo "$bundle_tar"
echo "Review before sharing; sensitive known config fields were redacted."
