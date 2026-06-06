# Architecture

## Signal Flow

```text
RTL-SDR dongle
  -> RTLSDR-Airband
      -> 160.545 MHz NFM
          -> PulseAudio sink: myfreq1sink
          -> Broadcastify/Icecast mixer output
      -> 161.265 MHz NFM
          -> PulseAudio sink: myfreq2sink

PulseAudio monitor sources
  -> SOX VOX recorder services
      -> temporary MP3s in /mnt/ramdisk
      -> /home/pi/Recordings/YYYY/MM-Mon/DD-Day/*.mp3
      -> rclone move to OneDrive
```

## Why This Architecture

RTLSDR-Airband is excellent at receiving multiple nearby NFM channels from one RTL-SDR and streaming to Broadcastify. Its native MP3 file output was tested on the target Pi with versions 5.1.1 and 5.2.0, but it did not create files reliably in this deployment. The PulseAudio plus SOX recorder path has run reliably for a long time, so the project keeps that as the production architecture and hardens the surrounding scripts and services.

## Runtime Pieces

`rtl_airband.service` starts RTLSDR-Airband and reads the installed RTL-Airband config.

`pulseaudio.service` starts PulseAudio in system mode. The included `system.pa` creates two null sinks named `myfreq1sink` and `myfreq2sink`; their `.monitor` sources are used by SOX.

`vox.service` records from `myfreq1sink.monitor` and names files with `_160.545`.

`vox2.service` records from `myfreq2sink.monitor` and names files with `_161.265`.

`sync.sh` is a small rclone helper for moving completed recordings to a configured remote. It runs as `pi` so it can reuse the existing rclone/OneDrive tokens under `/home/pi/.config/rclone`. It uses a short minimum-age guard before moving files so rclone does not race a just-closed SOX recording.

`train-recorder-health.service` runs `Scripts/health_check.sh` as a one-shot check. The optional timer can run it periodically and write results to the journal. Health checks verify services, writable paths, PulseAudio sources, recent primary-channel saves, and recent successful sync runs. The local recent-recording check is disabled by default because rclone normally drains `/home/pi/Recordings` shortly after files are created. The quieter `161.265` recent-save check is disabled by default to avoid false warnings during normal quiet periods.

`train-recorder-sync.service` and `train-recorder-sync.timer` provide an optional systemd-native rclone move job.

`train-recorder-cleanup.service` and `train-recorder-cleanup.timer` remove empty local date directories once a day. Empty directory cleanup is kept separate from the 5-minute rclone move job to avoid repeatedly deleting and recreating the current day's folder tree. Cleanup walks deepest-first, so an empty `Year/Month/Day` branch can be removed in one run, and logs a summary count instead of every deleted path.

The recorder, sync, and cleanup services run as `pi:pi`. This keeps PulseAudio access, generated MP3 ownership, and rclone credentials in one user context.

## Configuration

Recorder settings live in environment files under `/etc/train-recorder`:

```text
common.env       Shared output, temp, SOX, and silence settings.
freq160545.env   First recorder channel settings.
freq161265.env   Second recorder channel settings.
sync.env         Optional rclone settings.
```

The wrapper scripts still provide defaults, but the environment files are the preferred place to tune a live install. Each recorder service loads `common.env` first and its channel-specific env file second, so channel files can override shared values such as `SOX_VOLUME`.

## Deployed Layout

```text
/opt/train-recorder        Repository-backed application files.
/etc/train-recorder        Local environment files and tunable settings.
/usr/local/etc             Live RTLSDR-Airband config.
/etc/pulse/system.pa       PulseAudio system-mode sink config.
/home/pi/Recordings        Local recording spool before rclone moves files.
/mnt/ramdisk               Temporary SOX output files.
/home/pi/.config/rclone    pi user's OneDrive authentication.
```

## Adding Another Channel

1. Add another `module-null-sink` entry to `Config/system.pa`.
2. Add another RTLSDR-Airband channel output pointed at that sink.
3. Add a wrapper script or systemd unit that sets `PULSE_MONITOR`, `OUTPUT_SUFFIX`, and `MIN_BYTES`.
4. Enable the new service with systemd.
