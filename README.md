# RailWave Pi - Rail Radio Monitor & Archive

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

![RailWave Pi logo](docs/assets/railwave-pi-logo.png)

RailWave Pi is a Raspberry Pi rail radio monitor and archive using an RTL-SDR receiver, RTLSDR-Airband, PulseAudio null sinks, SOX voice-activated recording, and optional rclone offload.

The checked-in examples target an Ontario Northland Railway monitoring setup, but new installs should customize the site with `/etc/train-recorder/site.yaml`.

For backward compatibility, installed paths, generated config directories, and systemd unit names still use the existing `train-recorder` identifiers.

The default example setup:

- RTLSDR-Airband receiving two NFM channels from one RTL-SDR dongle.
- 160.545 MHz streamed to Broadcastify/Icecast and sent to a PulseAudio sink.
- 161.265 MHz sent to a second PulseAudio sink.
- 161.265 MHz example config uses manual RTLSDR-Airband SNR squelch to reduce false opens on a quiet channel.
- SOX-based VOX recorder services that write one MP3 per transmission.
- Optional rclone sync/move of recordings to cloud storage.

## Repository Layout

```text
Config/
  common.env.example         Shared recorder environment defaults.
  freq160545.env.example     160.545 MHz recorder settings.
  freq161265.env.example     161.265 MHz recorder settings.
  rtl_airband.conf.example   Example RTLSDR-Airband config. Copy and add secrets locally.
  sync.env.example           Optional rclone sync settings.
  system.pa                  PulseAudio system-mode config with two null sinks.
  site.example.yaml          Example site definition for generated configs.
Scripts/
  install.sh                 Conservative Raspberry Pi installer.
  site_config.sh             Wizard/generator/apply tool for site-specific configs.
  health_check.sh            Dynamic service, PulseAudio, storage, sync, and channel checks.
  doctor.sh                  Read-only install and runtime sanity checker.
  status_json.py             Machine-readable status collector for automation and dashboards.
  status_history.py          Rolling dashboard status history recorder.
  recording_diagnostics.py   Read-only recent MP3 sample diagnostics for tuning.
  dashboard.py               Optional read-only Flask status dashboard.
  wifi_check.py              Optional Wi-Fi/network health check with conservative remedy mode.
  validate_deploy.sh         Read-only post-deploy validation checklist.
  collect_diagnostics.sh     Sanitized troubleshooting bundle collector.
  cleanup_empty_dirs.sh      Daily cleanup for empty local recording directories.
  vox_record.sh              Shared configurable VOX recorder.
  vox.sh                     Legacy 160.545 MHz recorder wrapper.
  vox2.sh                    Legacy 161.265 MHz recorder wrapper.
  sync.sh                    Optional rclone move script.
  status_summary.sh          Read-only operator status summary.
Service_Files/
  vox@.service               Templated VOX recorder unit, one instance per channel env file.
  train-recorder-dashboard.service Optional read-only web dashboard unit.
  train-recorder-status-history.* Optional dashboard history service and timer.
  train-recorder-wifi-check.* Optional Wi-Fi/network check service and timer.
  *.service                  systemd units for PulseAudio, RTLSDR-Airband, health, sync, and cleanup.
  *.timer                    Optional systemd timers for health checks, rclone sync, and cleanup.
docs/
  INSTALL.md                 Raspberry Pi setup notes.
  ARCHITECTURE.md            Signal flow and operational model.
  OPERATIONS.md              Log, retention, and long-running install notes.
  SECURITY.md                Raspberry Pi hardening checklist.
  WATCHDOG.md                Hardware watchdog planning notes.
  HARDWARE.md                Tested hardware notes and deployment checklist.
  RELEASE.md                 Release checklist.
  ROADMAP.md                 Follow-up ideas for continued development.
CHANGELOG.md                 Release history and unreleased changes.
AGENTS.md                    Context for future coding agents and maintainers.
```

## Quick Start

1. Install git, then clone this repo to the Raspberry Pi, usually `/opt/train-recorder`.

   ```bash
   sudo apt update
   sudo apt install -y git
   sudo git clone https://github.com/robinpascoe-tech/Train_Recorder.git /opt/train-recorder
   sudo chown -R pi:pi /opt/train-recorder
   ```

2. Run the conservative installer:

   ```bash
   cd /opt/train-recorder
   sudo Scripts/install.sh
   ```

   `site_config.sh` requires PyYAML. The installer ensures the Debian package
   `python3-yaml` is present so `/etc/train-recorder/site.yaml` is always parsed
   with a real YAML parser.

3. Configure rclone as the `pi` user if cloud offload is enabled.
4. Create or edit `/etc/train-recorder/site.yaml`:

   ```bash
   sudo /opt/train-recorder/Scripts/site_config.sh wizard
   ```

5. Preview and apply the generated site configuration:

   ```bash
   sudo /opt/train-recorder/Scripts/site_config.sh generate
   sudo /opt/train-recorder/Scripts/site_config.sh plan
   sudo /opt/train-recorder/Scripts/site_config.sh diff
   sudo /opt/train-recorder/Scripts/site_config.sh apply
   ```

