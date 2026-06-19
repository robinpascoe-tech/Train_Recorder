# Release Checklist

Use this checklist before tagging a public release.

## Standard Release Flow

1. Confirm the working tree is clean and current:

   ```bash
   git status --short --branch
   git log --oneline --decorate -n 5
   ```

2. Run local checks:

   ```bash
   bash -n Scripts/*.sh
   shellcheck --external-sources --exclude=SC1090,SC1091 Scripts/*.sh
   python3 -m unittest discover -s tests -p 'test_*.py' -v
   ruff check Scripts tests
   ruff format --check Scripts tests
   ```

3. Confirm GitHub Actions passes on `main`, including ShellCheck, Python Tests, and Python Lint and Format jobs.

4. Confirm public docs are current:

   - [INSTALL.md](INSTALL.md)
   - [OPERATIONS.md](OPERATIONS.md)
   - [ARCHITECTURE.md](ARCHITECTURE.md)
   - [SECURITY.md](SECURITY.md)
   - [WATCHDOG.md](WATCHDOG.md)
   - [HARDWARE.md](HARDWARE.md)
   - [ROADMAP.md](ROADMAP.md)

5. Confirm examples and generated references are sanitized:

   - `Config/*.example`
   - `Config/site.example.yaml`
   - sanitized recording tree in [OPERATIONS.md](OPERATIONS.md#recording-retention)

6. Run a final secret scan and manual review:

   - no real Broadcastify/Icecast passwords
   - no real mountpoints if considered private
   - no rclone tokens
   - no SSH keys or passwords
   - no generated recordings
   - no live `site.yaml`, `rtl_airband.conf`, or `rclone.conf`

7. Validate known recorder installs when practical:

   ```bash
   sudo /opt/train-recorder/Scripts/site_config.sh doctor
   sudo /opt/train-recorder/Scripts/validate_deploy.sh
   sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
   ```

   Doctor should report zero failures, and deploy validation should report zero required failures. Warnings may still be acceptable when they are understood and documented, such as optional `pulse` group membership warnings on a working system-mode PulseAudio install.

8. Update [CHANGELOG.md](../CHANGELOG.md):

   - move `Unreleased` entries to the new version
   - add the release date
   - leave an empty `Unreleased` section for future work

9. Create and push the tag:

   ```bash
   git tag -a vX.Y.Z -m "RailWave Pi vX.Y.Z"
   git push origin vX.Y.Z
   ```

   If local filesystem permissions block annotated tag creation, fix the local `.git` permissions first. A lightweight tag is acceptable only when the release notes and GitHub release clearly identify the release commit.

10. Create the GitHub release from the tag. Include the tested hardware/OS summary, important validation notes, and any known limitations.

## Current Known Installs

- Original production Pi: upgraded production SOX/PulseAudio architecture, templated `vox@...` services, rclone sync, cleanup, and health timers.
- Fresh Raspberry Pi OS Trixie Pi: validated from a minimal install through package setup, site configuration, recording, rclone sync, doctor, diagnostics bundle collection, dashboard, Wi-Fi/network check timer, status history, and recording diagnostics.
- The current Trixie Pi deployment uses `freq161265` desired and live RTLSDR-Airband config both at `squelch_snr_threshold = 15`, with PyYAML-backed site configuration, Python/Ruff CI checks, RuntimeWatchdogSec enabled, deploy-validation watchdog checks, and opt-in Wi-Fi remedy reboot gating available but still disabled by default.

## Historical Release Notes

- v1.0.0 established the production SOX/PulseAudio architecture, generated site configuration workflow, conservative installer, templated recorder services, rclone sync, cleanup, documentation, MIT license, and shell lint workflow.
- v1.1.0 added the doctor command, `site_config.sh doctor`, doctor output in diagnostics bundles, installer validation flow, and production-tested doctor behavior for PulseAudio group warnings.
- v1.2.0 added machine-readable status JSON, the optional read-only Flask dashboard, the optional Wi-Fi/network health check, dashboard dependency handling, dashboard operator-summary polish, and the read-only deploy validator.
- v1.3.0 added dashboard uptime/history, recording diagnostics, hardware watchdog documentation and phase 1 deployment notes, security hardening docs, per-channel RTLSDR-Airband squelch generation, and the soaked `161.265` SNR squelch setting.
- v1.4.0 added the testable Python `site_config.py` implementation, broader Python unit coverage, Ruff lint/format CI, PyYAML-only site parsing, `site_config.sh apply` hardening, and conservative PulseAudio/RTLSDR-Airband restart rate limiting validated on the Trixie Pi.
- RTLSDR-Airband native MP3 recording was tested with versions 5.1.1 and 5.2.0 but is not the production recording path because it did not produce reliable file output on the target Pi.
