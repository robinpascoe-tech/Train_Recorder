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
  common.env.example         Shared recorder environment defaults.
  freq160545.env.example     160.545 MHz recorder settings.
  freq161265.env.example     161.265 MHz recorder settings.
  rtl_airband.conf.example   Example RTLSDR-Airband config. Copy and add secrets locally.
  sync.env.example           Optional rclone sync settings.
  system.pa                  PulseAudio system-mode config with two null sinks.
Scripts/
  install.sh                 Conservative Raspberry Pi installer.
  health_check.sh            Basic service, PulseAudio, storage, and recording checks.
  cleanup_empty_dirs.sh      Daily cleanup for empty local recording directories.
  vox_record.sh              Shared configurable VOX recorder.
  vox.sh                     160.545 MHz recorder wrapper.
  vox2.sh                    161.265 MHz recorder wrapper.
  sync.sh                    Optional rclone move script.
  status_summary.sh          Read-only operator status summary.
Service_Files/
  *.service                  systemd units for PulseAudio, RTLSDR-Airband, VOX recorders, health, sync, and cleanup.
  *.timer                    Optional systemd timers for health checks, rclone sync, and cleanup.
docs/
  INSTALL.md                 Raspberry Pi setup notes.
  ARCHITECTURE.md            Signal flow and operational model.
  ROADMAP.md                 Follow-up ideas for continued development.
AGENTS.md                    Context for future coding agents and maintainers.
```

## Secret Handling

Do not commit your real Broadcastify/Icecast password, mountpoint, or rclone credentials. Keep your live `rtl_airband.conf` outside git or copy it to `Config/rtl_airband.conf`, which is ignored by this repository.

## Quick Start

1. Install RTLSDR-Airband, PulseAudio, SOX with MP3 support, and rclone if you want cloud offload.
2. Copy this repo to the Raspberry Pi, for example `/opt/train-recorder`.
3. Copy `Config/rtl_airband.conf.example` to `/usr/local/etc/rtl_airband.conf` and fill in your own feed details.
4. Copy `Config/system.pa` to the PulseAudio system config path used by your distribution.
5. Copy `Config/*.env.example` to `/etc/train-recorder/*.env` and edit local settings.
6. Copy the files in `Service_Files/` to `/etc/systemd/system/`.
7. Enable and start the services.

See [docs/INSTALL.md](docs/INSTALL.md) for a fuller checklist.

See [docs/ROADMAP.md](docs/ROADMAP.md) for follow-up ideas.

## Development Notes

The VOX recorder is intentionally parameterized with environment variables so additional channels can be added without duplicating the recording loop. The wrapper scripts keep the current two-channel setup readable while `Scripts/vox_record.sh` holds the shared behavior. Each recorder service loads `common.env` first and its channel-specific env file second, so values such as `SOX_VOLUME` can be tuned per channel.

Useful variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PULSE_MONITOR` | required | PulseAudio monitor source, such as `myfreq1sink.monitor`. |
| `OUTPUT_ROOT` | `/home/pi/Recordings` | Root folder for dated recording directories. |
| `TEMP_DIR` | `/mnt/ramdisk` | Temporary recording location. |
| `PULSE_SERVER` | `unix:/run/pulse/native` | PulseAudio server socket used by health checks. |
| `SOX_VOLUME` | `4` | SOX input gain applied before silence detection and MP3 encoding; may be overridden in a channel env file. |
| `MIN_BYTES` | `700` | Discard files smaller than this threshold. |
| `START_DURATION` | `0.2` | SOX leading-silence trigger duration. |
| `STOP_DURATION` | `13.0` | SOX trailing-silence duration before closing a file. |
| `RECORDING_UMASK` | `0002` | Permissions mask for generated folders and MP3s. |
| `CHECK_RECENT_LOCAL_RECORDINGS` | `false` | Enables an optional warning when no recent MP3s remain under `OUTPUT_ROOT`; keep disabled when rclone moves files away quickly. |
| `CHECK_VOX1_RECENT_SAVE` | `true` | Warn when no recent `160.545` save appears in the `vox.service` journal. |
| `MAX_VOX1_SAVE_AGE_MINUTES` | `1440` | Recent-save window for the primary `160.545` channel. |
| `CHECK_VOX2_RECENT_SAVE` | `false` | Optional recent-save check for the quieter `161.265` channel. |
| `MAX_VOX2_SAVE_AGE_MINUTES` | `4320` | Recent-save window for the optional `161.265` check. |
| `CHECK_RECENT_SYNC_SUCCESS` | `true` | Fail health checks when `train-recorder-sync.service` has not finished recently. |
| `MAX_SYNC_SUCCESS_AGE_MINUTES` | `30` | Recent-success window for the rclone sync service. |
| `RCLONE_MIN_AGE` | `15s` | Minimum file age before `sync.sh` allows rclone to move a completed MP3. |
| `CLIPPING_WINDOW_MINUTES` | `1440` | Journal lookback window used by `status_summary.sh` for clipping warnings. |
| `JOURNAL_WINDOW_MINUTES` | `10080` | Journal lookback window used by `status_summary.sh` for last-event summaries. |

## Public Release Checklist

- Rotate any credential that was ever committed to a local or private copy.
- Verify git history contains no real credentials before pushing publicly.
- Choose a license before publishing.
- Add hardware notes for the exact Raspberry Pi, RTL-SDR dongle, antenna, and power setup.
- Add screenshots or sample sanitized logs if useful for troubleshooting.
