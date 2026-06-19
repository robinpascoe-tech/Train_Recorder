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
- `pulseaudio.service` now uses `Restart=on-failure` with `RestartSec=15s`, `StartLimitIntervalSec=10min`, and `StartLimitBurst=2`. This gives one automatic retry after a crash, then leaves the unit failed for operator review if the retry also fails.
- `rtl_airband.service` now uses `Restart=on-failure` with `RestartSec=30s`, `StartLimitIntervalSec=15min`, and `StartLimitBurst=4`. This gives a few retries for transient SDR or PulseAudio disruption, then stops retrying until an operator intervenes. The unit also uses `PartOf=pulseaudio.service` so an explicit PulseAudio restart restarts RTLSDR-Airband as well.

## Current Production Status

Phase 1 host-watchdog enablement has been tested on the Trixie Pi with console and physical access available. The disruptive watchdog test confirmed that the Pi rebooted when watchdog keepalives stopped, and the recorder stack validated cleanly after reboot. Keep the rollback steps below handy before enabling the same policy on any additional remote recorder.

On 2026-06-18, Phase 3 service restart smoke testing was performed on the same Pi after enabling the conservative restart policy:

- killing `pulseaudio.service` with `SIGKILL` triggered one delayed automatic restart after 15 seconds
- the PulseAudio restart also restarted `rtl_airband.service` cleanly via `PartOf=pulseaudio.service`
- killing `rtl_airband.service` with `SIGKILL` triggered one delayed automatic restart after 30 seconds
- `validate_deploy.sh` passed before and after the live test
- `validate_deploy.sh` should now warn if `RuntimeWatchdogSec` is disabled on a site that has adopted the host watchdog plan

The live test confirmed single-failure recovery. It did not intentionally exhaust `StartLimitBurst` on production hardware; repeated-failure soak testing should still be done cautiously during a maintenance window.

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

After enabling the host watchdog, continue soaking before adding any service-level `WatchdogSec=` notification policy:

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

## Phase 3: Service Policy Review

After host-watchdog soak testing stayed stable, the recorder moved to a conservative service restart policy:

- `pulseaudio.service` should attempt one restart after an unexpected exit. If the restart also fails inside the 10 minute start-limit window, systemd stops retrying. This keeps a bad `system.pa` or other startup failure visible instead of retrying forever.
- `rtl_airband.service` should attempt a few retries after unexpected exit so quick SDR unplug/replug or PulseAudio disruption can self-heal. If those retries fail inside the 15 minute start-limit window, systemd stops retrying and leaves the failure visible.
- Use `systemctl reset-failed pulseaudio.service rtl_airband.service` after fixing a bad config or replacing failed hardware so the rate limiter is cleared before retrying.
- Keep service watchdog notifications disabled for these units. They do not need `WatchdogSec=` to benefit from the host hardware watchdog or from conservative restart policies.
- Avoid `WatchdogSec=` on shell scripts and one-shot timer services. They do not send systemd watchdog notifications.
- Do not use the hardware watchdog to compensate for known bad config, bad SDR hardware, or failed network credentials.

Useful live checks for the restart policy:

```bash
systemctl show pulseaudio.service -p ActiveState -p NRestarts -p Restart -p RestartUSec -p StartLimitIntervalUSec -p StartLimitBurst
systemctl show rtl_airband.service -p ActiveState -p NRestarts -p Restart -p RestartUSec -p StartLimitIntervalUSec -p StartLimitBurst
journalctl -u pulseaudio.service -u rtl_airband.service --since today
```

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

## Remaining Follow-Up

- Continue real-Pi soak testing around deliberate SDR unplug/replug and PulseAudio crash simulation, and record whether the current retry windows are too short or too generous.
