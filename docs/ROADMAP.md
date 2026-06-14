# Roadmap

Completed:

- Initial SOX volume tuning to reduce clipping while preserving intelligibility. Per-channel `SOX_VOLUME` overrides are supported, and the current production config lowers `freq160545` one notch below the shared default.
- Production SOX/PulseAudio architecture soak tested on the original recorder Pi with templated `vox@...` services, rclone sync, health checks, cleanup, and raspiBackup adjustments.
- Fresh Raspberry Pi OS Trixie minimal install validated on a Raspberry Pi 3, including package install, site configuration, recording, and rclone sync.
- Dynamic health and status reports based on configured `VOX_CHANNELS`.
- Templated `vox@...` recorder services for channel-specific recorder instances.
- Conservative Raspberry Pi installer with optional prerequisite installation and RTLSDR-Airband source build.
- Generated site configuration workflow with `site_config.sh wizard`, `generate`, `plan`, and `apply`.
- Wizard defaults sourced from existing `/etc/train-recorder/site.yaml`, with sensitive Broadcastify values masked in prompts.
- Daily empty-directory cleanup service with summarized journal output.
- Documentation refresh for the current generated-config workflow.
- Log and retention policy notes for long-running installs.
- Sanitized sample recording directory tree and filename format documentation.
- Automated shell linting with GitHub Actions and ShellCheck.
- `site_config.sh apply` preflight checks, redacted generated-file diffs, and clearer restore notes.
- Broadcastify/Icecast placeholder validation before applying generated RTLSDR-Airband config.
- PulseAudio system-mode access and per-user PulseAudio disablement documented and handled by the installer.
- `/var/log` tmpfs and PCP disablement guidance for SD-card-friendly long-running installs.

v1 release readiness:

- Fill in site-specific hardware details in [HARDWARE.md](HARDWARE.md).
- Run the final release checklist in [RELEASE.md](RELEASE.md).
- Run one final secret/history scan before tagging `v1.0.0`.
- Move `CHANGELOG.md` `Unreleased` notes to `v1.0.0` with a release date.

Future ideas after v1:

- Soak-test and harden `site_config.sh apply` with real frequency add/remove changes.
- Continue monitoring SOX clipping warnings after longer soaks and adjust per-channel gain if needed.
- Add optional runtime-only cleanup guidance for removing build dependencies after RTLSDR-Airband is built.
- Add more hardware examples from other locations and antenna/SDR combinations.
