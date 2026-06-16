# Security Hardening

These notes are for recorder appliances on a trusted LAN. They are not a substitute for a firewall, VPN, or normal operating-system maintenance.

## Immediate Checklist

- Change the default `pi` password before leaving SSH enabled:

  ```bash
  passwd
  ```

- Keep the recorder behind a LAN firewall or router. Do not forward SSH, the dashboard, Icecast source ports, or PulseAudio ports from the internet.

- Use SSH keys for routine access. After confirming key login works from your admin machine, consider disabling password SSH login:

  ```bash
  sudo nano /etc/ssh/sshd_config.d/99-train-recorder-hardening.conf
  ```

  ```sshconfig
  PasswordAuthentication no
  PermitRootLogin no
  ```

  ```bash
  sudo systemctl reload ssh
  ```

- Keep `pi` as the service account for recorder, sync, and dashboard services. This matches PulseAudio access, generated MP3 ownership, and rclone token location.

- Confirm sensitive files are owned by root or `pi` and are not world-readable:

  ```bash
  sudo ls -l /etc/train-recorder/site.yaml /usr/local/etc/rtl_airband.conf
  sudo ls -l /home/pi/.config/rclone/rclone.conf
  ```

- Keep the dashboard LAN-only. The dashboard has no built-in authentication or TLS:

  ```text
  http://<pi-address>:8080/
  ```

  If remote access is needed, use a VPN or put authentication and TLS in front of it with a separate reverse proxy.

## Routine Checks

Run the normal read-only validation commands after hardening changes:

```bash
sudo /opt/train-recorder/Scripts/validate_deploy.sh
sudo /opt/train-recorder/Scripts/site_config.sh doctor
```

Check SSH and listening ports:

```bash
systemctl is-active ssh
ss -tulpn
```

Review recent authentication failures:

```bash
journalctl -u ssh --since today
```

## Updates

Apply Raspberry Pi OS security updates during a maintenance window:

```bash
sudo apt update
sudo apt upgrade
sudo reboot
```

After reboot:

```bash
sudo /opt/train-recorder/Scripts/validate_deploy.sh
```

Avoid unattended major OS upgrades on a remote recorder unless you have console access or a tested rollback path.

## Secrets

Do not copy these files into git, tickets, chat logs, or public diagnostics:

```text
/etc/train-recorder/site.yaml
/usr/local/etc/rtl_airband.conf
/home/pi/.config/rclone/rclone.conf
```

Use the diagnostics bundle for support snapshots because it redacts known sensitive fields:

```bash
sudo /opt/train-recorder/Scripts/collect_diagnostics.sh
```

Review the bundle before sharing it.
