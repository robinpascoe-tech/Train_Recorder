# Operations

## Logs

Train Recorder services write to the systemd journal. There are no project-managed flat log files by default.

Useful log commands:

```bash
journalctl -u rtl_airband.service --since today
journalctl -u vox@freq160545.service -u vox@freq161265.service --since today
journalctl -u train-recorder-sync.service --since today
journalctl -u train-recorder-health.service -u train-recorder-cleanup.service --since today
```

Follow live recorder activity:

```bash
journalctl -u rtl_airband.service -u vox@freq160545.service -u vox@freq161265.service -f
```

Use the status summary for a quick read-only health view before digging through logs:

```bash
sudo /opt/train-recorder/Scripts/status_summary.sh
```

The summary reads recent journal history to report last saves, sync and cleanup success, clipping warnings, pending local MP3s, and disk usage. The lookback windows are controlled by:

```text
CLIPPING_WINDOW_MINUTES=1440
JOURNAL_WINDOW_MINUTES=10080
```

Set those in `/etc/train-recorder/common.env` if the default windows are too short or too noisy for your site.

## Doctor Check

Run the doctor check when validating an install or investigating a recorder that looks unhealthy:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh doctor
```

The standalone script can also be run directly:

```bash
sudo /opt/train-recorder/Scripts/doctor.sh
```

The doctor command is read-only. It reports `ok`, `warn`, and `fail` lines for common installation and runtime issues:

- core service and timer state
- configured `vox@...` services and PulseAudio monitor sources
- writable recording and temp paths
- root-owned recordings or directories
- PulseAudio system-mode groups and accidental per-user PulseAudio
- required packages and tools
- rclone reachability and recent sync success
- legacy `vox.service`/`vox2.service`
- PCP services that can fill `/var/log` tmpfs
- raspiBackup recorder stop/start hooks
- recent SOX clipping warnings

Warnings do not make the command fail, but any `fail` line exits with status `1`.

## Diagnostics Bundle

For support or deeper troubleshooting, collect a sanitized diagnostics bundle:

```bash
sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
```

The script writes a timestamped `.tar.gz` under `/tmp` by default. It gathers service states, timers, recent journals, package versions, PulseAudio sinks/sources, disk and log usage, recording counts and permissions, rclone reachability checks, and redacted copies of Train Recorder configs.

Known sensitive fields such as Broadcastify passwords, mountpoints, rclone tokens, and generic token/secret values are redacted from copied configs. Still review the bundle before sharing it publicly.

Useful overrides:

```bash
SINCE="6 hours ago" sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
OUT_DIR=/home/pi sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
```

## Journal Retention

Long-running Raspberry Pi installs should cap journal size so logs cannot slowly fill the SD card. This is handled by systemd-journald, not by logrotate.

Check current journal disk usage:

```bash
journalctl --disk-usage
```

Create a local journald override:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo nano /etc/systemd/journald.conf.d/train-recorder.conf
```

Recommended starting point for a small Raspberry Pi SD card:

```ini
[Journal]
SystemMaxUse=200M
SystemKeepFree=1G
MaxRetentionSec=30day
Compress=yes
```

Apply the change:

```bash
sudo systemctl restart systemd-journald
journalctl --disk-usage
```

For very small cards, lower `SystemMaxUse` to `100M`. For troubleshooting-heavy sites, raise it to `500M` or remove `MaxRetentionSec` and rely on size limits only.

## Log tmpfs and PCP

Some Raspberry Pi installs mount `/var/log` as tmpfs to reduce SD card wear:

```fstab
tmpfs /var/log tmpfs defaults,noatime,nosuid,size=64m 0 0
```

This is a good fit for a recorder appliance, but it makes log volume more important because `/var/log` has a fixed RAM-backed size. Check it during soak tests:

```bash
df -h /var/log
sudo du -h --max-depth=2 /var/log | sort -h | tail -40
journalctl --disk-usage
```

If `/var/log` is full, first find the large writers before increasing the tmpfs size. On Raspberry Pi OS images that include Performance Co-Pilot, PCP can create large archives under:

