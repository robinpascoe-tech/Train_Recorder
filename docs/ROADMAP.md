# Roadmap

Completed:

- Initial SOX volume tuning to reduce clipping while preserving intelligibility. Per-channel `SOX_VOLUME` overrides are supported, and the current production config lowers `freq160545` one notch below the shared default.
- Dynamic health and status reports based on configured `VOX_CHANNELS`.
- Templated `vox@...` recorder services for channel-specific recorder instances.
- Conservative Raspberry Pi installer with optional prerequisite installation and RTLSDR-Airband source build.
- Generated site configuration workflow with `site_config.sh wizard`, `generate`, `plan`, and `apply`.
- Wizard defaults sourced from existing `/etc/train-recorder/site.yaml`, with sensitive Broadcastify values masked in prompts.
- Daily empty-directory cleanup service with summarized journal output.
- Documentation refresh for the current generated-config workflow.
- Log and retention policy notes for long-running installs.

Near-term ideas for continued development:

- Soak-test and harden `site_config.sh apply` with real frequency add/remove changes.
- Continue monitoring SOX clipping warnings after longer soaks and adjust per-channel gain if needed.
- Add hardware documentation for antenna, RTL-SDR model, Raspberry Pi model, cooling, and power.
- Add a sanitized sample recording directory tree for documentation.
- Add automated shell linting once the project has a Linux CI runner.
- Add a dry-run or diff mode for `site_config.sh apply` output so generated file changes are easier to review before restarting services.
- Add validation for Broadcastify/Icecast settings before applying a generated `rtl_airband.conf`.
