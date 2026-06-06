#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/train-recorder}"
CONFIG_DIR="${CONFIG_DIR:-/etc/train-recorder}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/home/pi/Recordings}"
RAMDISK_DIR="${RAMDISK_DIR:-/mnt/ramdisk}"
RUN_USER="${RUN_USER:-pi}"
RUN_GROUP="${RUN_GROUP:-pi}"
VOX_CHANNELS="${VOX_CHANNELS:-freq160545,freq161265}"
RTL_AIRBAND_REPO="${RTL_AIRBAND_REPO:-https://github.com/rtl-airband/RTLSDR-Airband.git}"
RTL_AIRBAND_REF="${RTL_AIRBAND_REF:-v5.2.0}"
RTL_AIRBAND_PLATFORM="${RTL_AIRBAND_PLATFORM:-native}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APT_UPDATED=0

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix answer

  case "$default" in
    y|Y) suffix='[Y/n]' ;;
    *) suffix='[y/N]' ;;
  esac

  read -r -p "$prompt $suffix " answer
  answer="${answer:-$default}"

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_apt_update() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    "${SUDO[@]}" apt-get update
    APT_UPDATED=1
  fi
}

install_packages() {
  local packages=("$@")
  run_apt_update
  "${SUDO[@]}" apt-get install -y "${packages[@]}"
}

copy_if_missing() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"

  if [[ -e "$dest" ]]; then
    echo "keep existing $dest"
  else
    "${SUDO[@]}" install -D -m "$mode" "$src" "$dest"
    echo "installed $dest"
  fi
}

install_with_backup() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"
  local backup

  if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest"; then
    backup="${dest}.bak-$(date +%Y%m%d-%H%M%S)"
    "${SUDO[@]}" cp "$dest" "$backup"
    echo "backed up $dest to $backup"
  fi

  "${SUDO[@]}" install -D -m "$mode" "$src" "$dest"
  echo "installed $dest"
}

