# Install Notes

These notes assume a Raspberry Pi-style Linux host and an install path of `/opt/train-recorder`.

## Dependencies

The installer can offer to install these packages for you:

- git, rsync, and CA certificates
- RTLSDR-Airband
- RTL-SDR drivers and udev rules
- PulseAudio
- SOX with MP3 and PulseAudio support
- rclone, optional

## Install Project Files

On a fresh Raspberry Pi OS image, install `git` first so the project can be cloned:

```bash
sudo apt update
sudo apt install -y git
```

Clone or copy the repository to the Pi:

```bash
sudo git clone https://github.com/robinpascoe-tech/Train_Recorder.git /opt/train-recorder
sudo chown -R pi:pi /opt/train-recorder
chmod +x /opt/train-recorder/Scripts/*.sh
```

For a guided, conservative install on a fresh Raspberry Pi, run:

```bash
cd /opt/train-recorder
sudo Scripts/install.sh
```

The installer can optionally install SOX, PulseAudio, rclone, RTL-SDR packages, and build RTLSDR-Airband from source with RTL-SDR, NFM, PulseAudio, libshout, and LAME support. The source build defaults to the project-tested `RTL_AIRBAND_REF=v5.2.0`; override that environment variable if you want another tag or branch. It does not overwrite existing env files, live RTLSDR-Airband config, PulseAudio config, or rclone credentials without prompting.

On a first pass, the installer prepares packages, directories, systemd units, PulseAudio access groups, and optional tmpfs mounts. If `/etc/train-recorder/site.yaml` does not exist yet, it intentionally skips service start prompts. Configure rclone and run `site_config.sh apply` after the site settings are ready; `apply` enables and starts the configured recorder services and timers. Finish the install by running `site_config.sh doctor`.

The RTLSDR-Airband source build installs development packages such as `build-essential`, `cmake`, `libpulse-dev`, `libfftw3-dev`, `libmp3lame-dev`, and related libraries. Those are expected if you choose to build from source. They can be left installed for future rebuilds; removing them later saves space but makes future RTLSDR-Airband upgrades less convenient.

## Configure OneDrive on a Headless Pi

Do this before running the site configuration wizard if this recorder will offload MP3s to OneDrive. The wizard asks for the rclone remote path, and it is easier to answer that prompt after the remote exists and has been tested.

`train-recorder-sync.service` runs as the `pi` user, so the rclone remote must be configured as `pi`, not as `root`. The token should live under:

```text
/home/pi/.config/rclone/rclone.conf
```

The examples below create a remote named `onedrive`. Use a different name if you also update `RCLONE_REMOTE` in `/etc/train-recorder/sync.env` or the wizard's rclone remote prompt.

Start on the Pi over SSH:

```bash
sudo -u pi rclone config
```

In the interactive prompts:

```text
n) New remote
name> onedrive
Storage> onedrive       # choose Microsoft OneDrive; on some rclone versions this is option 30
client_id>            # press Enter for the default unless you have your own app registration
client_secret>        # press Enter for the default unless you have your own app registration
Choose national cloud region for OneDrive> 1  # Microsoft Cloud Global
Edit advanced config? # usually n
Use web browser to automatically authenticate rclone with remote? # n
```

When rclone tells you to run `rclone authorize "onedrive"` on another machine, keep the Pi prompt open.

From a Windows machine with a browser, install rclone from <https://rclone.org/downloads/> or use an existing rclone install, then run this in PowerShell:

```powershell
rclone authorize "onedrive"
```

Log in to Microsoft in the browser window and approve access. PowerShell will print a long token between paste markers. Copy the whole token and paste it back into the waiting `config_token>` prompt on the Pi.

From an Ubuntu or other Linux desktop with a browser:

```bash
sudo apt update
sudo apt install rclone
rclone authorize "onedrive"
```

Log in through the browser, copy the returned token, and paste it into the Pi's `config_token>` prompt.

Back on the Pi, finish the remaining rclone prompts. For most OneDrive setups, choose the intended drive, confirm the remote, and quit config.

Verify the remote as the same user that the sync service uses:

```bash
sudo -u pi rclone lsd onedrive:
sudo -u pi rclone mkdir onedrive:TrainRecorderTest
sudo -u pi rclone rmdir onedrive:TrainRecorderTest
```

When the site wizard asks for the rclone remote, use the destination path you want recordings moved to, for example:

```text
onedrive:ONR/ONR_Tower3_NewLiskeard
```

Do not run `sudo rclone config` for this project unless you also intentionally change the sync service to run as root. Keeping rclone auth under the `pi` account avoids root-owned token files and matches the recorder service design.

