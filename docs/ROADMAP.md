# Roadmap

Completed:

- Initial SOX volume tuning to reduce clipping while preserving intelligibility. Per-channel `SOX_VOLUME` overrides are supported, and the current production config lowers `freq160545` one notch below the shared default.
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

Release readiness:

- v1.0.0 tagged and released.
- v1.1.0 tagged and released.
- Continue using [RELEASE.md](RELEASE.md) before future tags.

Future ideas:

- Polish the optional web dashboard after real operator use, including any additional fields, layout tweaks, or deployment hardening that prove useful.
- Integrate the Raspberry Pi hardware watchdog for unattended recovery. Document enabling the kernel watchdog, add conservative systemd watchdog settings where appropriate, and make sure the recorder services fail clearly enough for the host watchdog strategy to be useful.
- Add a Wi-Fi connectivity check/remedy script. It should detect loss of network or rclone destination reachability, log what it found, attempt safe recovery steps such as reconnecting the wireless interface or restarting the network service, and avoid reboot loops unless explicitly configured.
- Consider exposing the dashboard only on the LAN by default, with clear notes that it should not be internet-facing without authentication and TLS handled outside the project.

- Soak-test and harden `site_config.sh apply` with real frequency add/remove changes.
- Continue monitoring SOX clipping warnings after longer soaks and adjust per-channel gain if needed.
- Add optional runtime-only cleanup guidance for removing build dependencies after RTLSDR-Airband is built.
- Add more hardware examples from other locations and antenna/SDR combinations.
