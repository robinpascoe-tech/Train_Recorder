#!/usr/bin/env python3
"""Summarize recent MP3 recording samples for tuning and troubleshooting."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/etc/train-recorder"))
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
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def runtime_env() -> dict[str, str]:
    env = {"OUTPUT_ROOT": "/home/pi/Recordings", "VOX_CHANNELS": "freq160545,freq161265"}
    env.update(read_env_file(CONFIG_DIR / "common.env"))
    return env


def channels_list(env: dict[str, str]) -> list[str]:
    return [item.strip() for item in env.get("VOX_CHANNELS", "").replace(",", " ").split() if item.strip()]


def run_cmd(command: list[str], timeout: int = 15) -> dict[str, Any]:
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
        return {"ok": result.returncode == 0, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
    except FileNotFoundError:
        return {"ok": False, "stdout": "", "stderr": "command not found"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "command timed out"}


def legacy_journal_units(channel: str, service: str) -> list[str]:
    if channel == "freq160545":
        return [service, "vox.service"]
    if channel == "freq161265":
        return [service, "vox2.service"]
    return [service]


def recent_save_events(channel: str, suffix: str, journal_hours: float) -> list[dict[str, Any]]:
    service = f"vox@{channel}.service"
    events: list[dict[str, Any]] = []
    seen: set[tuple[str, int]] = set()
    for unit in legacy_journal_units(channel, service):
        result = run_cmd(["journalctl", "-u", unit, "--since", f"{journal_hours} hours ago", "--no-pager", "-o", "short-iso"], timeout=20)
        if not result["ok"] and "No journal files" not in result["stderr"]:
            continue
        for line in result["stdout"].splitlines():
            match = SAVE_RE.search(line)
            if not match or suffix not in Path(match.group(1)).stem:
                continue
            key = (match.group(1), int(match.group(2)))
            if key in seen:
                continue
            seen.add(key)
            events.append(
                {
                    "time": line.split(maxsplit=1)[0],
                    "path": match.group(1),
                    "name": Path(match.group(1)).name,
                    "bytes": int(match.group(2)),
                    "unit": unit,
                }
            )
    return sorted(events, key=lambda item: item.get("time", ""))


def parse_sox_stat(stderr: str) -> dict[str, float]:
    fields = {
        "maximum_amplitude": r"Maximum amplitude:\s+([-0-9.]+)",
        "minimum_amplitude": r"Minimum amplitude:\s+([-0-9.]+)",
        "rms_amplitude": r"RMS\s+amplitude:\s+([-0-9.]+)",
        "rough_frequency": r"Rough\s+frequency:\s+([-0-9.]+)",
        "volume_adjustment": r"Volume adjustment:\s+([-0-9.]+)",
    }
    parsed: dict[str, float] = {}
    for key, pattern in fields.items():
        match = re.search(pattern, stderr)
        if match:
            parsed[key] = float(match.group(1))
    return parsed


def mp3_files(root: Path, suffix: str, lookback_hours: float) -> list[Path]:
    if not root.exists():
        return []
    cutoff = time.time() - (lookback_hours * 3600)
    files = [path for path in root.rglob("*.mp3") if suffix in path.stem and path.stat().st_mtime >= cutoff]
    return sorted(files, key=lambda path: path.stat().st_mtime, reverse=True)


def analyze_file(path: Path) -> dict[str, Any]:
    stat = path.stat()
    soxi = run_cmd(["soxi", "-D", str(path)])
    sox = run_cmd(["sox", str(path), "-n", "stat"])
    duration = float(soxi["stdout"]) if soxi["ok"] and soxi["stdout"] else None
    sample: dict[str, Any] = {
        "path": str(path),
        "name": path.name,
        "bytes": stat.st_size,
        "modified_epoch": int(stat.st_mtime),
        "duration_seconds": duration,
        "sox_stat_ok": sox["ok"],
        "sox_stat": parse_sox_stat(sox["stderr"]),
    }
    if not sox["ok"]:
        sample["sox_error"] = sox["stderr"]
    return sample


def summarize_samples(samples: list[dict[str, Any]]) -> dict[str, Any]:
    durations = [float(item["duration_seconds"]) for item in samples if item.get("duration_seconds") is not None]
    sizes = [int(item["bytes"]) for item in samples]
    rms = [item["sox_stat"]["rms_amplitude"] for item in samples if "rms_amplitude" in item.get("sox_stat", {})]
    peaks = [abs(item["sox_stat"]["maximum_amplitude"]) for item in samples if "maximum_amplitude" in item.get("sox_stat", {})]
    return {
        "sampled_files": len(samples),
        "total_bytes": sum(sizes),
        "total_duration_seconds": round(sum(durations), 3),
        "average_duration_seconds": round(sum(durations) / len(durations), 3) if durations else None,
        "max_duration_seconds": round(max(durations), 3) if durations else None,
        "average_rms_amplitude": round(sum(rms) / len(rms), 6) if rms else None,
        "max_peak_amplitude": round(max(peaks), 6) if peaks else None,
    }


def summarize_events(events: list[dict[str, Any]]) -> dict[str, Any]:
    sizes = [int(item["bytes"]) for item in events]
    latest = events[-1] if events else None
    return {
        "count": len(events),
        "total_bytes": sum(sizes),
        "average_bytes": round(sum(sizes) / len(sizes), 1) if sizes else None,
        "max_bytes": max(sizes) if sizes else None,
        "latest_name": latest["name"] if latest else None,
    }


def collect(lookback_hours: float, max_files: int, journal_hours: float) -> dict[str, Any]:
    env = runtime_env()
    root = Path(env.get("OUTPUT_ROOT", "/home/pi/Recordings"))
    payload: dict[str, Any] = {
        "generated_at_epoch": int(time.time()),
        "output_root": str(root),
        "lookback_hours": lookback_hours,
        "journal_hours": journal_hours,
        "max_files_per_channel": max_files,
        "channels": [],
    }
    for channel in channels_list(env):
        channel_env = read_env_file(CONFIG_DIR / f"{channel}.env")
        suffix = channel_env.get("OUTPUT_SUFFIX", f"_{channel}")
        files = mp3_files(root, suffix, lookback_hours)
        samples = [analyze_file(path) for path in files[:max_files]]
        save_events = recent_save_events(channel, suffix, journal_hours)
        payload["channels"].append(
            {
                "name": channel,
                "frequency_mhz": channel_env.get("FREQUENCY_MHZ", ""),
                "output_suffix": suffix,
                "matching_files": len(files),
                "summary": summarize_samples(samples),
                "recent_saves": summarize_events(save_events),
                "samples": samples,
            }
        )
    return payload


def print_text(payload: dict[str, Any]) -> None:
    print("Train Recorder Recording Diagnostics")
    print(f"Output root: {payload['output_root']}")
    print(f"Lookback:    {payload['lookback_hours']} hours")
    print(f"Journal:     {payload['journal_hours']} hours")
    print()
    for channel in payload["channels"]:
        label = channel["frequency_mhz"] or channel["name"]
        summary = channel["summary"]
        latest = channel["samples"][0]["name"] if channel["samples"] else "none"
        recent = channel["recent_saves"]
        print(f"{label} ({channel['name']})")
        print(f"  matching files: {channel['matching_files']}")
        print(f"  sampled files:  {summary['sampled_files']}")
        print(f"  recent saves:   {recent['count']}")
        print(f"  recent bytes:   {recent['total_bytes']}")
        print(f"  total duration: {summary['total_duration_seconds']}s")
        print(f"  avg duration:   {summary['average_duration_seconds']}")
        print(f"  avg RMS amp:    {summary['average_rms_amplitude']}")
        print(f"  max peak amp:   {summary['max_peak_amplitude']}")
        print(f"  latest sample:  {latest}")
        print(f"  latest save:    {recent['latest_name'] or 'none'}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize recent Train Recorder MP3 samples")
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument("--lookback-hours", type=float, default=float(os.environ.get("RECORDING_DIAGNOSTICS_LOOKBACK_HOURS", "24")))
    parser.add_argument("--journal-hours", type=float, default=float(os.environ.get("RECORDING_DIAGNOSTICS_JOURNAL_HOURS", "24")))
    parser.add_argument("--max-files", type=int, default=int(os.environ.get("RECORDING_DIAGNOSTICS_MAX_FILES", "20")))
    args = parser.parse_args()

    payload = collect(args.lookback_hours, args.max_files, args.journal_hours)
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print_text(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
