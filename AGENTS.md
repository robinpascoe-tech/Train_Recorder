# Agent Handoff Notes

## Project Purpose

This repository maintains a Raspberry Pi railway radio recorder for two conventional NFM channels using one RTL-SDR dongle.

The production goals are:

- receive 160.545 MHz and 161.265 MHz
- stream 160.545 MHz to Broadcastify through RTLSDR-Airband
- write one MP3 per detected transmission for both channels
- preserve the historical recording path and filename format
- move completed recordings to OneDrive with rclone

## Current Production Architecture

Use this architecture unless the user explicitly asks to revisit it:

```text
RTL-SDR -> RTLSDR-Airband -> PulseAudio null sinks
                         -> Broadcastify/Icecast stream

PulseAudio monitor sources -> SOX VOX recorder scripts
                           -> /mnt/ramdisk temp files
                           -> /home/pi/Recordings/YYYY/MM-Mon/DD-Day/*.mp3
                           -> rclone move to OneDrive
```

`vox@freq160545.service`, `vox@freq161265.service`, and `train-recorder-sync.service` run as `pi:pi`. This is intentional. The `pi` user can access the PulseAudio system-mode monitor sources, owns generated MP3s, and has the rclone OneDrive auth under `/home/pi/.config/rclone`.

## Important Paths

```text
/opt/train-recorder                  deployed app files
/etc/train-recorder/site.yaml        desired site config with possible secrets
/etc/train-recorder/common.env       shared recorder settings
/etc/train-recorder/freq160545.env   first recorder channel settings
/etc/train-recorder/freq161265.env   second recorder channel settings
/etc/train-recorder/sync.env         rclone sync settings
/usr/local/etc/rtl_airband.conf      live RTLSDR-Airband config with secrets
/etc/pulse/system.pa                 live PulseAudio system-mode config
/home/pi/Recordings                  local recording spool
/mnt/ramdisk                         temporary SOX output files
/home/pi/.config/rclone              pi user's OneDrive/rclone auth
```

## Pi Access

The Windows SSH config may have an `onr-recorder` host alias for the production Pi. Prefer it when it resolves:

```bash
ssh onr-recorder
scp file onr-recorder:/tmp/
```

Do not commit SSH keys, passwords, Broadcastify credentials, or rclone tokens.

## Git Branches

`main` contains the production SOX/PulseAudio architecture.

`feature/native-rtl-airband-recording` is an experiment branch. It documents tests of RTLSDR-Airband native MP3 recording with 5.1.1 and 5.2.0. Those tests did not produce reliable file output on the target Pi, so do not merge that branch into production without a new successful test.

## Operational Notes

