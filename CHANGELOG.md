# Changelog

All notable changes to this project will be documented in this file.

This project follows a practical release process. Changes before the first public release are collected under `v1.0.0`.

## Unreleased

### Changed

- Documentation updated after the v1.4.0 release to align release notes, roadmap, install dependencies, architecture notes, hardware notes, and agent handoff context with the current product state.

## v1.4.0 - 2026-06-18

### Added

- Unit-test harness for `site_config.py` and `status_json.py`, plus CI coverage for the Python test suite.
- Unit coverage for `wifi_check.py`, `recording_diagnostics.py`, `status_history.py`, and dashboard API/render helpers.

### Changed

- SOX clipping checks now use configurable count and peak-sample thresholds so expected clipping remains visible without creating constant warnings.
- Dashboard now shows recent recording save counts from the recorder journal and keeps clipping trend display separate from threshold-warning state.
- Wi-Fi/network check state now preserves the most recent failure summary after recovery for dashboard and diagnostics visibility.
- `site_config.sh` is now a thin wrapper around the testable `site_config.py` implementation.
- `site_config.sh apply` now removes stale generated channel env files and disables sync cleanly when `rclone_remote` is removed.
- `site_config.sh apply` now prints restore guidance for file-update failures as well as `systemctl` failures after backups have been created.
- `site_config.sh` now requires PyYAML instead of falling back to a handwritten YAML subset parser, and `install.sh` ensures `python3-yaml` is installed.
- `pulseaudio.service` now retries once on failure with rate limiting, and `rtl_airband.service` now retries conservatively with rate limiting plus `PartOf=pulseaudio.service` so explicit PulseAudio restarts also recycle the SDR demodulator.
- Documentation freshness and optimization pass across README, install, operations, release, roadmap, watchdog, hardware, and agent handoff notes.

### Validated

- Python unit tests now pass locally across `site_config.py`, `status_json.py`, `wifi_check.py`, `recording_diagnostics.py`, `status_history.py`, and dashboard helpers.
- GitHub Actions now runs Python tests plus Ruff lint/format checks alongside the existing shell checks.
- The Trixie Pi recorder passed `validate_deploy.sh` after deploying the new PulseAudio and RTLSDR-Airband restart policies.
- Real-Pi restart smoke testing confirmed that `pulseaudio.service` recovered from a forced crash after one delayed restart, and `rtl_airband.service` recovered from both a PulseAudio recycle and a direct forced crash using the configured restart delay.

## v1.3.0 - 2026-06-17

### Added

- Raspberry Pi security hardening checklist for SSH, passwords, LAN-only dashboard exposure, updates, and secret handling.
- Hardware watchdog planning notes for conservative host-level recovery and future service restart policy review.
- Dashboard and status JSON now report system uptime.
- Dashboard history recorder, timer, API endpoint, and history panel for 24-hour operational trends.
- Read-only recording sample diagnostics for MP3 duration, size, RMS amplitude, and peak amplitude during recorder tuning.
- Clearer dashboard history cards with last sample age and non-zero trend indicators.
- Per-channel RTLSDR-Airband squelch options in generated config, including the soaked `161.265` SNR squelch setting.
- Recording diagnostics now includes recent journal save counts and byte totals after rclone moves local MP3 files.
- Dashboard history now separates operational warning samples from clipping trend samples.

## v1.2.0 - 2026-06-16

### Added

- Machine-readable status JSON via `site_config.sh doctor --json`.
- Optional read-only Flask web dashboard and systemd unit.
- Optional Wi-Fi/network health check with JSON state, check-only timer, and manual conservative remedy mode.
- Read-only post-deploy validator for git state, services, timers, doctor, dashboard, Wi-Fi/network, operator summary, and recent warning logs.

### Changed

- Refreshed documentation to align README, architecture, operations, release, roadmap, and agent handoff notes with the current project state.
- Diagnostics bundles now include the status JSON payload.
- Installer now ensures `python3-flask` is present before enabling the optional dashboard, and fresh-install docs call out the dashboard dependency.
- Dashboard now surfaces failures, warnings, event recency, network state, and pending recordings more clearly.

### Validated

- Fresh Raspberry Pi OS Trixie Pi ran the dashboard and Wi-Fi/network check for an 18-hour soak with clean doctor output.

## v1.1.0 - 2026-06-15

### Added

- Diagnostics bundle collector for sanitized troubleshooting snapshots.
- Read-only doctor command for common install and runtime checks.
- `site_config.sh doctor` alias for the standalone doctor command.
- Doctor output in diagnostics bundles, plus installer and documentation validation flow updates.
- Doctor treats missing `pulse` group membership as a warning while keeping `pulse-access` as the required system-mode PulseAudio access check.

## v1.0.0 - 2026-06-14

### Added

- Conservative Raspberry Pi installer for packages, project files, systemd units, PulseAudio access groups, optional tmpfs mounts, and optional RTLSDR-Airband source builds.
- Generated site configuration workflow with `site_config.sh wizard`, `generate`, `plan`, `diff`, and `apply`.
- Dynamic `vox@...` recorder services driven by channel env files instead of duplicated per-channel recorder scripts.
- Shared `vox_record.sh` SOX VOX recorder with per-channel settings such as `SOX_VOLUME`, `START_DURATION`, and `MIN_BYTES`.
- Dynamic health checks and operator status summaries based on configured `VOX_CHANNELS`.
- rclone move service and 5-minute timer for fast offload to OneDrive or another rclone remote.
- Daily cleanup timer for empty local recording directories.
- Log, journal retention, `/var/log` tmpfs, and PCP guidance for long-running Raspberry Pi installs.
- Headless OneDrive/rclone setup documentation for Windows and Linux desktop authorization flows.
- Sanitized recording directory tree and filename format documentation.
- MIT license and license badge.
- Shell lint workflow for GitHub Actions.

### Changed

- Production architecture standardized on RTLSDR-Airband to PulseAudio null sinks plus SOX VOX recording.
- `site_config.sh apply` is now the activation step for generated installs: it enables/restarts PulseAudio, RTLSDR-Airband, configured `vox@...` services, and train-recorder timers.
- Fresh installs now skip service start prompts until `/etc/train-recorder/site.yaml` exists.
- SOX install now includes `libsox-fmt-pulse` so SOX can read PulseAudio monitor sources.
- Installer configures PulseAudio access for `pi` and root and offers to disable per-user PulseAudio so the recorder uses only system-mode PulseAudio.
- Channel 1 volume tuning moved toward lower gain to reduce clipping while keeping intelligibility acceptable.
- raspiBackup guidance now recommends not stopping recorder services and excluding volatile recorder paths instead.

### Fixed

- Root-owned recording and rclone delete failures caused by legacy root-run `vox.service` and `vox2.service`.
- Legacy VOX services being restarted by raspiBackup by masking old services and removing recorder services from raspiBackup stop/start hooks.
- `/var/log` tmpfs filling because of PCP performance archives on small RAM-backed log mounts.
- Health and status reporting for fast-moving rclone workflows where local MP3s are normally gone quickly.
- Fresh Raspberry Pi OS Trixie install gaps found during second-Pi validation.

### Validated

- Existing production Pi soak tested with templated `vox@...` services, SOX/PulseAudio recording, rclone sync, cleanup, and health timers.
- Fresh Raspberry Pi OS Trixie minimal install on Raspberry Pi 3 validated through install, recording, and rclone sync.
- Shell syntax and ShellCheck pass locally through WSL and in GitHub Actions.
