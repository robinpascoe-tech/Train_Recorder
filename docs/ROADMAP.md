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
- `site_config.sh` refactored into a testable Python module with unit coverage for parsing, planning, apply reconciliation, and status helpers.
- `site_config.sh apply` now cleans up stale generated channel env files and disables sync cleanly when `rclone_remote` is removed.
- Failure-oriented `site_config.sh apply` tests for missing runtime paths, partial file update failures, `systemctl` failures, stale non-file targets, and restore-note output.
- Python CI coverage for unit tests plus Ruff lint and format checks alongside ShellCheck.
- PyYAML-only `site_config.sh` parsing, with `install.sh` ensuring `python3-yaml` is installed.
- Conservative `pulseaudio.service` and `rtl_airband.service` restart policies with systemd rate limiting.
- Real-Pi smoke testing for forced PulseAudio and RTLSDR-Airband crashes, including successful recovery and clean deploy validation afterward.
- `validate_deploy.sh` now warns when the systemd host hardware watchdog is disabled.
- Wi-Fi/network remedy mode now supports opt-in reboot after repeated core connectivity failures, with a success-cleared latch to avoid reboot loops during persistent outages.

Release readiness:

- v1.0.0 tagged and released.
- v1.1.0 tagged and released.
- v1.2.0 release notes prepared after an 18-hour clean dashboard soak on the fresh Trixie Pi.
- v1.3.0 tagged and released with dashboard history, recording diagnostics, watchdog/security docs, and per-channel RTLSDR-Airband squelch generation.
- v1.4.0 tagged and released with Python site_config refactor, broader test coverage, PyYAML-only site parsing, Ruff CI, apply hardening, and conservative core-service restart policies.
- Continue using [RELEASE.md](RELEASE.md) before future tags.

Future ideas:

- Continue soaking the Raspberry Pi hardware watchdog configuration before adding any service-level `WatchdogSec=` notification policy.
- During a maintenance window, deliberately exhaust the `pulseaudio.service` and `rtl_airband.service` start-limit bursts on test or physically accessible hardware to confirm repeated failures stop retrying as intended.
- Continue monitoring SOX clipping warnings after longer soaks and adjust per-channel gain if needed.
- Add optional runtime-only cleanup guidance for removing build dependencies after RTLSDR-Airband is built.
- Add more hardware examples from other locations and antenna/SDR combinations.
- Update GitHub Actions versions or workflow configuration to remove the non-blocking Node 20 deprecation warning from `actions/checkout@v4` and `actions/setup-python@v5`.
