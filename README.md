# Train Recorder

Raspberry Pi railway radio recorder using an RTL-SDR receiver, RTLSDR-Airband, PulseAudio null sinks, SOX voice-activated recording, and optional rclone offload.

This project currently targets an Ontario Northland Railway monitoring setup with:

- RTLSDR-Airband receiving two NFM channels from one RTL-SDR dongle.
- 160.545 MHz streamed to Broadcastify/Icecast and sent to a PulseAudio sink.
- 161.265 MHz sent to a second PulseAudio sink.
- Two SOX-based VOX recorder services that write one MP3 per transmission.
- Optional rclone sync/move of recordings to cloud storage.

## Repository Layout

```text
Config/
  rtl_airband.conf.example   Example RTLSDR-Airband config. Copy and add secrets locally.
  system.pa                  PulseAudio system-mode config with two null sinks.
Scripts/
  vox_record.sh              Shared configurable VOX recorder.
  vox.sh                     160.545 MHz recorder wrapper.
  vox2.sh                    161.265 MHz recorder wrapper.
  sync.sh                    Optional rclone move script.
Service_Files/
  *.service                  systemd units for PulseAudio, RTLSDR-Airband, and VOX recorders.
docs/
  INSTALL.md                 Raspberry Pi setup notes.
  ARCHITECTURE.md            Signal flow and operational model.
  NATIVE_RECORDING_TEST.md   Test plan for RTLSDR-Airband native MP3 recording.
  ROADMAP.md                 Follow-up ideas for continued development.
```

## Secret Handling

Do not commit your real Broadcastify/Icecast password, mountpoint, or rclone credentials. Keep your live `rtl_airband.conf` outside git or copy it to `Config/rtl_airband.conf`, which is ignored by this repository.

The first local commit in this repo included a live Broadcastify password. Before publishing publicly, rotate that password and rewrite/remove the old git history.

## Quick Start

1. Install RTLSDR-Airband, PulseAudio, SOX with MP3 support, and rclone if you want cloud offload.
2. Copy this repo to the Raspberry Pi, for example `/opt/train-recorder`.
3. Copy `Config/rtl_airband.conf.example` to `/usr/local/etc/rtl_airband.conf` and fill in your own feed details.
4. Copy `Config/system.pa` to the PulseAudio system config path used by your distribution.
5. Copy the files in `Service_Files/` to `/etc/systemd/system/`.
6. Enable and start the services.

See [docs/INSTALL.md](docs/INSTALL.md) for a fuller checklist.

See [docs/ROADMAP.md](docs/ROADMAP.md) for follow-up ideas.

## Development Notes

The VOX recorder is intentionally parameterized with environment variables so additional channels can be added without duplicating the recording loop. The wrapper scripts keep the current two-channel setup readable while `Scripts/vox_record.sh` holds the shared behavior.

Useful variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PULSE_MONITOR` | required | PulseAudio monitor source, such as `myfreq1sink.monitor`. |
| `OUTPUT_ROOT` | `/home/pi/Recordings` | Root folder for dated recording directories. |
| `TEMP_DIR` | `/mnt/ramdisk` | Temporary recording location. |
| `MIN_BYTES` | `700` | Discard files smaller than this threshold. |
| `START_DURATION` | `0.2` | SOX leading-silence trigger duration. |
| `STOP_DURATION` | `13.0` | SOX trailing-silence duration before closing a file. |

## Public Release Checklist

- Rotate the Broadcastify/Icecast password that was previously committed locally.
- Rewrite or recreate git history so no real credentials remain.
- Choose a license before publishing.
- Add hardware notes for the exact Raspberry Pi, RTL-SDR dongle, antenna, and power setup.
- Add screenshots or sample sanitized logs if useful for troubleshooting.
