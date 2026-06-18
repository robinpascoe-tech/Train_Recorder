#!/usr/bin/env python3
"""Maintain a small rolling status history for the dashboard."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import status_json


STATE_DIR = Path(os.environ.get("TRAIN_RECORDER_STATE_DIR", "/var/lib/train-recorder"))
HISTORY_FILE = Path(os.environ.get("STATUS_HISTORY_FILE", str(STATE_DIR / "status-history.json")))
DEFAULT_RETENTION_HOURS = int(os.environ.get("STATUS_HISTORY_RETENTION_HOURS", "24"))


def parse_time(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def compact_snapshot(status: dict[str, Any]) -> dict[str, Any]:
    latest_network = status.get("network", {}).get("latest_check", {})
    checks = [item for item in status.get("checks", []) if isinstance(item, dict)]
    operational_issues = [
        item
        for item in checks
        if not item.get("ok") and item.get("name") != "SOX clipping"
    ]
    operational_failures = sum(1 for item in operational_issues if item.get("level") == "fail")
    operational_warnings = sum(1 for item in operational_issues if item.get("level") == "warn")
    operational_overall = "fail" if operational_failures else "warn" if operational_warnings else "ok"
    return {
        "generated_at": status.get("generated_at"),
        "overall": status.get("overall"),
        "operational_overall": operational_overall,
        "operational_failures": operational_failures,
        "operational_warnings": operational_warnings,
        "failures": status.get("summary", {}).get("failures", 0),
        "warnings": status.get("summary", {}).get("warnings", 0),
        "sync_age_seconds": (status.get("events", {}).get("sync") or {}).get("age_seconds"),
        "health_age_seconds": (status.get("events", {}).get("health") or {}).get("age_seconds"),
        "wifi_check_overall": latest_network.get("overall") if latest_network.get("available") else None,
        "pending_recordings": status.get("storage", {}).get("pending_recordings", {}).get("count", 0),
        "pending_bytes": status.get("storage", {}).get("pending_recordings", {}).get("total_bytes", 0),
        "clipping_count": status.get("clipping", {}).get("count", 0),
        "uptime_seconds": status.get("runtime", {}).get("uptime_seconds"),
    }


def load_history(path: Path = HISTORY_FILE) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    if isinstance(data, dict):
        data = data.get("snapshots", [])
    return [item for item in data if isinstance(item, dict)]


def prune_history(snapshots: list[dict[str, Any]], retention_hours: int) -> list[dict[str, Any]]:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=retention_hours)
    kept: list[dict[str, Any]] = []
    for item in snapshots:
        generated = parse_time(str(item.get("generated_at", "")))
        if generated and generated >= cutoff:
            kept.append(item)
    return kept


def write_history(snapshots: list[dict[str, Any]], path: Path = HISTORY_FILE, retention_hours: int = DEFAULT_RETENTION_HOURS) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "retention_hours": retention_hours,
        "snapshots": snapshots,
    }
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as tmp:
        json.dump(payload, tmp, indent=2, sort_keys=True)
        tmp.write("\n")
        tmp_path = Path(tmp.name)
    tmp_path.replace(path)
    path.chmod(0o644)


def summarize(snapshots: list[dict[str, Any]]) -> dict[str, Any]:
    failures = sum(1 for item in snapshots if item.get("failures", 0))
    warnings = sum(1 for item in snapshots if item.get("warnings", 0))
    operational_failures = sum(1 for item in snapshots if item.get("operational_failures", 0))
    operational_warnings = sum(1 for item in snapshots if item.get("operational_warnings", 0))
    wifi_failures = sum(1 for item in snapshots if item.get("wifi_check_overall") == "fail")
    clipping_snapshots = sum(1 for item in snapshots if item.get("clipping_count", 0))
    max_pending = max((int(item.get("pending_recordings") or 0) for item in snapshots), default=0)
    clipping_total = sum(int(item.get("clipping_count") or 0) for item in snapshots)
    latest = snapshots[-1] if snapshots else {}
    latest_time = parse_time(str(latest.get("generated_at", ""))) if latest else None
    latest_age = None
    if latest_time:
        latest_age = max(0, int((datetime.now(timezone.utc) - latest_time).total_seconds()))
    return {
        "snapshots": len(snapshots),
        "latest_generated_at": latest.get("generated_at"),
        "latest_age_seconds": latest_age,
        "latest_overall": latest.get("overall"),
        "latest_operational_overall": latest.get("operational_overall", latest.get("overall")),
        "failure_snapshots": failures,
        "warning_snapshots": warnings,
        "operational_failure_snapshots": operational_failures,
        "operational_warning_snapshots": operational_warnings,
        "wifi_failure_snapshots": wifi_failures,
        "clipping_snapshots": clipping_snapshots,
        "max_pending_recordings": max_pending,
        "clipping_total": clipping_total,
    }


def append_snapshot(retention_hours: int = DEFAULT_RETENTION_HOURS) -> dict[str, Any]:
    snapshots = prune_history(load_history(), retention_hours)
    snapshots.append(compact_snapshot(status_json.collect_status()))
    snapshots = prune_history(snapshots, retention_hours)
    write_history(snapshots, retention_hours=retention_hours)
    return {"path": str(HISTORY_FILE), "summary": summarize(snapshots)}


def read_payload(retention_hours: int = DEFAULT_RETENTION_HOURS) -> dict[str, Any]:
    snapshots = prune_history(load_history(), retention_hours)
    return {
        "path": str(HISTORY_FILE),
        "retention_hours": retention_hours,
        "summary": summarize(snapshots),
        "snapshots": snapshots,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Maintain Train Recorder status history")
    parser.add_argument("--json", action="store_true", help="print the current history as JSON")
    parser.add_argument("--no-write", action="store_true", help="do not append a new snapshot")
    parser.add_argument("--retention-hours", type=int, default=DEFAULT_RETENTION_HOURS)
    args = parser.parse_args()

    if args.no_write:
        payload = read_payload(args.retention_hours)
    else:
        payload = append_snapshot(args.retention_hours)

    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        summary = payload["summary"]
        print(
            "history snapshots={snapshots} failures={failure_snapshots} warnings={warning_snapshots} "
            "wifi_failures={wifi_failure_snapshots} max_pending={max_pending_recordings}".format(**summary)
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
