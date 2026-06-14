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

`install.sh` is a conservative Raspberry Pi installer. It can install prerequisite packages, optionally build RTLSDR-Airband from source, copy project files, seed missing local configs, install systemd units, configure PulseAudio access groups, and set up optional tmpfs mounts. On a fresh install it prepares the host but skips service start prompts until `/etc/train-recorder/site.yaml` exists, so services are not started against placeholder config.

`site_config.sh` manages site-specific generated configuration. It can run an interactive wizard, generate `rtl_airband.conf`, `system.pa`, `common.env`, `sync.env`, and channel env files from `site.yaml`, show an apply plan, and reconcile live `vox@...` services. `apply` is the activation step for generated installs: it enables/restarts PulseAudio, RTLSDR-Airband, the configured recorder services, and the train-recorder timers. The YAML file is the desired state; generated files are artifacts. If `site.yaml` already exists, the wizard uses it as the default source for prompts and preserves sensitive Broadcastify values without printing them.

`rtl_airband.service` starts RTLSDR-Airband and reads the installed RTL-Airband config.

`pulseaudio.service` starts PulseAudio in system mode. The included `system.pa` creates two null sinks named `myfreq1sink` and `myfreq2sink`; their `.monitor` sources are used by SOX.

`vox@.service` is the templated recorder unit. Each instance loads `common.env` and `/etc/train-recorder/%i.env`, then runs `vox_record.sh`. For example, `vox@freq160545.service` records from `myfreq1sink.monitor` and names files with `_160.545`.

`sync.sh` is a small rclone helper for moving completed recordings to a configured remote. It runs as `pi` so it can reuse the existing rclone/OneDrive tokens under `/home/pi/.config/rclone`. It uses a short minimum-age guard before moving files so rclone does not race a just-closed SOX recording.

`train-recorder-health.service` runs `Scripts/health_check.sh` as a one-shot check. The optional timer can run it periodically and write results to the journal. Health checks verify shared services, writable paths, each configured `vox@...` service, each channel's PulseAudio source, per-channel recent-save policy, and recent successful sync runs. The local recent-recording check is disabled by default because rclone normally drains `/home/pi/Recordings` shortly after files are created. Quiet channels can set `HEALTH_CHECK_RECENT_SAVE=false` in their channel env file.

`train-recorder-sync.service` and `train-recorder-sync.timer` provide an optional systemd-native rclone move job.

`train-recorder-cleanup.service` and `train-recorder-cleanup.timer` remove empty local date directories once a day. Empty directory cleanup is kept separate from the 5-minute rclone move job to avoid repeatedly deleting and recreating the current day's folder tree. Cleanup walks deepest-first, so an empty `Year/Month/Day` branch can be removed in one run, and logs a summary count instead of every deleted path.

`status_summary.sh` is a read-only operator report. It summarizes service state, last recording saves, recent sync and cleanup success, pending local MP3s, clipping warnings, and disk usage.

The recorder, sync, and cleanup services run as `pi:pi`. This keeps PulseAudio access, generated MP3 ownership, and rclone credentials in one user context.

## Configuration

Recorder settings should be generated from `/etc/train-recorder/site.yaml` for new installs. The generated environment files under `/etc/train-recorder` remain readable and can still be edited directly for quick troubleshooting:

```text
site.yaml        Desired site configuration used by `site_config.sh`.
common.env       Shared output, temp, SOX, silence, and channel-list settings.
freq160545.env   First recorder channel settings.
freq161265.env   Second recorder channel settings.
sync.env         Optional rclone settings.
```

The legacy wrapper scripts still provide defaults for the original two channels, but the environment files and `vox@.service` are the preferred path for new installs. Each recorder service loads `common.env` first and its channel-specific env file second, so channel files can override shared values such as `SOX_VOLUME`.

`health_check.sh` and `status_summary.sh` read `VOX_CHANNELS` and then source each channel env file, so they do not need to be regenerated when channels are added or removed.

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

## Changing Channels

Use `site_config.sh` for channel add, remove, or frequency changes:

```bash
sudo /opt/train-recorder/Scripts/site_config.sh wizard
sudo /opt/train-recorder/Scripts/site_config.sh generate
sudo /opt/train-recorder/Scripts/site_config.sh plan
sudo /opt/train-recorder/Scripts/site_config.sh apply
```

The wizard updates `/etc/train-recorder/site.yaml`. `generate` writes a preview under `/tmp/train-recorder-generated`, `plan` shows which `vox@...` services would be enabled or disabled, and `apply` backs up replaced files before enabling/restarting PulseAudio, RTLSDR-Airband, the configured recorder instances, and train-recorder timers.

Manual channel changes are still possible, but every layer must agree: PulseAudio null sinks, RTLSDR-Airband channel outputs, `common.env` `VOX_CHANNELS`, channel env files, and enabled `vox@...` units.