```text
/var/log/pcp
```

PCP is not required for Train Recorder. Unless you intentionally use PCP metrics, disable it and remove its tmpfs logs:

```bash
sudo systemctl disable --now pmcd pmlogger pmie pmproxy
sudo rm -rf /var/log/pcp
sudo systemctl restart systemd-journald
sudo systemctl restart rsyslog
df -h /var/log
```

After cleanup, confirm the recorder stack stayed active:

```bash
systemctl is-active rtl_airband.service pulseaudio.service vox@freq160545.service vox@freq161265.service
sudo /opt/train-recorder/Scripts/status_summary.sh
```

If `/var/log` still fills after PCP is disabled, inspect the largest files and tune the service that owns them. Increase the tmpfs size only after confirming the growth is expected.

## One-Time Cleanup

If the journal is already too large, vacuum it after setting a policy:

```bash
sudo journalctl --vacuum-time=30d
sudo journalctl --vacuum-size=200M
journalctl --disk-usage
```

Vacuuming removes old journal entries only. It does not affect recordings, rclone state, or service configuration.

## Recording Retention

The local recording spool is usually short-lived because `train-recorder-sync.timer` runs rclone every 5 minutes and moves completed MP3 files to the configured remote. The local cleanup timer removes empty date directories once a day.

Completed recordings are stored under `OUTPUT_ROOT` in a dated tree. A sanitized example:

```text
/home/pi/Recordings/
`-- 2026/
    `-- 06-Jun/
        |-- 06-Sat/
        |   |-- 2026-06-06_08-15-30_160.545.mp3
        |   |-- 2026-06-06_10-42-18_160.545.mp3
        |   `-- 2026-06-06_14-05-09_161.265.mp3
        `-- 07-Sun/
            |-- 2026-06-07_09-12-44_160.545.mp3
            `-- 2026-06-07_11-33-02_160.545.mp3
```

The filename format is:

```text
YYYY-MM-DD_HH-MM-SS_<output_suffix>.mp3
```

`output_suffix` comes from the channel env file or `site.yaml`; the example channels use `_160.545` and `_161.265`. rclone preserves the same relative directory structure at the destination.

Recording retention should normally be managed at the destination, for example in OneDrive or another rclone remote. Avoid deleting local files by age on the Pi unless you have intentionally disabled rclone offload or are using the Pi as the long-term archive.

If the Pi is the long-term archive, define a separate retention policy before enabling deletion. At minimum, decide:

- how many days or months of MP3 files to keep locally
- whether retention applies to all channels or only high-volume channels
- whether files must be confirmed on the remote before local deletion
- how much free space must remain on the SD card

Do not add `--delete-empty-src-dirs` to the frequent rclone move job. The daily cleanup service already handles empty directories with less churn.

## rclone Token Maintenance

rclone stores OneDrive OAuth tokens in the `pi` user's config file:

```text
/home/pi/.config/rclone/rclone.conf
```

rclone normally refreshes OneDrive access automatically while using the remote. The config file timestamp may change during normal operation because rclone writes refreshed token data back to that file.

If sync starts failing with authentication or expired-token errors, first confirm the failure is really from rclone:

```bash
journalctl -u train-recorder-sync.service --since today
sudo -u pi rclone lsd onedrive:
```

If the remote cannot authenticate, reconnect it as the `pi` user:

```bash
sudo -u pi rclone config reconnect onedrive:
```

On a headless Pi, answer no when asked to use a web browser on the Pi. When prompted, run the authorize command on a Windows, Ubuntu, or other desktop machine with a browser:

```bash
rclone authorize "onedrive"
```

Log in to Microsoft, copy the returned token, and paste it back into the Pi's `config_token>` prompt.

After reconnecting, test the remote and service:

```bash
sudo -u pi rclone lsd onedrive:
sudo systemctl start train-recorder-sync.service
journalctl -u train-recorder-sync.service --since "5 minutes ago"
```

Avoid `sudo rclone config reconnect ...` unless the sync service has intentionally been changed to run as root. A root-owned rclone token will not help `train-recorder-sync.service` when that service runs as `pi`.
