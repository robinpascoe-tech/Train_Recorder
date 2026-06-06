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
