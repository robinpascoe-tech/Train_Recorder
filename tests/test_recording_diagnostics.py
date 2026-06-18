import tempfile
import unittest
from pathlib import Path
from unittest import mock

from support import load_script_module


recording_diagnostics = load_script_module("Scripts/recording_diagnostics.py", "train_recorder_recording_diagnostics")


class RecordingDiagnosticsTests(unittest.TestCase):
    def test_recent_save_events_merges_legacy_units_and_deduplicates(self):
        outputs = {
            "vox@freq160545.service": "\n".join(
                [
                    "2026-06-18T10:00:00+00:00 host Saved /tmp/a_160.545.mp3 (100 bytes)",
                    "2026-06-18T10:05:00+00:00 host Saved /tmp/b_160.545.mp3 (120 bytes)",
                ]
            ),
            "vox.service": "\n".join(
                [
                    "2026-06-18T10:00:00+00:00 host Saved /tmp/a_160.545.mp3 (100 bytes)",
                    "2026-06-18T10:06:00+00:00 host Saved /tmp/c_other.mp3 (150 bytes)",
                ]
            ),
        }

        def fake_run(command, timeout=20):
            unit = command[2]
            return {"ok": True, "stdout": outputs[unit], "stderr": ""}

        with mock.patch.object(recording_diagnostics, "run_cmd", side_effect=fake_run):
            events = recording_diagnostics.recent_save_events("freq160545", "_160.545", 24)

        self.assertEqual([event["name"] for event in events], ["a_160.545.mp3", "b_160.545.mp3"])
        self.assertEqual(events[0]["unit"], "vox@freq160545.service")

    def test_parse_sox_stat_extracts_expected_fields(self):
        stderr = """
Maximum amplitude:     0.812500
Minimum amplitude:    -0.750000
RMS     amplitude:     0.123456
Rough   frequency:          456
Volume adjustment:        1.234
"""
        parsed = recording_diagnostics.parse_sox_stat(stderr)

        self.assertEqual(parsed["maximum_amplitude"], 0.8125)
        self.assertEqual(parsed["minimum_amplitude"], -0.75)
        self.assertEqual(parsed["rms_amplitude"], 0.123456)
        self.assertEqual(parsed["rough_frequency"], 456.0)
        self.assertEqual(parsed["volume_adjustment"], 1.234)

    def test_mp3_files_filters_by_suffix_and_lookback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            recent = root / "recent_160.545.mp3"
            old = root / "old_160.545.mp3"
            other = root / "recent_161.265.mp3"
            for path in [recent, old, other]:
                path.write_bytes(b"data")

            now = 10_000
            with mock.patch.object(recording_diagnostics.time, "time", return_value=now):
                recent.touch()
                other.touch()
                old.touch()
                old_mtime = now - (48 * 3600)
                other_mtime = now - 60
                recent_mtime = now - 30
                import os

                os.utime(recent, (recent_mtime, recent_mtime))
                os.utime(old, (old_mtime, old_mtime))
                os.utime(other, (other_mtime, other_mtime))

                files = recording_diagnostics.mp3_files(root, "_160.545", 24)

        self.assertEqual([path.name for path in files], ["recent_160.545.mp3"])

    def test_summarize_samples_and_events(self):
        samples = [
            {"duration_seconds": 10.0, "bytes": 100, "sox_stat": {"rms_amplitude": 0.1, "maximum_amplitude": 0.8}},
            {"duration_seconds": 20.0, "bytes": 200, "sox_stat": {"rms_amplitude": 0.2, "maximum_amplitude": -0.9}},
        ]
        events = [
            {"bytes": 100, "name": "a.mp3"},
            {"bytes": 200, "name": "b.mp3"},
        ]

        summary = recording_diagnostics.summarize_samples(samples)
        recent = recording_diagnostics.summarize_events(events)

        self.assertEqual(summary["sampled_files"], 2)
        self.assertEqual(summary["total_bytes"], 300)
        self.assertEqual(summary["average_duration_seconds"], 15.0)
        self.assertEqual(summary["average_rms_amplitude"], 0.15)
        self.assertEqual(summary["max_peak_amplitude"], 0.9)
        self.assertEqual(recent["count"], 2)
        self.assertEqual(recent["average_bytes"], 150.0)
        self.assertEqual(recent["latest_name"], "b.mp3")


if __name__ == "__main__":
    unittest.main()
