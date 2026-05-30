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
      -> /home/pi/Recordings/YYYY/MM-Mon/DD-Day/*.mp3
      -> optional rclone move
```

## Runtime Pieces

`rtl_airband.service` starts RTLSDR-Airband and reads the installed RTL-Airband config.

`pulseaudio.service` starts PulseAudio in system mode. The included `system.pa` creates two null sinks named `myfreq1sink` and `myfreq2sink`; their `.monitor` sources are used by SOX.

`vox.service` records from `myfreq1sink.monitor` and names files with `_160.545`.

`vox2.service` records from `myfreq2sink.monitor` and names files with `_161.265`.

`sync.sh` is a small rclone helper for moving completed recordings to a configured remote.

## Adding Another Channel

1. Add another `module-null-sink` entry to `Config/system.pa`.
2. Add another RTLSDR-Airband channel output pointed at that sink.
3. Add a wrapper script or systemd unit that sets `PULSE_MONITOR`, `OUTPUT_SUFFIX`, and `MIN_BYTES`.
4. Enable the new service with systemd.
