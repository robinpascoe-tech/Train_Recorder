import json
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from support import load_script_module


status_json_module = load_script_module("Scripts/status_json.py", "train_recorder_status_json_for_dashboard")
sys.modules["status_json"] = status_json_module
status_history = load_script_module("Scripts/status_history.py", "train_recorder_status_history")
sys.modules["status_history"] = status_history
dashboard = load_script_module("Scripts/dashboard.py", "train_recorder_dashboard")


class StatusHistoryTests(unittest.TestCase):
    def test_compact_snapshot_separates_operational_and_clipping(self):
        status = {
            "generated_at": "2026-06-18T15:00:00+00:00",
            "overall": "warn",
            "summary": {"failures": 0, "warnings": 2},
            "checks": [
                {"name": "recent sync", "ok": False, "level": "fail"},
                {"name": "SOX clipping", "ok": False, "level": "warn"},
                {"name": "Wi-Fi/network check", "ok": False, "level": "warn"},
            ],
            "events": {"sync": {"age_seconds": 90}, "health": {"age_seconds": 30}},
            "network": {"latest_check": {"available": True, "overall": "fail"}},
            "storage": {"pending_recordings": {"count": 3, "total_bytes": 900}},
            "clipping": {"count": 12, "ok": False},
            "runtime": {"uptime_seconds": 1234},
        }

        snapshot = status_history.compact_snapshot(status)

        self.assertEqual(snapshot["operational_failures"], 1)
        self.assertEqual(snapshot["operational_warnings"], 1)
        self.assertEqual(snapshot["operational_overall"], "fail")
        self.assertEqual(snapshot["clipping_count"], 12)
        self.assertFalse(snapshot["clipping_ok"])

    def test_summarize_reports_latest_and_trends(self):
        now = datetime.now(timezone.utc)
        snapshots = [
            {
                "generated_at": (now - timedelta(minutes=20)).isoformat(),
                "overall": "ok",
                "operational_overall": "ok",
                "failures": 0,
                "warnings": 0,
                "operational_failures": 0,
                "operational_warnings": 0,
                "wifi_check_overall": "ok",
                "pending_recordings": 1,
                "clipping_count": 2,
                "clipping_ok": True,
            },
            {
                "generated_at": (now - timedelta(minutes=5)).isoformat(),
                "overall": "warn",
                "operational_overall": "warn",
                "failures": 0,
                "warnings": 1,
                "operational_failures": 0,
                "operational_warnings": 1,
                "wifi_check_overall": "fail",
                "pending_recordings": 4,
                "clipping_count": 5,
                "clipping_ok": False,
            },
        ]

        summary = status_history.summarize(snapshots)

        self.assertEqual(summary["snapshots"], 2)
        self.assertEqual(summary["warning_snapshots"], 1)
        self.assertEqual(summary["wifi_failure_snapshots"], 1)
        self.assertEqual(summary["max_pending_recordings"], 4)
        self.assertEqual(summary["clipping_total"], 7)
        self.assertEqual(summary["latest_operational_overall"], "warn")
        self.assertIsNotNone(summary["latest_age_seconds"])


class DashboardTests(unittest.TestCase):
    def setUp(self):
        self.status_payload = {
            "generated_at": "2026-06-18T15:00:00+00:00",
            "overall": "warn",
            "host": "recorder",
            "summary": {"failures": 0, "warnings": 1},
            "services": [],
            "timers": [],
            "checks": [],
            "channels": [],
            "storage": {"pending_recordings": {"count": 0, "total_bytes": 0}, "filesystems": []},
            "network": {"hostname": "recorder", "ip_addresses": [], "wifi_ssid": "", "wifi_connected": False, "latest_check": {"available": False}},
            "runtime": {"uptime_seconds": 1234},
            "events": {"sync": None, "cleanup": None, "health": None},
            "config": {"vox_channels": []},
            "rclone": {"configured": False, "reachable": None},
            "pulse": {"sources": []},
            "clipping": {"count": 0, "max_samples": 0, "ok": True},
        }
        self.history_payload = {"retention_hours": 24, "summary": {"snapshots": 1}}

    def test_render_page_escapes_overall_text(self):
        payload = dict(self.status_payload)
        payload["overall"] = '<script>alert("x")</script>'
        with mock.patch.object(dashboard.status_json, "collect_status", return_value=payload):
            html = dashboard.render_page()

        self.assertIn("&lt;script&gt;alert", html)
        self.assertNotIn('<script>alert("x")</script>', html)

    def test_api_status_and_history_return_expected_payloads(self):
        with mock.patch.object(dashboard.status_json, "collect_status", return_value=dict(self.status_payload)), \
            mock.patch.object(dashboard.status_history, "read_payload", return_value=self.history_payload):
            client = dashboard.app.test_client()
            status_response = client.get("/api/status")
            history_response = client.get("/api/history")

        self.assertEqual(status_response.status_code, 200)
        self.assertEqual(history_response.status_code, 200)
        status_data = json.loads(status_response.data)
        history_data = json.loads(history_response.data)
        self.assertEqual(status_data["history"], self.history_payload)
        self.assertEqual(history_data, self.history_payload)


if __name__ == "__main__":
    unittest.main()
