#!/usr/bin/env python3
"""Emit read-only Train Recorder status as JSON."""

from __future__ import annotations

import json
import os
import platform
import pwd
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/etc/train-recorder"))
RUN_USER = os.environ.get("RUN_USER", "pi")
PULSE_SERVER = os.environ.get("PULSE_SERVER", "unix:/run/pulse/native")
WIFI_CHECK_STATE = Path(os.environ.get("WIFI_CHECK_STATE", "/var/lib/train-recorder/wifi-check.json"))
SAVE_RE = re.compile(r"Saved\s+(\S+)\s+\((\d+)\s+bytes\)")


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            values[key] = value
    return values


def runtime_env() -> dict[str, str]:
    env = {
        "OUTPUT_ROOT": "/home/pi/Recordings",
        "TEMP_DIR": "/mnt/ramdisk",
        "VOX_CHANNELS": "freq160545,freq161265",
        "PULSE_SERVER": PULSE_SERVER,
        "CHECK_RECENT_SYNC_SUCCESS": "true",
        "MAX_SYNC_SUCCESS_AGE_MINUTES": "30",
        "CLIPPING_WINDOW_MINUTES": "1440",
        "CLIPPING_WARN_COUNT": "50",
        "CLIPPING_WARN_MAX_SAMPLES": "1000000",
        "JOURNAL_WINDOW_MINUTES": "10080",
    }
    env.update(read_env_file(CONFIG_DIR / "common.env"))
    env.update(read_env_file(CONFIG_DIR / "sync.env"))
    return env


def run_cmd(command: list[str], timeout: int = 8, env: dict[str, str] | None = None) -> dict[str, Any]:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
        }
    except FileNotFoundError:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command not found"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command timed out"}


def bool_env(value: str | None) -> bool:
    return str(value or "").lower() in {"1", "true", "yes", "on"}


def int_env(env: dict[str, str], name: str, default: int) -> int:
    try:
        return int(env.get(name, str(default)))
    except (TypeError, ValueError):
        return default


def channels_list(env: dict[str, str]) -> list[str]:
    return [item.strip() for item in env.get("VOX_CHANNELS", "").replace(",", " ").split() if item.strip()]


def service_status(name: str) -> dict[str, Any]:
    active = run_cmd(["systemctl", "is-active", name])
    enabled = run_cmd(["systemctl", "is-enabled", name])
    return {
        "name": name,
        "active": active["stdout"] or "unknown",
        "enabled": enabled["stdout"] or "unknown",
        "ok": active["stdout"] == "active",
    }


def command_exists(name: str) -> bool:
    return command_path(name) is not None


