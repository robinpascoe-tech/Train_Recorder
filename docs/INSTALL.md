# Install Notes

These notes assume a Raspberry Pi-style Linux host and an install path of `/opt/train-recorder`.

## Dependencies

Install and configure:

- RTLSDR-Airband
- RTL-SDR drivers and udev rules
- PulseAudio
- SOX with MP3 support
- rclone, optional

## Prepare Config

Clone or copy the repository to the Pi:

```bash
sudo git clone https://github.com/YOUR_USER/train-recorder.git /opt/train-recorder
sudo chown -R pi:pi /opt/train-recorder
chmod +x /opt/train-recorder/Scripts/*.sh
```

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

Create the RAM disk and recordings directory if your system does not already do this:

```bash
sudo mkdir -p /mnt/ramdisk /home/pi/Recordings
sudo chown -R pi:pi /home/pi/Recordings /mnt/ramdisk
sudo chmod 775 /home/pi/Recordings
```

On a Raspberry Pi, create the RAM disk persistently by adding this line to `/etc/fstab`:

```fstab
tmpfs /mnt/ramdisk tmpfs nodev,nosuid,size=50M 0 0
```

Then mount and verify it:

```bash
sudo mount /mnt/ramdisk
df -h /mnt/ramdisk
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

## Install Services

```bash
sudo cp /opt/train-recorder/Service_Files/*.service /etc/systemd/system/
sudo cp /opt/train-recorder/Service_Files/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pulseaudio.service rtl_airband.service vox.service vox2.service
sudo systemctl start pulseaudio.service
sudo systemctl start rtl_airband.service
sudo systemctl start vox.service vox2.service
```

Optional health and sync timers:

```bash
sudo systemctl enable --now train-recorder-health.timer
sudo systemctl enable --now train-recorder-sync.timer
```

The VOX recorder services and sync service run as the `pi` user. This keeps generated recordings and rclone/OneDrive credentials in the same user context, so root-owned recordings and recursive `chmod 777` cron workarounds should not be needed.

Check status and logs:

```bash
systemctl status pulseaudio.service rtl_airband.service vox.service vox2.service
journalctl -u rtl_airband.service -u vox.service -u vox2.service -f
/opt/train-recorder/Scripts/health_check.sh
```

Check the systemd timers:

```bash
systemctl list-timers --all | grep train-recorder
journalctl -u train-recorder-sync.service -u train-recorder-health.service --since today
```

## Optional rclone Offload

Configure rclone for your destination, then override `RCLONE_REMOTE` if the default does not match your setup:

```bash
sudo nano /etc/train-recorder/sync.env
systemctl start train-recorder-sync.service
```

For unattended operation, enable `train-recorder-sync.timer`. It runs `train-recorder-sync.service` every 5 minutes, matching the original cron cadence.

If migrating from the old cron-based setup, comment out the previous `pi` crontab line after the timer is active:

```cron
# */5 * * * * /home/pi/sync.sh # replaced by train-recorder-sync.timer
```

## Publishing Safely

Before pushing this repository to GitHub, rotate any credentials that were ever committed locally and remove them from history. The current public-facing config is an example file only; keep the real config ignored and private.
