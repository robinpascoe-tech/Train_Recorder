# Changelog

All notable changes to this project will be documented in this file.

This project follows a practical release process rather than strict semantic versioning history before v1. The first public release is planned as `v1.0.0` after the final release checklist is complete.

## Unreleased

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