def command_path(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    for directory in ("/usr/sbin", "/sbin", "/usr/bin", "/bin"):
        candidate = Path(directory) / name
        if candidate.exists():
            return str(candidate)
    return None


def python_module_available(name: str) -> bool:
    result = run_cmd(["python3", "-c", f"import {name}"], timeout=5)
    return bool(result["ok"])


def ip_addresses() -> list[str]:
    result = run_cmd(["hostname", "-I"])
    if result["ok"] and result["stdout"]:
        return [item for item in result["stdout"].split() if item]
    return []


def uptime_seconds() -> int | None:
    try:
        raw = Path("/proc/uptime").read_text().split()[0]
        return int(float(raw))
    except (IndexError, OSError, ValueError):
        return None


def wifi_status() -> dict[str, Any]:
    iwgetid = command_path("iwgetid")
    if iwgetid:
        result = run_cmd([iwgetid, "-r"])
        if result["ok"] and result["stdout"]:
            return {"ssid": result["stdout"].splitlines()[0].strip(), "source": "iwgetid", "connected": True}

    iw = command_path("iw")
    if iw:
        result = run_cmd([iw, "dev"])
        if result["stdout"]:
            for line in result["stdout"].splitlines():
                line = line.strip()
                if line.startswith("ssid "):
                    return {"ssid": line.removeprefix("ssid ").strip(), "source": "iw", "connected": True}

    nmcli = command_path("nmcli")
    if nmcli:
        result = run_cmd([nmcli, "-t", "-f", "active,ssid", "dev", "wifi"])
        if result["stdout"]:
            for line in result["stdout"].splitlines():
                active, _, ssid = line.partition(":")
                if active == "yes" and ssid:
                    return {"ssid": ssid, "source": "nmcli", "connected": True}

    wpa_cli = command_path("wpa_cli")
    if wpa_cli:
        result = run_cmd([wpa_cli, "status"])
        if result["stdout"]:
            fields = dict(line.split("=", 1) for line in result["stdout"].splitlines() if "=" in line)
            ssid = fields.get("ssid", "")
            state = fields.get("wpa_state", "")
            if ssid:
                return {"ssid": ssid, "source": "wpa_cli", "connected": state == "COMPLETED"}

    return {"ssid": "", "source": "", "connected": False}


def pulse_sources(pulse_server: str) -> list[str]:
    env = os.environ.copy()
    env["PULSE_SERVER"] = pulse_server
    result = run_cmd(["pactl", "list", "short", "sources"], env=env)
    sources: list[str] = []
    if result["ok"]:
        for line in result["stdout"].splitlines():
            parts = line.split()
            if len(parts) >= 2:
                sources.append(parts[1])
    return sources


def disk_usage(path: str) -> dict[str, Any]:
    item: dict[str, Any] = {"path": path, "exists": Path(path).exists(), "ok": False}
    try:
        usage = shutil.disk_usage(path)
    except OSError as exc:
        item["error"] = str(exc)
        return item

    used = usage.total - usage.free
    used_pct = round((used / usage.total) * 100, 1) if usage.total else 0
    item.update(
        {
            "ok": used_pct < 95,
            "total_bytes": usage.total,
            "used_bytes": used,
            "free_bytes": usage.free,
            "used_percent": used_pct,
        }
    )
    return item


def pending_recordings(output_root: str) -> dict[str, Any]:
    count = 0
    total = 0
    root = Path(output_root)
    if not root.exists():
        return {"path": output_root, "count": 0, "total_bytes": 0, "exists": False}
    for file_path in root.rglob("*.mp3"):
        try:
            count += 1
            total += file_path.stat().st_size
        except OSError:
            continue
    return {"path": output_root, "count": count, "total_bytes": total, "exists": True}


def journal_lines(units: list[str], minutes: int, output: str = "short-unix") -> list[str]:
    lines: list[str] = []
    for unit in units:
        result = run_cmd(
            ["journalctl", "-u", unit, "--since", f"{minutes} minutes ago", "--no-pager", "-o", output],
            timeout=12,
        )
        if result["stdout"]:
            lines.extend(result["stdout"].splitlines())
    return lines


def parse_short_unix(line: str) -> tuple[float | None, str]:
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s+.*?:\s*(.*)$", line)
    if match:
        return float(match.group(1)), match.group(2)
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s+(.*)$", line)
    if match:
        return float(match.group(1)), match.group(2)
    return None, line


def last_journal_event(units: list[str], minutes: int, pattern: str) -> dict[str, Any] | None:
    regex = re.compile(pattern)
    matches: list[tuple[float, str]] = []
    for line in journal_lines(units, minutes):
        if regex.search(line):
            epoch, message = parse_short_unix(line)
            if epoch is not None:
                matches.append((epoch, message))
    if not matches:
        return None
    epoch, message = sorted(matches, key=lambda item: item[0])[-1]
    return {
        "epoch": epoch,
        "iso": datetime.fromtimestamp(epoch, timezone.utc).isoformat(),
        "age_seconds": max(0, int(time.time() - epoch)),
        "message": message,
    }


def recent_recordings(units: list[str], minutes: int, output_suffix: str) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for line in journal_lines(units, minutes):
        epoch, message = parse_short_unix(line)
        if epoch is None:
            continue
        match = SAVE_RE.search(message)
        if not match:
            continue
        file_path = match.group(1)
        if output_suffix and output_suffix not in Path(file_path).stem:
            continue
        key = (str(epoch), file_path)
        if key in seen:
            continue
        seen.add(key)
        events.append(
            {
                "epoch": epoch,
                "iso": datetime.fromtimestamp(epoch, timezone.utc).isoformat(),
                "age_seconds": max(0, int(time.time() - epoch)),
                "path": file_path,
                "name": Path(file_path).name,
                "bytes": int(match.group(2)),
            }
        )
    events.sort(key=lambda item: item["epoch"])
    latest = events[-1] if events else None
    return {
        "count": len(events),
        "total_bytes": sum(int(item["bytes"]) for item in events),
        "latest": latest,
        "window_minutes": minutes,
    }


def clipping_is_ok(summary: dict[str, Any], warn_count: int, warn_max_samples: int) -> bool:
    count_ok = warn_count <= 0 or int(summary.get("count", 0)) < warn_count
    samples_ok = warn_max_samples <= 0 or int(summary.get("max_samples", 0)) < warn_max_samples
    return count_ok and samples_ok


def clipping_summary(units: list[str], minutes: int, warn_count: int = 50, warn_max_samples: int = 1000000) -> dict[str, Any]:
    count = 0
    max_samples = 0
    for line in journal_lines(units, minutes, output="short"):
        if "balancing clipped" not in line:
            continue
        count += 1
        match = re.search(r"balancing clipped ([0-9]+) samples", line)
        if match:
            max_samples = max(max_samples, int(match.group(1)))
    summary = {
        "count": count,
        "max_samples": max_samples,
        "window_minutes": minutes,
        "warn_count": warn_count,
        "warn_max_samples": warn_max_samples,
    }
    summary["ok"] = clipping_is_ok(summary, warn_count, warn_max_samples)
    return summary


def user_groups(user: str) -> list[str]:
    result = run_cmd(["id", "-nG", user])
    if result["ok"]:
        return result["stdout"].split()
    return []


def rclone_status(env: dict[str, str]) -> dict[str, Any]:
    remote = env.get("RCLONE_REMOTE", "")
    status: dict[str, Any] = {"remote": remote, "configured": bool(remote), "reachable": None}
    if not remote:
        return status
    if not command_exists("rclone"):
        status.update({"reachable": False, "error": "rclone not installed"})
        return status

    try:
        current_user = pwd.getpwuid(os.geteuid()).pw_name
    except KeyError:
        current_user = os.environ.get("USER", "")

    if current_user == RUN_USER:
        command = ["rclone", "lsd", remote]
    else:
        command = ["sudo", "-n", "-u", RUN_USER, "rclone", "lsd", remote]
    result = run_cmd(command, timeout=15)
    status.update({"reachable": result["ok"]})
    if not result["ok"]:
        status["error"] = result["stderr"] or result["stdout"]
    return status


def wifi_check_state() -> dict[str, Any]:
    if not WIFI_CHECK_STATE.exists():
        return {"available": False, "path": str(WIFI_CHECK_STATE)}
    try:
        data = json.loads(WIFI_CHECK_STATE.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return {"available": False, "path": str(WIFI_CHECK_STATE), "error": str(exc)}
    data["available"] = True
    data["path"] = str(WIFI_CHECK_STATE)
    last_failure = data.get("last_failure")
    if isinstance(last_failure, dict):
        generated = last_failure.get("generated_at")
        try:
            parsed = datetime.fromisoformat(str(generated).replace("Z", "+00:00"))
            last_failure["age_seconds"] = max(0, int((datetime.now(timezone.utc) - parsed).total_seconds()))
        except (TypeError, ValueError):
            pass
    return data


def add_check(checks: list[dict[str, Any]], name: str, level: str, ok: bool, message: str) -> None:
    checks.append({"name": name, "level": level if not ok else "ok", "ok": ok, "message": message})


def collect_status() -> dict[str, Any]:
    env = runtime_env()
    channels = channels_list(env)
    pulse_server = env.get("PULSE_SERVER", PULSE_SERVER)
    source_names = pulse_sources(pulse_server)
    journal_window = int(env.get("JOURNAL_WINDOW_MINUTES", "10080"))
    clipping_window = int_env(env, "CLIPPING_WINDOW_MINUTES", 1440)
    clipping_warn_count = int_env(env, "CLIPPING_WARN_COUNT", 50)
    clipping_warn_max_samples = int_env(env, "CLIPPING_WARN_MAX_SAMPLES", 1000000)
    sync_window = int_env(env, "MAX_SYNC_SUCCESS_AGE_MINUTES", 30)

    core_services = [service_status(name) for name in ["pulseaudio.service", "rtl_airband.service"]]
    timer_requirements = {
        "train-recorder-sync.timer": bool(env.get("RCLONE_REMOTE", "")),
        "train-recorder-health.timer": True,
        "train-recorder-cleanup.timer": True,
    }
    timers = [service_status(name) for name in timer_requirements]

    channel_statuses: list[dict[str, Any]] = []
    all_journal_units = ["rtl_airband.service", "train-recorder-sync.service", "train-recorder-cleanup.service"]
    for channel in channels:
        channel_env = read_env_file(CONFIG_DIR / f"{channel}.env")
        service = f"vox@{channel}.service"
        monitor = channel_env.get("PULSE_MONITOR", "")
        output_suffix = channel_env.get("OUTPUT_SUFFIX", f"_{channel}")
        journal_units = channel_env.get("JOURNAL_UNITS", service).split()
        last_save = last_journal_event(journal_units, journal_window, rf"Saved .*{re.escape(output_suffix)}\.mp3")
        channel_item = {
            "name": channel,
            "env_file": str(CONFIG_DIR / f"{channel}.env"),
            "frequency_mhz": channel_env.get("FREQUENCY_MHZ", ""),
            "service": service_status(service),
            "pulse_monitor": monitor,
            "pulse_source_exists": monitor in source_names if monitor else False,
            "output_suffix": output_suffix,
            "last_save": last_save,
            "recent_recordings": recent_recordings(journal_units, journal_window, output_suffix),
            "clipping": clipping_summary(journal_units, clipping_window, clipping_warn_count, clipping_warn_max_samples),
        }
        channel_statuses.append(channel_item)
        all_journal_units.extend(journal_units)

    sync_last = last_journal_event(["train-recorder-sync.service"], journal_window, r"Finished train-recorder-sync\.service")
    cleanup_last = last_journal_event(["train-recorder-cleanup.service"], journal_window, r"Finished train-recorder-cleanup\.service")
    health_last = last_journal_event(["train-recorder-health.service"], journal_window, r"Finished train-recorder-health\.service")

    checks: list[dict[str, Any]] = []
    for item in core_services:
        add_check(checks, item["name"], "fail", bool(item["ok"]), f"{item['name']} active={item['active']}")
    for item in timers:
        required = timer_requirements.get(item["name"], True)
        add_check(
            checks,
            item["name"],
            "fail" if required else "warn",
            bool(item["ok"]),
            f"{item['name']} active={item['active']}",
        )
    for channel in channel_statuses:
        add_check(checks, channel["service"]["name"], "fail", bool(channel["service"]["ok"]), f"{channel['service']['name']} active={channel['service']['active']}")
        add_check(
            checks,
            f"{channel['name']} pulse source",
            "fail",
            bool(channel["pulse_source_exists"]),
            f"{channel['pulse_monitor'] or 'missing PULSE_MONITOR'}",
        )

    output_root = env.get("OUTPUT_ROOT", "/home/pi/Recordings")
    temp_dir = env.get("TEMP_DIR", "/mnt/ramdisk")
    disks = [disk_usage(output_root), disk_usage(temp_dir)]
    if Path("/var/log").exists():
        disks.append(disk_usage("/var/log"))
    for disk in disks:
        used = disk.get("used_percent")
        if used is not None:
            add_check(checks, f"disk {disk['path']}", "fail", used < 95, f"{used}% used")

    groups = {"run_user": user_groups(RUN_USER), "root": user_groups("root")}
    add_check(checks, f"{RUN_USER} pulse-access", "fail", "pulse-access" in groups["run_user"], f"{RUN_USER} groups")
    add_check(checks, "root pulse-access", "fail", "pulse-access" in groups["root"], "root groups")
    add_check(checks, f"{RUN_USER} pulse", "warn", "pulse" in groups["run_user"], f"{RUN_USER} is not in pulse")
    add_check(checks, "root pulse", "warn", "pulse" in groups["root"], "root is not in pulse")

    if bool_env(env.get("CHECK_RECENT_SYNC_SUCCESS", "true")):
        add_check(
            checks,
            "recent sync",
            "fail",
            bool(sync_last and sync_last["age_seconds"] <= sync_window * 60),
            f"last sync within {sync_window} minutes",
        )

    rclone = rclone_status(env)
    if rclone["configured"]:
        add_check(checks, "rclone remote", "fail", bool(rclone["reachable"]), rclone.get("error", "reachable"))

    wifi_check = wifi_check_state()
    if wifi_check.get("available"):
        add_check(
            checks,
            "Wi-Fi/network check",
            "warn",
            wifi_check.get("overall") == "ok",
            f"latest network check {wifi_check.get('overall', 'unknown')}",
        )

    clipping = clipping_summary(sorted(set(all_journal_units)), clipping_window, clipping_warn_count, clipping_warn_max_samples)
    add_check(
        checks,
        "SOX clipping",
        "warn",
        bool(clipping["ok"]),
        (f"{clipping['count']} warnings, max {clipping['max_samples']} samples (warn at {clipping_warn_count}+ warnings or {clipping_warn_max_samples}+ samples)"),
    )

    failures = [item for item in checks if not item["ok"] and item["level"] == "fail"]
    warnings = [item for item in checks if not item["ok"] and item["level"] == "warn"]
    overall = "fail" if failures else "warn" if warnings else "ok"

    wifi = wifi_status()
    dashboard_service = service_status("train-recorder-dashboard.service")

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "host": platform.node(),
        "network": {
            "hostname": platform.node(),
            "ip_addresses": ip_addresses(),
            "wifi_ssid": wifi["ssid"],
            "wifi_ssid_source": wifi["source"],
            "wifi_connected": wifi["connected"],
            "latest_check": wifi_check,
        },
        "overall": overall,
        "summary": {"failures": len(failures), "warnings": len(warnings), "checks": len(checks)},
        "runtime": {
            "uptime_seconds": uptime_seconds(),
            "dashboard": {
                "service": dashboard_service,
                "flask_available": python_module_available("flask"),
                "api_path": "/api/status",
            },
        },
        "config": {
            "config_dir": str(CONFIG_DIR),
            "output_root": output_root,
            "temp_dir": temp_dir,
            "pulse_server": pulse_server,
            "vox_channels": channels,
            "rclone_remote_configured": bool(env.get("RCLONE_REMOTE", "")),
        },
        "services": core_services,
        "timers": timers,
        "channels": channel_statuses,
        "pulse": {"server": pulse_server, "sources": source_names, "groups": groups},
        "events": {"sync": sync_last, "cleanup": cleanup_last, "health": health_last},
        "storage": {"filesystems": disks, "pending_recordings": pending_recordings(output_root)},
        "rclone": rclone,
        "clipping": clipping,
        "checks": checks,
    }


def main() -> int:
    status = collect_status()
    print(json.dumps(status, indent=2, sort_keys=True))
    return 1 if status["overall"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