6. Verify the recorder:

   ```bash
   sudo /opt/train-recorder/Scripts/site_config.sh doctor
   ```

   For a shorter operational view after validation, run `sudo /opt/train-recorder/Scripts/status_summary.sh`.

   If you enable the optional dashboard, install `python3-flask` or answer yes to the installer's dashboard dependency prompt. The dashboard listens on port `8080` by default.

   After a code deploy, run `sudo /opt/train-recorder/Scripts/validate_deploy.sh` for a repeatable read-only validation pass.

Reference docs:

- [docs/INSTALL.md](docs/INSTALL.md): full install checklist.
- [docs/OPERATIONS.md](docs/OPERATIONS.md): logs, dashboard, diagnostics, retention, and tuning.
- [docs/SECURITY.md](docs/SECURITY.md): Raspberry Pi hardening checklist.
- [docs/WATCHDOG.md](docs/WATCHDOG.md): hardware watchdog plan and rollback.
- [docs/HARDWARE.md](docs/HARDWARE.md): tested hardware and deployment details to collect.
- [docs/ROADMAP.md](docs/ROADMAP.md): completed work and follow-up ideas.
- [docs/RELEASE.md](docs/RELEASE.md): release checklist.

The sanitized recording directory example in [docs/OPERATIONS.md](docs/OPERATIONS.md#recording-retention) shows the dated folder tree and MP3 filename format.

## Secret Handling

Do not commit real Broadcastify/Icecast passwords, mountpoints, rclone credentials, SSH keys, or generated recordings. Keep live configs under `/etc/train-recorder`, `/usr/local/etc`, and `/home/pi/.config/rclone`; the repository should contain examples only.

## License

This repository's scripts, configuration templates, and documentation are licensed under the MIT License. Third-party tools such as RTLSDR-Airband, PulseAudio, SOX, rclone, and RTL-SDR libraries are not included in this repository and remain under their respective licenses.

## Site Configuration

For reusable installs, keep site-specific settings in `/etc/train-recorder/site.yaml`. Start from `Config/site.example.yaml` or run:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh wizard
sudo /opt/train-recorder/Scripts/site_config.sh generate
sudo /opt/train-recorder/Scripts/site_config.sh plan
sudo /opt/train-recorder/Scripts/site_config.sh diff
sudo /opt/train-recorder/Scripts/site_config.sh apply
sudo /opt/train-recorder/Scripts/site_config.sh doctor
```

`generate` writes a preview to `/tmp/train-recorder-generated` by default. `diff` compares generated files with live files and redacts Broadcastify secrets in RTLSDR-Airband diffs. `apply` runs preflight checks, backs up replaced files, reconciles `vox@...` services, removes stale generated channel env files, disables the sync timer when `rclone_remote` is removed, and enables PulseAudio/RTLSDR-Airband plus the configured train-recorder timers.

After applying a site config, run `sudo /opt/train-recorder/Scripts/site_config.sh doctor` for the read-only install and runtime validation check.

For automation or the optional dashboard, use `sudo /opt/train-recorder/Scripts/site_config.sh doctor --json`.

If you run `site_config.sh` before the installer, install PyYAML first:

```bash
sudo apt install python3-yaml
```

If `site.yaml` already exists, the wizard loads it and uses the current values as defaults. Sensitive Broadcastify values are preserved without printing them in the prompt.

## Development Notes

The VOX recorder is intentionally parameterized with environment variables so additional channels can be added without duplicating the recording loop. `vox@.service` starts one recorder instance per channel env file while `Scripts/vox_record.sh` holds the shared behavior. Each recorder service loads `common.env` first and its channel-specific env file second, so values such as `SOX_VOLUME` can be tuned per channel.

`Scripts/site_config.sh` is now a thin shell wrapper around the testable Python implementation in `Scripts/site_config.py`. Keep behavior changes in the Python module so unit tests can cover parsing, generation, plan output, and apply reconciliation.

The Python test suite now covers `site_config.py`, `status_json.py`, `wifi_check.py`, `recording_diagnostics.py`, `status_history.py`, and the dashboard API/render helpers. That coverage is intentionally helper-focused so operator-visible regressions are caught without needing a live Pi in CI.

Failure-oriented tests now cover `site_config.py apply` paths for missing runtime directories, partial file-copy failures, `systemctl` failures, stale non-file targets, and restore-note output after backups are created.

GitHub Actions runs shell syntax/ShellCheck, Python unit tests, and Ruff lint/format checks on pushes to `main` and pull requests. To run the same checks on a Linux host:

```bash
bash -n Scripts/*.sh
shellcheck --severity=error --external-sources --exclude=SC1090,SC1091 Scripts/*.sh
python3 -m pip install Flask PyYAML
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
ruff check Scripts tests
ruff format --check Scripts tests
```

`SC1090` and `SC1091` are excluded because several scripts intentionally source runtime env files from `/etc/train-recorder`.

Useful variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PULSE_MONITOR` | required | PulseAudio monitor source, such as `myfreq1sink.monitor`. |
| `OUTPUT_ROOT` | `/home/pi/Recordings` | Root folder for dated recording directories. |
| `TEMP_DIR` | `/mnt/ramdisk` | Temporary recording location. |
| `PULSE_SERVER` | `unix:/run/pulse/native` | PulseAudio server socket used by health checks. |
| `VOX_CHANNELS` | `freq160545,freq161265` | Comma-separated channel env names used by install/start helpers. |
| `SOX_VOLUME` | `4` | SOX input gain applied before silence detection and MP3 encoding; may be overridden in a channel env file. |
| `MIN_BYTES` | `700` | Discard files smaller than this threshold. |
| `START_DURATION` | `0.2` | SOX leading-silence trigger duration. |
| `STOP_DURATION` | `13.0` | SOX trailing-silence duration before closing a file. |
| `RECORDING_UMASK` | `0002` | Permissions mask for generated folders and MP3s. |
| `CHECK_RECENT_LOCAL_RECORDINGS` | `false` | Enables an optional warning when no recent MP3s remain under `OUTPUT_ROOT`; keep disabled when rclone moves files away quickly. |
| `CHECK_RECENT_SYNC_SUCCESS` | `true` | Fail health checks when `train-recorder-sync.service` has not finished recently. |
| `MAX_SYNC_SUCCESS_AGE_MINUTES` | `30` | Recent-success window for the rclone sync service. |
| `WIFI_CHECK_REMEDY` | `false` | Lets `train-recorder-wifi-check.timer` run `wifi_check.py` in remedy mode instead of check-only mode. |
| `WIFI_CHECK_ALLOW_REBOOT` | `false` | Allows `wifi_check.py --remedy` to request a reboot after repeated core network failures; keep disabled unless the site has been explicitly tested for this behavior. |
| `WIFI_CHECK_REBOOT_FAILURE_THRESHOLD` | `3` | Consecutive failed Wi-Fi/network checks required before remedy mode may request one reboot. |
| `RCLONE_MIN_AGE` | `15s` | Minimum file age before `sync.sh` allows rclone to move a completed MP3. |
| `CLIPPING_WINDOW_MINUTES` | `1440` | Journal lookback window used by status, doctor, and dashboard clipping summaries. |
| `CLIPPING_WARN_COUNT` | `50` | Warning threshold for SOX clipping messages within the clipping window; set `0` to disable the count threshold. |
| `CLIPPING_WARN_MAX_SAMPLES` | `1000000` | Warning threshold for the largest SOX clipping sample count; set `0` to disable the peak-samples threshold. |
| `JOURNAL_WINDOW_MINUTES` | `10080` | Journal lookback window used by `status_summary.sh` for last-event summaries. |
| `RECORDING_DIAGNOSTICS_LOOKBACK_HOURS` | `24` | MP3 lookback window used by `recording_diagnostics.py`. |
| `RECORDING_DIAGNOSTICS_JOURNAL_HOURS` | `24` | Journal lookback window used by `recording_diagnostics.py` for recent save events after rclone moves local files. |
| `RECORDING_DIAGNOSTICS_MAX_FILES` | `20` | Per-channel sample limit used by `recording_diagnostics.py`. |

Channel environment files also support:

| Variable | Purpose |
| --- | --- |
| `FREQUENCY_MHZ` | Human-readable channel frequency for reports. |
| `HEALTH_CHECK_RECENT_SAVE` | Enables or disables recent-save health warnings for that channel. |
| `MAX_SAVE_AGE_MINUTES` | Recent-save lookback window for that channel. |
| `JOURNAL_UNITS` | Optional space-separated journal units to search for that channel, useful during migrations. |

`site.yaml` channel entries also support these RTLSDR-Airband fields, which are generated into `rtl_airband.conf`:

| Field | Purpose |
| --- | --- |
| `squelch_snr_threshold` | Optional per-channel SNR squelch threshold. The `161.265` example uses `15` after additional soak tuning. |
| `squelch_threshold` | Optional per-channel absolute squelch threshold. More gain/site dependent than SNR squelch. |
| `bandwidth` | Optional per-channel bandwidth limit. |
| `ctcss` | Optional per-channel CTCSS tone when the channel tone is known. |

## Public Release Checklist

- Rotate any credential that was ever committed to a local or private copy.
- Verify git history contains no real credentials before pushing publicly.
- Complete [docs/RELEASE.md](docs/RELEASE.md) before tagging a release.
- Fill in hardware notes for the exact Raspberry Pi, RTL-SDR dongle, antenna, and power setup.
- Add screenshots or sample sanitized logs if useful for troubleshooting.

## Disclaimer

This project is an independent, non-commercial hobbyist development. All product names, logos, and brands, including Raspberry Pi and Ontario Northland Railway, are property of their respective owners. Their use here does not imply affiliation, endorsement, or sponsorship.
