#!/usr/bin/env python3
"""Check network health and optionally try conservative Wi-Fi recovery."""

from __future__ import annotations

import argparse
import json
import os
import platform
import pwd
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen


CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/etc/train-recorder"))
STATE_DIR = Path(os.environ.get("STATE_DIR", "/var/lib/train-recorder"))
STATE_FILE = Path(os.environ.get("WIFI_CHECK_STATE", str(STATE_DIR / "wifi-check.json")))
RUN_USER = os.environ.get("RUN_USER", "pi")
DASHBOARD_PORT = int(os.environ.get("DASHBOARD_PORT", "8080"))
DNS_TEST_HOST = os.environ.get("WIFI_CHECK_DNS_HOST", "rclone.org")


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def runtime_env() -> dict[str, str]:
    env: dict[str, str] = {}
    env.update(read_env_file(CONFIG_DIR / "common.env"))
    env.update(read_env_file(CONFIG_DIR / "sync.env"))
    return env


def run_cmd(command: list[str], timeout: int = 10) -> dict[str, Any]:
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "command": command,
        }
    except FileNotFoundError:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command not found", "command": command}
    except subprocess.TimeoutExpired:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command timed out", "command": command}


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


def bool_env(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def ip_addresses() -> list[str]:
    result = run_cmd(["hostname", "-I"])
    if result["ok"] and result["stdout"]:
        return [item for item in result["stdout"].split() if item]
    return []


def default_gateway() -> str:
    result = run_cmd(["ip", "route", "show", "default"])
    if not result["stdout"]:
        return ""
    parts = result["stdout"].split()
    if "via" in parts:
        idx = parts.index("via")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return ""


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


def check_result(name: str, ok: bool, message: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"name": name, "ok": ok, "message": message, "details": details or {}}


def check_gateway(gateway: str) -> dict[str, Any]:
    if not gateway:
        return check_result("gateway", False, "no default gateway")
    result = run_cmd(["ping", "-c", "1", "-W", "3", gateway], timeout=6)
    return check_result("gateway", result["ok"], f"default gateway {gateway}", {"gateway": gateway})


def check_dns() -> dict[str, Any]:
    result = run_cmd(["getent", "hosts", DNS_TEST_HOST])
    return check_result("dns", result["ok"], f"resolve {DNS_TEST_HOST}", {"host": DNS_TEST_HOST})


def current_user() -> str:
    try:
        return pwd.getpwuid(os.geteuid()).pw_name
    except KeyError:
        return os.environ.get("USER", "")


def check_rclone(env: dict[str, str]) -> dict[str, Any]:
    remote = env.get("RCLONE_REMOTE", "")
    if not remote:
        return check_result("rclone", True, "rclone remote not configured", {"configured": False})
    if not command_exists("rclone"):
        return check_result("rclone", False, "rclone is not installed", {"configured": True, "remote": remote})

    if current_user() == RUN_USER:
        command = ["rclone", "lsd", remote]
    else:
        command = ["sudo", "-n", "-u", RUN_USER, "rclone", "lsd", remote]
    result = run_cmd(command, timeout=20)
    return check_result(
        "rclone",
        result["ok"],
        "rclone remote reachable" if result["ok"] else "rclone remote not reachable",
        {"configured": True, "remote": remote, "stderr": result["stderr"]},
    )


def check_dashboard() -> dict[str, Any]:
    if not service_is_active("train-recorder-dashboard.service"):
        return check_result("dashboard", True, "dashboard service is not active", {"configured": False})
    try:
        with urlopen(f"http://127.0.0.1:{DASHBOARD_PORT}/api/status", timeout=8) as response:
            ok = response.status == 200
            return check_result("dashboard", ok, f"dashboard HTTP {response.status}", {"configured": True, "port": DASHBOARD_PORT})
    except URLError as exc:
        return check_result("dashboard", False, "dashboard not reachable", {"configured": True, "port": DASHBOARD_PORT, "error": str(exc)})
    except TimeoutError:
        return check_result("dashboard", False, "dashboard check timed out", {"configured": True, "port": DASHBOARD_PORT})


def service_is_active(name: str) -> bool:
    return run_cmd(["systemctl", "is-active", name])["stdout"] == "active"


def remedy_actions() -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []

    wpa_cli = command_path("wpa_cli")
    if wpa_cli:
        result = run_cmd([wpa_cli, "reconnect"], timeout=15)
        actions.append({"action": "wpa_cli reconnect", "ok": result["ok"], "output": result["stdout"] or result["stderr"]})

    nmcli = command_path("nmcli")
    if nmcli and service_is_active("NetworkManager.service"):
        result = run_cmd([nmcli, "networking", "connectivity", "check"], timeout=20)
        actions.append({"action": "nmcli connectivity check", "ok": result["ok"], "output": result["stdout"] or result["stderr"]})
        if not result["ok"]:
            retry = run_cmd([nmcli, "radio", "wifi", "on"], timeout=15)
            actions.append({"action": "nmcli radio wifi on", "ok": retry["ok"], "output": retry["stdout"] or retry["stderr"]})

    for service in ("dhcpcd.service", "wpa_supplicant.service"):
        if service_is_active(service):
            result = run_cmd(["systemctl", "restart", service], timeout=30)
            actions.append({"action": f"restart {service}", "ok": result["ok"], "output": result["stdout"] or result["stderr"]})
            break

    if not actions:
        actions.append({"action": "none", "ok": False, "output": "no supported Wi-Fi remedy tool or service found"})
    return actions


def collect(remedy: bool = False) -> dict[str, Any]:
    env = runtime_env()
    gateway = default_gateway()
    wifi = wifi_status()
    checks = [
        check_result("ip-address", bool(ip_addresses()), "at least one IP address assigned", {"ip_addresses": ip_addresses()}),
        check_gateway(gateway),
        check_dns(),
        check_rclone(env),
        check_dashboard(),
    ]
    failures = [item for item in checks if not item["ok"]]
    actions: list[dict[str, Any]] = []
    if remedy and failures:
        actions = remedy_actions()

    overall = "fail" if failures else "ok"
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "host": platform.node(),
        "overall": overall,
        "remedy_requested": remedy,
        "network": {
            "hostname": platform.node(),
            "ip_addresses": ip_addresses(),
            "default_gateway": gateway,
            "wifi_ssid": wifi["ssid"],
            "wifi_ssid_source": wifi["source"],
            "wifi_connected": wifi["connected"],
        },
        "summary": {"failures": len(failures), "checks": len(checks), "actions": len(actions)},
        "checks": checks,
        "actions": actions,
    }


def write_state(data: dict[str, Any]) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
        tmp.replace(STATE_FILE)
    except OSError as exc:
        data.setdefault("state_error", str(exc))


def main() -> int:
    parser = argparse.ArgumentParser(description="Check Train Recorder network/Wi-Fi health")
    parser.add_argument("--json", action="store_true", help="print JSON instead of a short text summary")
    parser.add_argument("--remedy", action="store_true", help="try conservative recovery actions if checks fail")
    parser.add_argument("--no-write-state", action="store_true", help="do not write the state file")
    args = parser.parse_args()

    remedy = args.remedy or bool_env("WIFI_CHECK_REMEDY", False)
    data = collect(remedy=remedy)
    if not args.no_write_state:
        write_state(data)

    if args.json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        print(f"network={data['overall']} failures={data['summary']['failures']} actions={data['summary']['actions']}")
        for check in data["checks"]:
            print(f"{'ok' if check['ok'] else 'fail'} {check['name']}: {check['message']}")
        for action in data["actions"]:
            print(f"action {'ok' if action['ok'] else 'fail'} {action['action']}: {action['output']}")

    return 1 if data["overall"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