## Configure RAM Disk

SOX writes each in-progress recording to a temporary file before moving the completed MP3 into the dated recording tree. The default temp directory is `/mnt/ramdisk`, which reduces SD card writes and keeps partial recordings out of the final archive path.

Create the RAM disk mount point and recording spool:

```bash
sudo mkdir -p /mnt/ramdisk /home/pi/Recordings
sudo chown -R pi:pi /home/pi/Recordings /mnt/ramdisk
sudo chmod 775 /home/pi/Recordings
```

On a Raspberry Pi, create the RAM disk persistently by adding this line to `/etc/fstab`:

```fstab
tmpfs /mnt/ramdisk tmpfs nodev,nosuid,size=50M 0 0
```

Mount and verify it:

```bash
sudo mount /mnt/ramdisk
df -h /mnt/ramdisk
```

The default `50M` size is enough for short railway voice transmissions. Increase it if your channels can produce long recordings or if you add more simultaneous recorder channels.

When the site wizard asks for the RAM disk/temp dir, use:

```text
/mnt/ramdisk
```

## Configure Log tmpfs

For Raspberry Pi installs that run continuously, consider placing `/var/log` on tmpfs to reduce SD card writes. This keeps routine system logs in RAM instead of writing them constantly to the card.

Add a line like this to `/etc/fstab`:

```fstab
tmpfs /var/log tmpfs defaults,noatime,nosuid,size=64m 0 0
```

Mount and verify it:

```bash
sudo mount /var/log
df -h /var/log
```

The `64m` size is usually enough for this recorder when journald retention is capped and unnecessary high-volume logging services are disabled. If your image includes Performance Co-Pilot (`pcp`), disable it unless you intentionally use PCP performance archives:

```bash
sudo systemctl disable --now pmcd pmlogger pmie pmproxy
sudo rm -rf /var/log/pcp
```

PCP can quickly fill a small `/var/log` tmpfs with performance archives. It is not required by Train Recorder, RTLSDR-Airband, PulseAudio, SOX, or rclone. See [OPERATIONS.md](OPERATIONS.md) for checking log usage during long soaks.

## PulseAudio Access

The recorder uses PulseAudio in system mode. SOX recorder services run as `pi`, while `rtl_airband.service` normally runs as root and writes to the PulseAudio null sinks. Both users need access to the system PulseAudio socket.

The installer configures these groups when PulseAudio packages are installed:

```bash
sudo usermod -aG pulse,pulse-access,audio pi
sudo usermod -aG pulse,pulse-access root
```

If you install PulseAudio manually or see PulseAudio `Access denied` errors from SOX or RTLSDR-Airband, run those commands and restart the affected services:

```bash
sudo systemctl restart pulseaudio.service
sudo systemctl restart rtl_airband.service
sudo systemctl restart 'vox@*.service'
```

On desktop-capable Raspberry Pi OS images, installing PulseAudio can also enable a per-user PulseAudio service and socket for `pi`. Train Recorder does not use that user session daemon; it should use only the system-mode `pulseaudio.service`. The installer offers to disable the per-user service by masking:

```text
~pi/.config/systemd/user/pulseaudio.service
~pi/.config/systemd/user/pulseaudio.socket
```

Check for duplicate PulseAudio daemons:

```bash
ps -eo user,group,pid,ppid,cmd | grep '[p]ulseaudio'
systemctl is-active pulseaudio.service
sudo -u pi XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active pulseaudio.service pulseaudio.socket
```

The expected recorder-appliance state is one active system daemon running as the `pulse` user, and inactive or masked user units for `pi`.

`site_config.sh doctor` requires `pulse-access` for system-mode PulseAudio access. It reports missing `pulse` group membership as a warning because some upgraded installs work correctly with `pulse-access` even if they differ from the installer's preferred group set.

## Generate Site Config

