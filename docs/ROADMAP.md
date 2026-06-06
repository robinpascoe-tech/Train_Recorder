# Roadmap

Near-term ideas for continued development:

- Soak-test and harden `site_config.sh apply` with real frequency add/remove changes.
- Tune SOX volume to reduce clipping warnings while preserving intelligibility.
- Add log rotation and retention policy notes for long-running installs.
- Add hardware documentation for antenna, RTL-SDR model, Raspberry Pi model, cooling, and power.
- Add a sanitized sample recording directory tree for documentation.
- Add automated shell linting once the project has a Linux CI runner.
- Add a dry-run or diff mode for `site_config.sh apply` output so generated file changes are easier to review before restarting services.
- Add validation for Broadcastify/Icecast settings before applying a generated `rtl_airband.conf`.
