# Hardware Watchdog Plan

This project should use the Raspberry Pi hardware watchdog as a last-resort host recovery tool, not as the first response to ordinary recorder service failures.

The preferred recovery order is:

1. Service-level restart for processes that can safely restart.
2. Timer-level retry for one-shot maintenance jobs.
3. Operator-visible warnings through doctor, dashboard, and deploy validation.
4. Hardware watchdog reboot only when the operating system or systemd stops making progress.

## Current Service Posture

- `vox@<channel>.service` already uses `Restart=on-failure` with a 30 second delay. This is appropriate because SOX recorder processes can restart without rewriting live config.
- `train-recorder-dashboard.service` already uses `Restart=on-failure` with a 10 second delay. This is appropriate because the dashboard is read-only.
- `train-recorder-sync.service`, `train-recorder-health.service`, `train-recorder-cleanup.service`, and `train-recorder-wifi-check.service` are one-shot services run by timers. Their next timer run is the retry path.
- `rtl_airband.service` currently uses `Restart=no` because startup failures are usually misconfiguration or SDR device failure. Changing this needs a separate soak test; blind restart loops could hide a broken SDR or bad config.
- `pulseaudio.service` has no explicit restart policy in the project unit. If PulseAudio exits, downstream health checks and recorder services should fail clearly.

## Current Production Status

Phase 1 host-watchdog enablement has been tested on the Trixie Pi with console and physical access available. The disruptive watchdog test confirmed that the Pi rebooted when watchdog keepalives stopped, and the recorder stack validated cleanly after reboot. Keep the rollback steps below handy before enabling the same policy on any additional remote recorder.

The current host-level override is:

```ini
[Manager]
RuntimeWatchdogSec=30s
RebootWatchdogSec=10min
```

## Phase 1: Documented Manual Enablement

Before enabling a watchdog on a remote recorder, confirm console or power-cycle access exists. A bad watchdog setup can create a reboot loop.

Check whether the watchdog device exists:

```bash
ls -l /dev/watchdog*
```

Enable systemd's runtime watchdog with a local override:

```bash
sudo mkdir -p /etc/systemd/system.conf.d
sudo nano /etc/systemd/system.conf.d/99-train-recorder-watchdog.conf
```

Suggested starting point:

```ini
[Manager]
RuntimeWatchdogSec=30s
RebootWatchdogSec=10min
```

Apply during a maintenance window:

```bash
sudo systemctl daemon-reexec
sudo systemctl show --property=RuntimeWatchdogUSec --property=RebootWatchdogUSec
```

Then validate the recorder stack:

```bash
sudo /opt/train-recorder/Scripts/validate_deploy.sh
```

## Phase 2: Soak-Test Host Watchdog Only

After enabling the host watchdog, continue soaking before adding any service-level watchdog settings:

- confirm the Pi does not reboot unexpectedly
- confirm dashboard, doctor, and deploy validation remain green
- confirm sync still drains local MP3s
- confirm logs do not show watchdog or systemd manager errors

Useful checks:

```bash
uptime
journalctl -b -p warning
journalctl --list-boots
sudo /opt/train-recorder/Scripts/validate_deploy.sh
```

## Phase 3: Optional Service Policy Review

Only after the host watchdog is stable, review service restart behavior:

- Consider `Restart=on-failure` for `pulseaudio.service` only if PulseAudio exits are observed and restarts recover cleanly.
- Revisit `rtl_airband.service` only with a deliberate SDR-failure test. If restart is enabled, use rate limiting such as `StartLimitIntervalSec` and `StartLimitBurst` so a missing SDR does not spin forever.
- Avoid `WatchdogSec=` on shell scripts and one-shot timer services. They do not send systemd watchdog notifications.
- Do not use the hardware watchdog to compensate for known bad config, bad SDR hardware, or failed network credentials.

## Rollback

Disable the systemd hardware watchdog override:

```bash
sudo rm -f /etc/systemd/system.conf.d/99-train-recorder-watchdog.conf
sudo systemctl daemon-reexec
sudo systemctl show --property=RuntimeWatchdogUSec --property=RebootWatchdogUSec
```

If service restart policies were changed, restore the affected unit from the previous `/etc/systemd/system/*.bak-*` backup or reinstall the project unit, then run:

```bash
sudo systemctl daemon-reload
sudo /opt/train-recorder/Scripts/validate_deploy.sh
```

## Open Decisions

- Whether `pulseaudio.service` should gain `Restart=on-failure`.
- Whether `rtl_airband.service` should remain `Restart=no` or use conservative restart rate limiting after SDR unplug/replug testing.
- Whether deploy validation should warn when the host watchdog is disabled after the plan has been adopted for a site.