install_repo_files() {
  echo
  echo "Installing project files to $INSTALL_DIR"

  "${SUDO[@]}" mkdir -p "$INSTALL_DIR"

  if [[ "$(cd "$REPO_ROOT" && pwd -P)" != "$(cd "$INSTALL_DIR" 2>/dev/null && pwd -P || true)" ]]; then
    if ! command -v rsync >/dev/null 2>&1; then
      echo "rsync is required for project file installation; installing it now."
      install_packages rsync
    fi

    "${SUDO[@]}" rsync -a \
      --exclude '.git/' \
      --exclude 'Config/rtl_airband.conf' \
      "$REPO_ROOT"/ "$INSTALL_DIR"/
  else
    echo "repo already appears to be at $INSTALL_DIR"
  fi

  "${SUDO[@]}" chmod +x "$INSTALL_DIR"/Scripts/*.sh
  "${SUDO[@]}" chown -R "$RUN_USER:$RUN_GROUP" "$INSTALL_DIR"
}

install_pulseaudio_config() {
  local src="$INSTALL_DIR/Config/system.pa"
  local dest="/etc/pulse/system.pa"
  local sample="/etc/pulse/system.pa.train-recorder.example"

  if [[ ! -e "$dest" ]]; then
    copy_if_missing "$src" "$dest"
  elif cmp -s "$src" "$dest"; then
    echo "keep existing $dest; already matches train-recorder config"
  elif ask_yes_no "$dest already exists. Back it up and replace it with the train-recorder PulseAudio system config?"; then
    install_with_backup "$src" "$dest"
  else
    "${SUDO[@]}" install -D -m 0644 "$src" "$sample"
    echo "kept existing $dest"
    echo "wrote train-recorder sample to $sample"
  fi
}

install_local_configs() {
  echo
  echo "Installing local config files without overwriting existing files"

  "${SUDO[@]}" mkdir -p "$CONFIG_DIR"
  copy_if_missing "$INSTALL_DIR/Config/common.env.example" "$CONFIG_DIR/common.env"
  copy_if_missing "$INSTALL_DIR/Config/freq160545.env.example" "$CONFIG_DIR/freq160545.env"
  copy_if_missing "$INSTALL_DIR/Config/freq161265.env.example" "$CONFIG_DIR/freq161265.env"
  copy_if_missing "$INSTALL_DIR/Config/sync.env.example" "$CONFIG_DIR/sync.env"
  copy_if_missing "$INSTALL_DIR/Config/rtl_airband.conf.example" "/usr/local/etc/rtl_airband.conf"
  install_pulseaudio_config
}

prepare_directories() {
  echo
  echo "Preparing runtime directories"

  "${SUDO[@]}" mkdir -p "$RECORDINGS_DIR" "$RAMDISK_DIR" /usr/local/etc
  "${SUDO[@]}" chown -R "$RUN_USER:$RUN_GROUP" "$RECORDINGS_DIR" "$RAMDISK_DIR"
  "${SUDO[@]}" chmod 775 "$RECORDINGS_DIR"
}

install_systemd_units() {
  echo
  echo "Installing systemd units"

  local unit

  for unit in "$INSTALL_DIR"/Service_Files/*.service "$INSTALL_DIR"/Service_Files/*.timer; do
    install_with_backup "$unit" "/etc/systemd/system/$(basename "$unit")"
  done

  "${SUDO[@]}" systemctl daemon-reload
}

configured_vox_channels() {
  local channels="$VOX_CHANNELS"

  if [[ -f "$CONFIG_DIR/common.env" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_DIR/common.env"
    channels="$VOX_CHANNELS"
  fi

  channels="${channels//,/ }"
  printf '%s\n' $channels
}

install_sox() {
  install_packages sox libsox-fmt-mp3
}

install_pulseaudio() {
  install_packages pulseaudio pulseaudio-utils
}

install_rclone() {
  install_packages rclone
}

install_rtlsdr_runtime() {
  install_packages rtl-sdr librtlsdr-dev
}

build_rtlsdr_airband() {
  local build_root source_dir build_dir

  build_root="$(mktemp -d /tmp/rtlsdr-airband-build.XXXXXX)"
  source_dir="$build_root/source"
  build_dir="$source_dir/build"

  echo
  echo "Building RTLSDR-Airband from $RTL_AIRBAND_REPO ($RTL_AIRBAND_REF)"
  echo "This will install or replace /usr/local/bin/rtl_airband."

  install_packages \
    git \
    build-essential \
    cmake \
    pkg-config \
    libmp3lame-dev \
    libshout3-dev \
    'libconfig++-dev' \
    libfftw3-dev \
    librtlsdr-dev \
    libpulse-dev

  git clone "$RTL_AIRBAND_REPO" "$source_dir"
  git -C "$source_dir" checkout "$RTL_AIRBAND_REF"
  mkdir -p "$build_dir"

  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPLATFORM="$RTL_AIRBAND_PLATFORM" \
    -DRTLSDR=ON \
    -DMIRISDR=OFF \
    -DSOAPYSDR=OFF \
    -DNFM=ON \
    -DPULSEAUDIO=ON

  cmake --build "$build_dir" --parallel "$(nproc)"
  "${SUDO[@]}" cmake --install "$build_dir"

  if command -v rtl_airband >/dev/null 2>&1; then
    rtl_airband -h >/dev/null 2>&1 || true
    echo "rtl_airband installed at $(command -v rtl_airband)"
  fi

  echo "source build left at $build_root for review"
}

enable_core_services() {
  local channel

  "${SUDO[@]}" systemctl enable pulseaudio.service rtl_airband.service

  for channel in $(configured_vox_channels); do
    "${SUDO[@]}" systemctl enable "vox@${channel}.service"
  done
}

start_core_services() {
  local channel

  "${SUDO[@]}" systemctl start pulseaudio.service
  "${SUDO[@]}" systemctl start rtl_airband.service

  for channel in $(configured_vox_channels); do
    "${SUDO[@]}" systemctl start "vox@${channel}.service"
  done
}

enable_optional_timers() {
  "${SUDO[@]}" systemctl enable --now train-recorder-health.timer
  "${SUDO[@]}" systemctl enable --now train-recorder-sync.timer
  "${SUDO[@]}" systemctl enable --now train-recorder-cleanup.timer
}

echo "Train Recorder installer"
echo "Repo root:    $REPO_ROOT"
echo "Install dir:  $INSTALL_DIR"
echo "Config dir:   $CONFIG_DIR"
echo
echo "This installer is conservative: it does not overwrite existing env files,"
echo "RTLSDR-Airband config, PulseAudio config, or rclone credentials without asking."

if ask_yes_no "Install/update apt helper packages used by the installer?"; then
  install_packages rsync git ca-certificates
fi

if ask_yes_no "Install SOX with MP3 support?"; then
  install_sox
fi

if ask_yes_no "Install PulseAudio packages?"; then
  install_pulseaudio
fi

if ask_yes_no "Install rclone from apt?"; then
  install_rclone
fi

if ask_yes_no "Install RTL-SDR runtime and development packages?"; then
  install_rtlsdr_runtime
fi

if ask_yes_no "Build and install RTLSDR-Airband from source with RTLSDR, NFM, PulseAudio, libshout, and LAME support?"; then
  build_rtlsdr_airband
fi

install_repo_files
prepare_directories
install_local_configs
install_systemd_units

echo
echo "RAM disk note:"
echo "  For persistent RAM disk setup, add this to /etc/fstab if it is not present:"
echo "  tmpfs $RAMDISK_DIR tmpfs nodev,nosuid,size=50M 0 0"

if ask_yes_no "Enable core recorder services at boot?"; then
  enable_core_services
fi

if ask_yes_no "Start core recorder services now?"; then
  start_core_services
fi

if ask_yes_no "Enable health, sync, and cleanup timers now?"; then
  enable_optional_timers
fi

echo
echo "Install pass complete."
echo
echo "Next manual steps:"
echo "  1. Edit /usr/local/etc/rtl_airband.conf with local Broadcastify/Icecast settings."
echo "  2. Edit $CONFIG_DIR/*.env for local paths, rclone remote, and channel tuning."
echo "  3. Configure rclone as $RUN_USER if using OneDrive offload."
echo "  4. Verify with:"
echo "     sudo $INSTALL_DIR/Scripts/health_check.sh"
echo "     sudo $INSTALL_DIR/Scripts/status_summary.sh"
