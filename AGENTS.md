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
/opt/train-recorder                  deployed repo-backed app files
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

The Windows SSH config has an `onr-recorder` host alias for the current Pi. Prefer:

```bash
ssh onr-recorder
scp file onr-recorder:/tmp/
```

Do not commit SSH keys, passwords, Broadcastify credentials, or rclone tokens.

## Git Branches

`main` contains the production SOX/PulseAudio architecture.

`feature/native-rtl-airband-recording` is an experiment branch. It documents tests of RTLSDR-Airband native MP3 recording with 5.1.1 and 5.2.0. Those tests did not produce reliable file output on the target Pi, so do not merge that branch into production without a new successful test.

## Operational Notes

- `Scripts/install.sh` is intentionally conservative. It can install packages and seed missing configs, but it must not overwrite live env files, `/usr/local/etc/rtl_airband.conf`, `/etc/pulse/system.pa`, or rclone credentials without prompting. Its optional RTLSDR-Airband source build defaults to `RTL_AIRBAND_REF=v5.2.0`.
- New recorder services should use the templated `vox@.service` naming convention. Legacy `vox.service` and `vox2.service` existed for the original two-channel install, but new/generated configs should enable `vox@<channel-env-name>.service`.
- The old cron entry for `/home/pi/sync.sh` was replaced by `train-recorder-sync.timer`.
- Empty local date directories are cleaned deepest-first by `train-recorder-cleanup.timer`, not by adding `--delete-empty-src-dirs` to every rclone run. The cleanup script logs a summary count instead of every deleted path.
- The old recursive `chmod 777 /home/pi/Recordings` workaround was retired.
- `/home/pi/Recordings` should be `pi:pi` and `775`.
- Generated MP3s should be `pi:pi` and group writable.
- The health check local-recency warning is disabled by default because rclone moves files away quickly. Re-enable it only when troubleshooting a setup that keeps local MP3s.
- The health check and status summary read `VOX_CHANNELS` and source each channel env file. Per-channel recent-save behavior belongs in `HEALTH_CHECK_RECENT_SAVE` and `MAX_SAVE_AGE_MINUTES`, not hardcoded script logic.
- Use `sudo /opt/train-recorder/Scripts/status_summary.sh` for a quick read-only operator summary before pulling detailed logs.
- SOX clipping warnings have been observed. Production tuning was moved from `SOX_VOLUME=5` toward `SOX_VOLUME=4`; compare clipping warnings and intelligibility after a soak.
- Channel env files load after `common.env`, so `SOX_VOLUME` can be tuned per channel. Current production direction is lowering `freq160545.env` one notch below the shared default to reduce channel 1 clipping.

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
journalctl -u vox@freq160545.service -u vox@freq161265.service -u train-recorder-sync.service --since today
```

Keep changes small and soak-test after service or permission changes.