For a site-specific install, use `site_config.sh` instead of hand-editing every generated file:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh wizard
sudo /opt/train-recorder/Scripts/site_config.sh generate
sudo /opt/train-recorder/Scripts/site_config.sh plan
sudo /opt/train-recorder/Scripts/site_config.sh diff
sudo /opt/train-recorder/Scripts/site_config.sh apply
sudo /opt/train-recorder/Scripts/site_config.sh doctor
```

The wizard writes `/etc/train-recorder/site.yaml`. If that file already exists, the wizard loads it and uses the current values as prompt defaults so later frequency or site changes can be made incrementally. The generator reads that file and writes a preview under `/tmp/train-recorder-generated` by default. `plan` shows service-level changes, and `diff` shows generated file changes with Broadcastify mountpoint/password values redacted. `apply` runs preflight checks, backs up replaced files under `/etc/train-recorder/backups/<timestamp>/`, updates RTLSDR-Airband and PulseAudio configs, enables/restarts the configured `vox@...` services, and enables the health, cleanup, and sync timers when applicable. `doctor` is the read-only validation step after apply; it checks services, timers, PulseAudio sources, paths, permissions, packages, rclone reachability, known legacy-service pitfalls, PCP, raspiBackup hooks, and recent SOX clipping warnings. You can also copy `Config/site.example.yaml` to `/etc/train-recorder/site.yaml` and edit it manually.

### Wizard Prompt Reference

The wizard prompts are intentionally short. Use this reference when deciding what each value should be.

| Prompt | Meaning |
| --- | --- |
| Site name | Human-friendly name for this recorder site. Used as the default feed name and in generated config metadata. |
| How many frequencies should be recorded | Number of NFM channels to receive and record. All configured frequencies must fit within the usable bandwidth of the selected SDR. |
| Frequency N in MHz | Radio frequency for this channel, in MHz, for example `160.545`. |
| Channel env name | Short service/config identifier for the channel, for example `freq160545`. This becomes `/etc/train-recorder/<name>.env` and `vox@<name>.service`, so use letters, numbers, dots, underscores, or dashes only. |
| PulseAudio sink name | Name of the PulseAudio null sink RTLSDR-Airband should write this channel to. SOX records from the matching `<sink>.monitor` source. |
| Output filename suffix | Suffix added to each MP3 filename so recordings identify the channel, for example `_160.545`. |
| SOX start duration | Amount of audio, in seconds, SOX must hear above the start threshold before it begins saving a transmission. Larger values can ignore short noise bursts, but may clip the beginning of short transmissions. |
| Minimum recording bytes | Small-file guard. Recordings smaller than this are discarded as likely noise or false starts. |
| Require recent-save health warning for this channel | Whether health checks should warn when this channel has not saved a recording recently. Enable it for active channels; disable it for quiet channels that may go a day or two without traffic. |
| Max save age minutes | Age threshold used when recent-save health warnings are enabled for the channel. |
| Enable RTLSDR-Airband AFC for this channel | Enables RTLSDR-Airband automatic frequency correction for the channel. This can help track small tuning offsets; leave disabled if it causes unstable tuning on a quiet or adjacent channel. |
| Stream one channel to Broadcastify/Icecast | Enables an Icecast/Broadcastify stream output in addition to local recording. |
| Channel to stream | Channel env name to send to the Icecast/Broadcastify mixer. Usually the primary road or dispatch channel. |
| Icecast server | Hostname supplied by Broadcastify or another Icecast provider. |
| Icecast port | Port supplied by the stream provider. Broadcastify often uses `80` or `8000`, depending on the feed assignment. |
| Icecast mountpoint | Provider-assigned mountpoint for the stream. This is sensitive feed information; the wizard preserves an existing value without printing it. |
| Icecast username | Stream source username. Broadcastify commonly uses `source`. |
| Icecast password | Stream source password. This is secret; the wizard preserves an existing value without printing it. |
| Feed name | Public stream/feed display name sent to Icecast/Broadcastify metadata. |
| Genre | Stream genre metadata. `RAIL` is appropriate for Broadcastify rail feeds. |
| Description | Stream description metadata sent to Icecast/Broadcastify. |
| Recording output root | Local spool root for completed MP3 recordings before rclone moves them, normally `/home/pi/Recordings`. |
| RAM disk/temp dir | Temporary directory where SOX writes recordings before moving completed files into the dated output tree, normally `/mnt/ramdisk`. |
| rclone remote, blank to skip | Destination remote path for offloading completed recordings, for example `onedrive:ONR/ONR_Tower3_NewLiskeard`. Leave blank if this site should not generate sync config. |
| RTL-SDR gain | RTLSDR-Airband tuner gain. Higher gain can improve weak signals but may increase overload or clipping. |
| Usable SDR bandwidth MHz | Approximate usable tuner bandwidth for checking whether all requested frequencies fit on one RTL-SDR. A common conservative value is `2.4`. |

## Manual Config Fallback

The preferred path is `site_config.sh wizard`, `generate`, `plan`, `diff`, `apply`, and `doctor`. If you are not using generated config yet, you can still seed and edit the individual files manually.

Copy the example RTL-Airband config and edit the local copy:

```bash
sudo cp /opt/train-recorder/Config/rtl_airband.conf.example /usr/local/etc/rtl_airband.conf
sudo nano /usr/local/etc/rtl_airband.conf
```

Set your own Broadcastify/Icecast `server`, `port`, `mountpoint`, `username`, and `password`.

Install the PulseAudio system config:

```bash
sudo cp /opt/train-recorder/Config/system.pa /etc/pulse/system.pa
```

Install recorder environment files:

```bash
sudo mkdir -p /etc/train-recorder
sudo cp /opt/train-recorder/Config/common.env.example /etc/train-recorder/common.env
sudo cp /opt/train-recorder/Config/freq160545.env.example /etc/train-recorder/freq160545.env
sudo cp /opt/train-recorder/Config/freq161265.env.example /etc/train-recorder/freq161265.env
sudo cp /opt/train-recorder/Config/sync.env.example /etc/train-recorder/sync.env
sudo nano /etc/train-recorder/common.env
```

Channel-specific env files are loaded after `common.env`, so they can override shared values. For example, set `SOX_VOLUME=3` in `/etc/train-recorder/freq160545.env` to lower only the `160.545` recorder while leaving the other channel on the shared value.

## Install Services

`site_config.sh apply` installs generated config files, reconciles `vox@...` services, and enables the train-recorder timers, but it does not replace the full system installer. If you are setting up manually, install the systemd units:

```bash
sudo cp /opt/train-recorder/Service_Files/*.service /etc/systemd/system/
sudo cp /opt/train-recorder/Service_Files/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pulseaudio.service rtl_airband.service vox@freq160545.service vox@freq161265.service
sudo systemctl start pulseaudio.service
sudo systemctl start rtl_airband.service
sudo systemctl start vox@freq160545.service vox@freq161265.service
```

Optional health and sync timers:

```bash
sudo systemctl enable --now train-recorder-health.timer
sudo systemctl enable --now train-recorder-sync.timer
sudo systemctl enable --now train-recorder-cleanup.timer
```

The VOX recorder services and sync service run as the `pi` user. This keeps generated recordings and rclone/OneDrive credentials in the same user context, so root-owned recordings and recursive `chmod 777` cron workarounds should not be needed.

Check status and logs:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh doctor
systemctl status pulseaudio.service rtl_airband.service vox@freq160545.service vox@freq161265.service
journalctl -u rtl_airband.service -u vox@freq160545.service -u vox@freq161265.service -f
sudo /opt/train-recorder/Scripts/status_summary.sh
sudo /opt/train-recorder/Scripts/health_check.sh
```

Check the systemd timers:

```bash
systemctl list-timers --all | grep train-recorder
journalctl -u train-recorder-sync.service -u train-recorder-health.service --since today
```

The health check reads `VOX_CHANNELS` from `common.env` and then sources each channel env file. A channel can set `HEALTH_CHECK_RECENT_SAVE=true` and `MAX_SAVE_AGE_MINUTES=1440` to warn when no recent save appears, or set `HEALTH_CHECK_RECENT_SAVE=false` for quieter channels. The sync check fails if `train-recorder-sync.service` has not completed within `MAX_SYNC_SUCCESS_AGE_MINUTES`.

For long-running installs, configure journal retention so service logs cannot slowly fill the SD card. See [OPERATIONS.md](OPERATIONS.md).

## Optional rclone Offload

Configure rclone for your destination, then override `RCLONE_REMOTE` if the default does not match your setup:

```bash
sudo nano /etc/train-recorder/sync.env
systemctl start train-recorder-sync.service
```

For unattended operation, enable `train-recorder-sync.timer`. It runs `train-recorder-sync.service` every 5 minutes, matching the original cron cadence. The default `RCLONE_MIN_AGE=15s` keeps rclone from moving a file immediately after SOX closes it.

Enable `train-recorder-cleanup.timer` to remove empty local date directories once a day. This keeps the local spool tidy without making the 5-minute sync job delete and recreate the current date folder tree. The cleanup walks deepest-first, so empty day, month, and year folders are removed together when no files remain below them. It logs only a summary count to keep journal output readable.

If migrating from the old cron-based setup, comment out the previous `pi` crontab line after the timer is active:

```cron
# */5 * * * * /home/pi/sync.sh # replaced by train-recorder-sync.timer
```

Test the sync service:

```bash
sudo systemctl start train-recorder-sync.service
journalctl -u train-recorder-sync.service --since "5 minutes ago"
```

## Publishing Safely

Before pushing this repository to GitHub, rotate any credentials that were ever committed locally and remove them from history. The current public-facing config is an example file only; keep the real config ignored and private.
