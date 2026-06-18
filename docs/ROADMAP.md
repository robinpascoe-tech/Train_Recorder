# Roadmap

Completed:

- Initial SOX volume tuning to reduce clipping while preserving intelligibility. Per-channel `SOX_VOLUME` overrides are supported, and the current production config lowers `freq160545` one notch below the shared default.
- Recording sample diagnostics for recent MP3 count, duration, size, RMS amplitude, and peak amplitude.
- Per-channel RTLSDR-Airband squelch options in generated config, with `161.265` using `squelch_snr_threshold: 14` after soak testing.
- Dashboard history separates operational warnings from clipping trend warnings.
- Production SOX/PulseAudio architecture soak tested on the original recorder Pi with templated `vox@...` services, rclone sync, health checks, cleanup, and raspiBackup adjustments.
- Fresh Raspberry Pi OS Trixie minimal install validated on a Raspberry Pi 3, including package install, site configuration, recording, and rclone sync.
- Dynamic health and status reports based on configured `VOX_CHANNELS`.
- Templated `vox@...` recorder services for channel-specific recorder instances.
- Conservative Raspberry Pi installer with optional prerequisite installation and RTLSDR-Airband source build.
- Generated site configuration workflow with `site_config.sh wizard`, `generate`, `plan`, `diff`, `apply`, and `doctor`.
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
- v1.1 doctor command, `site_config.sh doctor` alias, diagnostics bundle doctor output, installer validation flow, and release validation on both known Pi installs.
- Dashboard foundation with `site_config.sh doctor --json`, reusable status JSON collection, optional read-only Flask dashboard, dashboard systemd unit, and diagnostics bundle status JSON.
- Wi-Fi/network check first pass with JSON state, check-only timer, manual conservative remedy mode, dashboard/status integration, and diagnostics bundle capture.
- Dashboard operator-summary polish after real use, with clearer failure, warning, recency, network, and pending-recording display.
- Read-only post-deploy validator for repeatable commit, service, timer, doctor, dashboard, Wi-Fi/network, summary, and warning-log checks.
- Hardware watchdog planning notes for conservative host-level recovery, service policy review, soak testing, and rollback.
- Dashboard history first pass with rolling JSON snapshots and 24-hour trend summaries.

Release readiness:

- v1.0.0 tagged and released.
- v1.1.0 tagged and released.
- v1.2.0 release notes prepared after an 18-hour clean dashboard soak on the fresh Trixie Pi.
- v1.3.0 tagged and released with dashboard history, recording diagnostics, watchdog/security docs, and per-channel RTLSDR-Airband squelch generation.
- Continue using [RELEASE.md](RELEASE.md) before future tags.

Future ideas:

- Continue soaking the Raspberry Pi hardware watchdog configuration before adding service-level watchdog settings.
- Expand Wi-Fi/network remediation only after observing the first-pass timer in production. Avoid reboot loops unless explicitly configured and tested.
- Soak-test and harden `site_config.sh apply` with real frequency add/remove changes.
- Continue monitoring SOX clipping warnings after longer soaks and adjust per-channel gain if needed.
- Add optional runtime-only cleanup guidance for removing build dependencies after RTLSDR-Airband is built.
- Add more hardware examples from other locations and antenna/SDR combinations.
