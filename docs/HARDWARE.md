# Hardware Notes

This project is intended for small Raspberry Pi recorder appliances using one RTL-SDR receiver. Exact RF performance depends heavily on local signal levels, antenna placement, feedline, and power quality, so keep site-specific hardware notes with each deployment.

## Tested Systems

### ONR Recorder Production Pi

Status: production soak tested.

Fill in or update these details from the installed site:

| Item | Details |
| --- | --- |
| Raspberry Pi model | Raspberry Pi 3 |
| Raspberry Pi OS | Raspberry Pi OS Bullseye minimal image |
| Storage | Samsung 32Gb EVO Plus SD Card |
| RTL-SDR model | Nooelec RTL-SDR v5 SDR - NESDR Smart |
| Antenna | HYS VHF/UHF 2M/70CM Antenna HYS-771N Mounted directly to RTL-SDR adapter using 90 deg adapter |
| Feedline/adapters | RP-SMA - BNC 90 deg Adapter |
| Power supply | Raspberry Pi Micro-USB Power Adapter |
| Cooling/enclosure | Raspberry Pi Aluminum Heatsink Case |
| Network | Built-in Wifi |
| Notes | Existing production recorder for 160.545 MHz and 161.265 MHz. |

### Fresh Install Validation Pi

Status: fresh install validated on Raspberry Pi OS Trixie and used for v1.3.0 production validation.

| Item | Details |
| --- | --- |
| Raspberry Pi model | Raspberry Pi 3 |
| Raspberry Pi OS | Raspberry Pi OS Trixie minimal image |
| Storage | Samsung 256Gb EVO Plus SD Card |
| RTL-SDR model | Nooelec RTL-SDR v5 SDR - NESDR Smart |
| Antenna | HYS VHF/UHF 2M/70CM Antenna HYS-771N Mounted directly to RTL-SDR adapter using 90 deg adapter |
| Feedline/adapters | RP-SMA - BNC 90 deg Adapter |
| Power supply | Raspberry Pi Micro-USB Power Adapter |
| Cooling/enclosure | Raspberry Pi Aluminum Heatsink Case |
| Network | Built-in Wifi |
| Notes | Installed from project docs, recorded transmissions, rclone-synced recordings, served the dashboard/history view, ran the Wi-Fi/network timer, and validated the `161.265` SNR squelch setting. |

## Recommended Hardware Information to Capture

For each deployment, record:

- Raspberry Pi model and RAM size.
- Raspberry Pi OS version and whether it is minimal/headless.
- SD card or storage model, size, and endurance rating if known.
- RTL-SDR dongle model, serial/index if more than one SDR is attached, and frequency correction value if measured.
- Antenna model/type, mounting location, approximate height, and whether it is indoors or outdoors.
- Feedline type/length and any adapters, filters, splitters, or LNAs.
- Power supply rating and whether it is official Raspberry Pi power or another known-good supply.
- Cooling, enclosure, and expected ambient temperature.
- Network connection type and any static IP or hostname convention.
- Broadcastify/Icecast feed channel and local recording channels, without documenting secrets.

## Practical Notes

- One RTL-SDR can receive multiple nearby railway NFM channels when they fit inside the usable tuner bandwidth configured in `site.yaml`.
- Strong local signals can still clip after demodulation or SOX gain. Use per-channel `SOX_VOLUME` overrides to tune recording loudness.
- Quiet channels can false-open auto squelch during noise or interference events. Keep proven RTLSDR-Airband squelch values, such as `squelch_snr_threshold`, in `site.yaml` so generated config preserves them.
- Poor power supplies and overheating can cause USB, SDR, or filesystem instability. Prefer a known-good power supply and basic cooling for unattended installs.
- Antenna placement is often more important than SDR gain. Raise and clear the antenna before compensating with high gain.
- Keep live Broadcastify credentials, rclone tokens, and exact private deployment details out of the public repository.
