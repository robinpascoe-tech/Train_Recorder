import unittest
from unittest import mock

from support import load_script_module


status_json = load_script_module("Scripts/status_json.py", "train_recorder_status_json")


class StatusJsonTests(unittest.TestCase):
    def test_recent_recordings_filters_suffix_and_deduplicates(self):
        lines = [
            "1000 host unit: Saved /tmp/20260618_120000_160.545.mp3 (100 bytes)",
            "1000 host unit: Saved /tmp/20260618_120000_160.545.mp3 (100 bytes)",
            "1005 host unit: Saved /tmp/20260618_120500_161.265.mp3 (200 bytes)",
        ]
        with mock.patch.object(status_json, "journal_lines", return_value=lines), mock.patch.object(
            status_json.time, "time", return_value=1010
        ):
            summary = status_json.recent_recordings(["vox@freq160545.service"], 60, "_160.545")

        self.assertEqual(summary["count"], 1)
        self.assertEqual(summary["total_bytes"], 100)
        self.assertEqual(summary["latest"]["name"], "20260618_120000_160.545.mp3")

    def test_clipping_summary_tracks_max_samples_and_thresholds(self):
        lines = [
            "Jun 18 10:00:00 recorder sox[1]: balancing clipped 8 samples",
            "Jun 18 10:01:00 recorder sox[1]: balancing clipped 32 samples",
            "Jun 18 10:02:00 recorder sox[1]: unrelated line",
        ]
        with mock.patch.object(status_json, "journal_lines", return_value=lines):
            summary = status_json.clipping_summary(["vox@freq160545.service"], 60, warn_count=2, warn_max_samples=40)

        self.assertEqual(summary["count"], 2)
        self.assertEqual(summary["max_samples"], 32)
        self.assertFalse(summary["ok"])


if __name__ == "__main__":
    unittest.main()
