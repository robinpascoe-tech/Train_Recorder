import unittest
from unittest import mock

from support import load_script_module


wifi_check = load_script_module("Scripts/wifi_check.py", "train_recorder_wifi_check")


class WifiCheckTests(unittest.TestCase):
    def test_reboot_policy_requests_single_reboot_after_threshold(self):
        env = {
            "WIFI_CHECK_ALLOW_REBOOT": "true",
            "WIFI_CHECK_REBOOT_FAILURE_THRESHOLD": "3",
        }
        previous = {
            "overall": "fail",
            "summary": {"consecutive_failures": 2},
            "remedy": {"reboot_latched_until_success": False},
        }
        failures = [{"name": "gateway", "ok": False, "message": "no default gateway"}]

        policy = wifi_check.reboot_policy(env, previous, failures, 3)

        self.assertTrue(policy["requested"])
        self.assertTrue(policy["reboot_latched_until_success"])
        self.assertIn("3 consecutive failed checks", policy["reason"])

    def test_reboot_policy_waits_for_success_after_first_reboot(self):
        env = {
            "WIFI_CHECK_ALLOW_REBOOT": "true",
            "WIFI_CHECK_REBOOT_FAILURE_THRESHOLD": "3",
        }
        previous = {
            "overall": "fail",
            "summary": {"consecutive_failures": 4},
            "remedy": {"reboot_latched_until_success": True},
        }
        failures = [{"name": "gateway", "ok": False, "message": "no default gateway"}]

        policy = wifi_check.reboot_policy(env, previous, failures, 5)

        self.assertFalse(policy["requested"])
        self.assertTrue(policy["reboot_latched_until_success"])
        self.assertIn("waiting for a successful check", policy["reason"])

    def test_collect_clears_reboot_latch_after_success(self):
        previous = {
            "overall": "fail",
            "summary": {"consecutive_failures": 4},
            "remedy": {"reboot_latched_until_success": True},
        }
        checks = [
            {"name": "ip-address", "ok": True, "message": "assigned", "details": {}},
            {"name": "gateway", "ok": True, "message": "reachable", "details": {}},
            {"name": "dns", "ok": True, "message": "resolved", "details": {}},
            {"name": "rclone", "ok": True, "message": "reachable", "details": {}},
            {"name": "dashboard", "ok": True, "message": "ok", "details": {}},
        ]

        with (
            mock.patch.object(wifi_check, "runtime_env", return_value={"WIFI_CHECK_ALLOW_REBOOT": "true"}),
            mock.patch.object(wifi_check, "load_state", return_value=previous),
            mock.patch.object(wifi_check, "default_gateway", return_value="192.168.3.1"),
            mock.patch.object(
                wifi_check,
                "wifi_status",
                return_value={
                    "ssid": "ONR",
                    "source": "iwgetid",
                    "connected": True,
                },
            ),
            mock.patch.object(wifi_check, "ip_addresses", return_value=["192.168.3.50"]),
            mock.patch.object(wifi_check, "check_gateway", return_value=checks[1]),
            mock.patch.object(wifi_check, "check_dns", return_value=checks[2]),
            mock.patch.object(wifi_check, "check_rclone", return_value=checks[3]),
            mock.patch.object(wifi_check, "check_dashboard", return_value=checks[4]),
            mock.patch.object(wifi_check.platform, "node", return_value="recorder"),
        ):
            payload = wifi_check.collect(remedy=True)

        self.assertEqual(payload["summary"]["consecutive_failures"], 0)
        self.assertFalse(payload["remedy"]["reboot_latched_until_success"])
        self.assertFalse(payload["remedy"]["reboot_requested"])

    def test_check_rclone_uses_run_user_without_sudo(self):
        env = {"RCLONE_REMOTE": "onedrive:test"}
        with (
            mock.patch.object(wifi_check, "command_exists", return_value=True),
            mock.patch.object(wifi_check, "current_user", return_value=wifi_check.RUN_USER),
            mock.patch.object(
                wifi_check,
                "run_cmd",
                return_value={"ok": True, "stdout": "", "stderr": "", "command": []},
            ) as run_cmd,
        ):
            result = wifi_check.check_rclone(env)

        self.assertTrue(result["ok"])
        self.assertEqual(run_cmd.call_args.args[0], ["rclone", "lsd", "onedrive:test"])

    def test_check_rclone_uses_sudo_for_other_user(self):
        env = {"RCLONE_REMOTE": "onedrive:test"}
        with (
            mock.patch.object(wifi_check, "command_exists", return_value=True),
            mock.patch.object(wifi_check, "current_user", return_value="root"),
            mock.patch.object(
                wifi_check,
                "run_cmd",
                return_value={"ok": False, "stdout": "", "stderr": "permission denied", "command": []},
            ) as run_cmd,
        ):
            result = wifi_check.check_rclone(env)

        self.assertFalse(result["ok"])
        self.assertEqual(
            run_cmd.call_args.args[0],
            ["sudo", "-n", "-u", wifi_check.RUN_USER, "rclone", "lsd", "onedrive:test"],
        )
        self.assertEqual(result["details"]["stderr"], "permission denied")

    def test_failure_snapshot_summarizes_failed_checks(self):
        checks = [
            {"name": "gateway", "ok": False, "message": "no default gateway"},
            {"name": "dns", "ok": False, "message": "resolve failed"},
            {"name": "dashboard", "ok": True, "message": "ok"},
        ]
        snapshot = wifi_check.failure_snapshot(checks, "2026-06-18T15:00:00+00:00")

        self.assertEqual(snapshot["generated_at"], "2026-06-18T15:00:00+00:00")
        self.assertEqual(len(snapshot["failed_checks"]), 2)
        self.assertIn("gateway", snapshot["summary"])
        self.assertIn("dns", snapshot["summary"])

    def test_collect_preserves_previous_failure_after_recovery(self):
        checks = [
            {"name": "ip-address", "ok": True, "message": "assigned", "details": {}},
            {"name": "gateway", "ok": True, "message": "reachable", "details": {}},
            {"name": "dns", "ok": True, "message": "resolved", "details": {}},
            {"name": "rclone", "ok": True, "message": "reachable", "details": {}},
            {"name": "dashboard", "ok": True, "message": "ok", "details": {}},
        ]
        previous = {
            "last_failure": {
                "generated_at": "2026-06-18T14:00:00+00:00",
                "summary": "old failure",
            }
        }

        with (
            mock.patch.object(wifi_check, "runtime_env", return_value={}),
            mock.patch.object(wifi_check, "load_state", return_value=previous),
            mock.patch.object(wifi_check, "default_gateway", return_value="192.168.3.1"),
            mock.patch.object(
                wifi_check,
                "wifi_status",
                return_value={
                    "ssid": "ONR",
                    "source": "iwgetid",
                    "connected": True,
                },
            ),
            mock.patch.object(wifi_check, "ip_addresses", return_value=["192.168.3.50"]),
            mock.patch.object(wifi_check, "check_gateway", return_value=checks[1]),
            mock.patch.object(wifi_check, "check_dns", return_value=checks[2]),
            mock.patch.object(wifi_check, "check_rclone", return_value=checks[3]),
            mock.patch.object(wifi_check, "check_dashboard", return_value=checks[4]),
            mock.patch.object(wifi_check.platform, "node", return_value="recorder"),
        ):
            payload = wifi_check.collect(remedy=False)

        self.assertEqual(payload["overall"], "ok")
        self.assertEqual(payload["last_failure"], previous["last_failure"])
        self.assertEqual(payload["summary"]["actions"], 0)

    def test_collect_runs_remedy_when_failures_present(self):
        failure = {"name": "gateway", "ok": False, "message": "no default gateway", "details": {}}

        with (
            mock.patch.object(
                wifi_check,
                "runtime_env",
                return_value={
                    "WIFI_CHECK_ALLOW_REBOOT": "true",
                    "WIFI_CHECK_REBOOT_FAILURE_THRESHOLD": "3",
                },
            ),
            mock.patch.object(wifi_check, "load_state", return_value={}),
            mock.patch.object(wifi_check, "default_gateway", return_value=""),
            mock.patch.object(
                wifi_check,
                "wifi_status",
                return_value={"ssid": "", "source": "", "connected": False},
            ),
            mock.patch.object(wifi_check, "ip_addresses", return_value=[]),
            mock.patch.object(wifi_check, "check_gateway", return_value=failure),
            mock.patch.object(
                wifi_check,
                "check_dns",
                return_value={
                    "name": "dns",
                    "ok": True,
                    "message": "ok",
                    "details": {},
                },
            ),
            mock.patch.object(
                wifi_check,
                "check_rclone",
                return_value={
                    "name": "rclone",
                    "ok": True,
                    "message": "ok",
                    "details": {},
                },
            ),
            mock.patch.object(
                wifi_check,
                "check_dashboard",
                return_value={
                    "name": "dashboard",
                    "ok": True,
                    "message": "ok",
                    "details": {},
                },
            ),
            mock.patch.object(
                wifi_check,
                "remedy_actions",
                return_value=[{"action": "wpa_cli reconnect", "ok": True}],
            ),
            mock.patch.object(wifi_check.platform, "node", return_value="recorder"),
        ):
            payload = wifi_check.collect(remedy=True)

        self.assertEqual(payload["overall"], "fail")
        self.assertEqual(payload["summary"]["actions"], 2)
        self.assertEqual(payload["actions"][0]["action"], "wpa_cli reconnect")
        self.assertEqual(payload["actions"][1]["action"], "reboot gate")
        self.assertIn("waiting for 3 consecutive failed checks", payload["actions"][1]["output"])


if __name__ == "__main__":
    unittest.main()
