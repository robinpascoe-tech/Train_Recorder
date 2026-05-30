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
sudo chown -R pi:pi /home/pi/Recordings
```

## Install Services

```bash
sudo cp /opt/train-recorder/Service_Files/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pulseaudio.service rtl_airband.service vox.service vox2.service
sudo systemctl start pulseaudio.service
sudo systemctl start rtl_airband.service
sudo systemctl start vox.service vox2.service
```

Check status and logs:

```bash
systemctl status pulseaudio.service rtl_airband.service vox.service vox2.service
journalctl -u rtl_airband.service -u vox.service -u vox2.service -f
```

## Optional rclone Offload

Configure rclone for your destination, then override `RCLONE_REMOTE` if the default does not match your setup:

```bash
RCLONE_REMOTE='onedrive:ONR/ONR_Tower3_NewLiskeard' /opt/train-recorder/Scripts/sync.sh
```

For unattended operation, create a timer or cron job that runs `Scripts/sync.sh`.

## Publishing Safely

Before pushing this repository to GitHub, rotate any credentials that were ever committed locally and remove them from history. The current public-facing config is an example file only; keep the real config ignored and private.
