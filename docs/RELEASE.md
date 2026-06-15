# Release Checklist

Use this checklist before tagging a public release.

## v1.0.0 Readiness

- Confirm both known recorder installs are healthy:
  - Production Pi: SOX/PulseAudio architecture soak tested.
  - Fresh Raspberry Pi OS Trixie Pi: install, recording, and rclone sync validated.
- Run local checks:

```bash
bash -n Scripts/*.sh
shellcheck --external-sources --exclude=SC1090,SC1091 Scripts/*.sh
```

- Confirm GitHub Actions shell lint passes on `main`.
- Run a final secret scan and manual review:
  - no real Broadcastify/Icecast passwords
  - no real mountpoints if considered private
  - no rclone tokens
  - no SSH keys or passwords
  - no generated recordings
- Confirm public docs are current:
  - [INSTALL.md](INSTALL.md)
  - [OPERATIONS.md](OPERATIONS.md)
  - [ARCHITECTURE.md](ARCHITECTURE.md)
  - [HARDWARE.md](HARDWARE.md)
  - [ROADMAP.md](ROADMAP.md)
- Confirm examples are sanitized:
  - `Config/*.example`
  - `Config/site.example.yaml`
  - sanitized recording tree in [OPERATIONS.md](OPERATIONS.md#recording-retention)
- Confirm runtime expectations are documented:
  - system-mode PulseAudio only
  - `vox@...` templated services
  - rclone runs as `pi`
  - `/mnt/ramdisk` temp recordings
  - optional `/var/log` tmpfs and PCP disablement
- Update [CHANGELOG.md](../CHANGELOG.md):
  - move `Unreleased` entries to `v1.0.0`
  - add the release date
- Create and push the tag:

```bash
git tag -a v1.0.0 -m "Train Recorder v1.0.0"
git push origin v1.0.0
```

## Post-Release

- Create a GitHub release from the tag.
- Include the tested hardware/OS summary.
- Include any known limitations, especially that RTLSDR-Airband native MP3 recording was tested but not used in production.
- Start a new `Unreleased` section in [CHANGELOG.md](../CHANGELOG.md) for future changes.

## v1.1.0 Readiness

- Confirm current `main` is deployed on both known recorder installs:
  - Production Pi: `site_config.sh doctor` reports no failures and diagnostics bundle includes `commands/doctor`.
  - Fresh Raspberry Pi OS Trixie Pi: `site_config.sh doctor` reports no failures and diagnostics bundle includes `commands/doctor`.
- Run local checks:

```bash
bash -n Scripts/*.sh
shellcheck --external-sources --exclude=SC1090,SC1091 Scripts/*.sh
git status --short --branch
```

- Run a final secret and history scan.
- Move `Unreleased` entries to `v1.1.0` in [CHANGELOG.md](../CHANGELOG.md).
- Tag and publish the release.
