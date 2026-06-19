# Operations

## Logs

RailWave Pi services write to the systemd journal. There are no project-managed flat log files by default.

Useful log commands:

```bash
journalctl -u rtl_airband.service --since today
journalctl -u vox@freq160545.service -u vox@freq161265.service --since today
journalctl -u train-recorder-sync.service --since today
journalctl -u train-recorder-health.service -u train-recorder-cleanup.service --since today
journalctl -u train-recorder-dashboard.service -u train-recorder-wifi-check.service --since today
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
CLIPPING_WARN_COUNT=50
CLIPPING_WARN_MAX_SAMPLES=1000000
JOURNAL_WINDOW_MINUTES=10080
```

Set those in `/etc/train-recorder/common.env` if the default windows or clipping warning thresholds are too short or too noisy for your site. A value of `0` disables the matching clipping threshold. Clipping counts remain visible even when they are below the warning threshold.

## Recording Sample Diagnostics

Use the recording diagnostics report when tuning SOX volume or VOX settings:

```bash
sudo /opt/train-recorder/Scripts/recording_diagnostics.py
sudo /opt/train-recorder/Scripts/recording_diagnostics.py --json
```

The report scans recent local MP3 files under `OUTPUT_ROOT`, grouped by each channel `OUTPUT_SUFFIX`, and runs bounded `soxi`/`sox stat` checks on the newest samples. Because rclone usually moves recordings quickly, it also reads recent recorder journal `Saved ...` events so save counts and byte totals remain visible after local files are gone.

Use the text output for a quick tuning check. Use `--json` when comparing counts, byte totals, durations, RMS amplitude, and peak amplitude over time.

Defaults:

```text
RECORDING_DIAGNOSTICS_LOOKBACK_HOURS=24
RECORDING_DIAGNOSTICS_JOURNAL_HOURS=24
RECORDING_DIAGNOSTICS_MAX_FILES=20
```

When local sample counts are zero but recent saves are nonzero, rclone has already moved the MP3s. That is normal on healthy offload-enabled installs.

## RTLSDR-Airband Squelch Tuning

Quiet channels can false-open auto squelch during noise or interference events. For `161.265`, the current production setting is:

```yaml
channels:
  - name: freq161265
    squelch_snr_threshold: 14
```

The generator also supports optional per-channel `squelch_threshold`, `bandwidth`, and `ctcss` fields. Tune one channel at a time and use `site_config.sh diff` before `apply` so manual live changes do not drift from `/etc/train-recorder/site.yaml`.

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

For PulseAudio access, `pulse-access` is the required group for the system-mode socket checks. Missing `pulse` group membership is reported as a warning because existing installs can function correctly with `pulse-access` while still differing from the installer's preferred group set.

For automation or dashboard use, emit machine-readable JSON:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh doctor --json
```

## Deploy Validation

After pulling a new commit or changing deployed scripts, run the read-only deploy validator:

```bash
sudo /opt/train-recorder/Scripts/validate_deploy.sh
```

It checks the deployed git commit and worktree, core services, recorder channel services, timers, doctor, dashboard endpoints when enabled, the Wi-Fi/network check, the operator summary, and recent warning-level journal entries. It exits nonzero when required validation fails.

For unattended host recovery planning, see [WATCHDOG.md](WATCHDOG.md). Enable the Raspberry Pi hardware watchdog only after reviewing the rollback path and soaking the current service restart behavior.

## Web Dashboard

The optional dashboard is a read-only Flask app backed by the same status JSON:

```bash
sudo apt install python3-flask
sudo systemctl status train-recorder-dashboard.service
```

By default it listens on port `8080`:

```text
http://<pi-address>:8080/
```

The dashboard exposes `/api/status` for the raw JSON payload. It is designed for trusted LAN use only. Do not expose it directly to the internet without a separate authentication and TLS layer such as a VPN or reverse proxy.

For SSH, password, firewall, and dashboard exposure guidance, see [SECURITY.md](SECURITY.md).

The dashboard includes host, IP, Wi-Fi SSID, service, timer, storage, sync, latest Wi-Fi/network-check status, recent journal save counts, and threshold-aware SOX clipping status. If the dashboard service was already running when scripts were updated, restart it so it loads the latest code:

```bash
sudo systemctl restart train-recorder-dashboard.service
```

## Dashboard History

The optional dashboard history timer records compact status snapshots for a rolling local view:

```bash
sudo systemctl enable --now train-recorder-status-history.timer
```

The history file is:

```text
/var/lib/train-recorder/status-history.json
```

The dashboard reads this file to show sample freshness, operational warning trends, Wi-Fi failures, pending-recording peaks, and clipping trends. Clipping is displayed separately from operational warnings so a known audio-level tuning issue does not hide current service health. Clipping samples are counted as a trend, while the warning color follows `CLIPPING_WARN_COUNT` and `CLIPPING_WARN_MAX_SAMPLES`. The history file is intentionally small JSON, not a database. The default retention window is 24 hours and can be changed with:

```text
STATUS_HISTORY_RETENTION_HOURS=24
```

Inspect the history directly:

```bash
sudo /opt/train-recorder/Scripts/status_history.py --json --no-write
```

## Wi-Fi and Network Check

The optional Wi-Fi/network check can be run manually or by timer:

```bash
sudo /opt/train-recorder/Scripts/wifi_check.py
sudo /opt/train-recorder/Scripts/wifi_check.py --json
```

The latest result is written to:

```text
/var/lib/train-recorder/wifi-check.json
```

Enable the check-only timer:

```bash
sudo systemctl enable --now train-recorder-wifi-check.timer
```

The script checks local IP assignment, default gateway reachability, DNS resolution, rclone remote reachability when configured, and the local dashboard API. It also records Wi-Fi SSID when the installed network tools can detect it. The JSON state preserves `last_failure` after recovery so the dashboard and diagnostics bundle can show the most recent network failure age and failed check names.

Manual remedy mode is available:

```bash
sudo /opt/train-recorder/Scripts/wifi_check.py --remedy
```

Use remedy mode cautiously. It attempts conservative local recovery actions first. Reboot is disabled by default. If you explicitly set `WIFI_CHECK_ALLOW_REBOOT=true`, remedy mode may request one reboot after `WIFI_CHECK_REBOOT_FAILURE_THRESHOLD` consecutive failures affecting core connectivity checks (`ip-address`, `gateway`, or `dns`). It then latches that reboot attempt until a successful later check clears the latch, which avoids reboot loops during a persistent outage such as an unplugged router.

## Diagnostics Bundle

For support or deeper troubleshooting, collect a sanitized diagnostics bundle:

```bash
sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
```

The script writes a timestamped `.tar.gz` under `/tmp` by default. It gathers doctor output, status JSON, service states, timers, recent journals, package versions, PulseAudio sinks/sources, disk and log usage, recording counts and permissions, rclone reachability checks, and redacted copies of RailWave Pi configs.

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

PCP is not required for RailWave Pi. Unless you intentionally use PCP metrics, disable it and remove its tmpfs logs:

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