- `Scripts/install.sh` is intentionally conservative. It can install packages and seed missing configs, but it must not overwrite live env files, `/usr/local/etc/rtl_airband.conf`, `/etc/pulse/system.pa`, or rclone credentials without prompting. Its optional RTLSDR-Airband source build defaults to `RTL_AIRBAND_REF=v5.2.0`. On fresh installs it prepares packages/files/units/access groups but skips service start prompts until `/etc/train-recorder/site.yaml` exists.
- Fresh Trixie installs need `git` before cloning, `libsox-fmt-pulse` for SOX PulseAudio input, and PulseAudio system-mode group access for both `pi` and root. The installer adds `pi` to `pulse,pulse-access,audio` and root to `pulse,pulse-access`; doctor treats `pulse-access` as required and missing `pulse` membership as a warning. Desktop-capable images may enable per-user `pi` PulseAudio units; recorder appliances should mask `~pi/.config/systemd/user/pulseaudio.service` and `pulseaudio.socket` so only system-mode `pulseaudio.service` runs.
- `Scripts/site_config.sh` is the desired-state configuration tool. `/etc/train-recorder/site.yaml` is source-of-truth and may contain Broadcastify secrets; generated env files, `system.pa`, and `rtl_airband.conf` are artifacts. Use `generate`, `plan`, and `diff` before `apply`, then `doctor` after apply. The wizard loads an existing `site.yaml` as prompt defaults and masks sensitive Broadcastify values in prompts. `apply` is the activation step for generated installs and enables/restarts the configured recorder services and train-recorder timers.
- `Scripts/doctor.sh` is the read-only validation command. Prefer `sudo /opt/train-recorder/Scripts/site_config.sh doctor`; diagnostics bundles include the same doctor output under `commands/doctor`.
- `Scripts/status_json.py` powers `sudo /opt/train-recorder/Scripts/site_config.sh doctor --json` and the optional Flask dashboard. Keep dashboard/status automation read-only unless the user explicitly asks for control actions.
- `Scripts/dashboard.py` is an optional LAN-oriented Flask dashboard served by `train-recorder-dashboard.service` on port `8080` by default. Do not expose it directly to the internet without a separate authentication and TLS layer.
- `Scripts/wifi_check.py` writes `/var/lib/train-recorder/wifi-check.json` for the dashboard and diagnostics bundle. `train-recorder-wifi-check.timer` runs check-only mode by default; `--remedy` is manual/explicit and should stay conservative.
- New recorder services should use the templated `vox@.service` naming convention. Legacy `vox.service` and `vox2.service` existed for the original two-channel install, but new/generated configs should enable `vox@<channel-env-name>.service`.
- The old cron entry for `/home/pi/sync.sh` was replaced by `train-recorder-sync.timer`.
- Empty local date directories are cleaned deepest-first by `train-recorder-cleanup.timer`, not by adding `--delete-empty-src-dirs` to every rclone run. The cleanup script logs a summary count instead of every deleted path.
- The old recursive `chmod 777 /home/pi/Recordings` workaround was retired.
- `/home/pi/Recordings` should be `pi:pi` and `775`.
- Generated MP3s should be `pi:pi` and group writable.
- The health check local-recency warning is disabled by default because rclone moves files away quickly. Re-enable it only when troubleshooting a setup that keeps local MP3s.
- The health check and status summary read `VOX_CHANNELS` and source each channel env file. Per-channel recent-save behavior belongs in `HEALTH_CHECK_RECENT_SAVE` and `MAX_SAVE_AGE_MINUTES`, not hardcoded script logic.
- Use `sudo /opt/train-recorder/Scripts/site_config.sh doctor` for install/runtime validation and `sudo /opt/train-recorder/Scripts/status_summary.sh` for a quick read-only operator summary before pulling detailed logs.
- SOX clipping warnings have been observed. Shared `SOX_VOLUME` is `4`; production `freq160545.env` has been lowered to `SOX_VOLUME=2` after soak testing, while `freq161265` currently uses the shared default.
- Clipping counts are expected to be visible in status/dashboard output; warning state is controlled by `CLIPPING_WARN_COUNT` and `CLIPPING_WARN_MAX_SAMPLES` in the shared env.
- Channel env files load after `common.env`, so `SOX_VOLUME` can be tuned per channel. For RTLSDR-Airband-side false-open tuning, keep per-channel fields such as `squelch_snr_threshold` in `/etc/train-recorder/site.yaml`; current production desired state uses `squelch_snr_threshold: 14` for `freq161265`.
- v1.3.0 is released and deployed to the Trixie Pi. It includes dashboard history, recording diagnostics, hardware watchdog docs/phase 1, and per-channel RTLSDR-Airband squelch generation.

## Safe Deployment Pattern

Before changing the live Pi:

1. Check `git status`.
2. Copy files to `/tmp` first when testing.
3. Back up live files or units before replacing them.
4. Restart only the affected services.
5. Verify with:

```bash
systemctl is-active rtl_airband.service vox@freq160545.service vox@freq161265.service
systemctl list-timers --all | grep train-recorder
sudo /opt/train-recorder/Scripts/site_config.sh doctor
journalctl -u vox@freq160545.service -u vox@freq161265.service -u train-recorder-sync.service --since today
```

Keep changes small and soak-test after service or permission changes.
