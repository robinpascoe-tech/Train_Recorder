# Native RTLSDR-Airband Recording Test

This branch tests replacing the PulseAudio/SOX recorder services with RTLSDR-Airband's native MP3 file output.

## Goal

Keep the current RF and Broadcastify behavior, but have RTLSDR-Airband write one MP3 file per transmission for both configured NFM frequencies.

## Test Config

Use:

```text
Config/rtl_airband.native-recording.conf.example
```

Copy it to the live config path on the Pi:

```bash
sudo cp /opt/train-recorder/Config/rtl_airband.native-recording.conf.example /usr/local/etc/rtl_airband.conf
sudo nano /usr/local/etc/rtl_airband.conf
```

Fill in your real Broadcastify/Icecast values locally.

## Expected Recording Location

The config writes native RTLSDR-Airband MP3 files under:

```text
/home/pi/Recordings
```

With `dated_subdirectories = true`, RTLSDR-Airband creates:

```text
/home/pi/Recordings/YYYY/MM/DD
```

This is close to the previous recorder root, but not an exact match for the old SOX directory format:

```text
/home/pi/Recordings/YYYY/MM-Mon/DD-Day
```

## Expected File Names

The old SOX recorder wrote names like:

```text
2026-05-30_14-22-10_160.545.mp3
```

RTLSDR-Airband's native file output appends its own timestamp to `filename_template`. With this test config, the closest native form is expected to be similar to:

```text
_20260530_142210_160.545.mp3
_20260530_142315_161.265.mp3
```

The important pieces are preserved:

- local date and time
- channel frequency in the filename
- one MP3 per transmission
- same `/home/pi/Recordings` root

If we need the old directory and filename style exactly, the next step is a small post-processing script that renames/moves completed RTLSDR-Airband files after each recording closes.

## Behavior Difference To Watch

The old SOX recorder used a trailing silence duration of about 13 seconds before closing a recording. RTLSDR-Airband's native `split_on_transmission` behavior closes files much sooner after the channel goes idle.

That means this branch may produce more, shorter files when a radio exchange has short pauses between transmissions. That may be better if we want one file per key-up, but worse if we want one file per conversation.

## Test Procedure

Stop the SOX recorder services so recordings are not duplicated:

```bash
sudo systemctl stop vox.service vox2.service
sudo systemctl disable vox.service vox2.service
```

Restart RTLSDR-Airband with the native-recording config:

```bash
sudo systemctl restart rtl_airband.service
```

Watch logs and recordings:

```bash
journalctl -u rtl_airband.service -f
find /home/pi/Recordings -type f -name '*.mp3' -printf '%TY-%Tm-%Td %TH:%TM %p\n'
```

After confirming recordings, check that the Broadcastify stream is still connected and sounding right.
