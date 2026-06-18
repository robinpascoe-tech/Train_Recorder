import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from support import load_script_module


site_config = load_script_module("Scripts/site_config.py", "train_recorder_site_config")


def sample_data(*, remote="onedrive:ONR/test", channels=None, output_root="/tmp/out", temp_dir="/tmp/ramdisk"):
    if channels is None:
        channels = [
            {
                "name": "freq160545",
                "frequency_mhz": 160.545,
                "pulse_sink": "freq1sink",
                "output_suffix": "_160.545",
                "afc": True,
                "health_check_recent_save": True,
                "max_save_age_minutes": 1440,
            },
            {
                "name": "freq161265",
                "frequency_mhz": 161.265,
                "pulse_sink": "freq2sink",
                "output_suffix": "_161.265",
                "afc": False,
                "health_check_recent_save": False,
                "max_save_age_minutes": 4320,
            },
        ]
    return {
        "site": {
            "name": "Train Recorder",
            "output_root": output_root,
            "temp_dir": temp_dir,
            "pulse_server": "unix:/run/pulse/native",
            "audio_format": "mp3",
            "sox_volume": 4,
            "stop_duration": "13.0",
            "stop_threshold": "0.1%",
            "recording_umask": "0002",
            "check_recent_local_recordings": False,
            "check_recent_sync_success": bool(remote),
            "max_sync_success_age_minutes": 30,
            "rclone_remote": remote,
            "rclone_min_age": "15s",
        },
        "sdr": {
            "type": "rtlsdr",
            "index": 0,
            "gain": 48,
            "correction": 0,
            "bandwidth_mhz": 2.4,
        },
        "broadcastify": {
            "enabled": False,
        },
        "channels": channels,
    }


class ValidateSiteTests(unittest.TestCase):
    def test_rejects_duplicate_frequency(self):
        data = sample_data(
            channels=[
                {
                    "name": "freq160545",
                    "frequency_mhz": 160.545,
                    "pulse_sink": "freq1sink",
                    "output_suffix": "_160.545",
                },
                {
                    "name": "freq160545_alt",
                    "frequency_mhz": 160.545,
                    "pulse_sink": "freq2sink",
                    "output_suffix": "_160.545_alt",
                },
            ]
        )
        with self.assertRaises(SystemExit) as raised:
            site_config.validate_site(data)
        self.assertIn("duplicate channel frequency", str(raised.exception))

    def test_rejects_duplicate_pulse_sink(self):
        data = sample_data(
            channels=[
                {
                    "name": "freq160545",
                    "frequency_mhz": 160.545,
                    "pulse_sink": "sharedsink",
                    "output_suffix": "_160.545",
                },
                {
                    "name": "freq161265",
                    "frequency_mhz": 161.265,
                    "pulse_sink": "sharedsink",
                    "output_suffix": "_161.265",
                },
            ]
        )
        with self.assertRaises(SystemExit) as raised:
            site_config.validate_site(data)
        self.assertIn("duplicate pulse sink", str(raised.exception))

    def test_rejects_duplicate_output_suffix(self):
        data = sample_data(
            channels=[
                {
                    "name": "freq160545",
                    "frequency_mhz": 160.545,
                    "pulse_sink": "freq1sink",
                    "output_suffix": "_shared",
                },
                {
                    "name": "freq161265",
                    "frequency_mhz": 161.265,
                    "pulse_sink": "freq2sink",
                    "output_suffix": "_shared",
                },
            ]
        )
        with self.assertRaises(SystemExit) as raised:
            site_config.validate_site(data)
        self.assertIn("duplicate output suffix", str(raised.exception))


class PlanAndApplyTests(unittest.TestCase):
    def build_apply_fixture(self, remote="", old_channels='VOX_CHANNELS="freq160545 oldchan"\n'):
        temp_dir = tempfile.TemporaryDirectory()
        root = Path(temp_dir.name)
        config_dir = root / "etc" / "train-recorder"
        install_dir = root / "opt" / "train-recorder"
        generated_dir = root / "generated"
        systemd_dir = root / "etc" / "systemd" / "system"
        pulse_path = root / "etc" / "pulse" / "system.pa"
        rtl_path = root / "usr" / "local" / "etc" / "rtl_airband.conf"
        output_root = root / "recordings"
        temp_path = root / "ramdisk"

        config_dir.mkdir(parents=True)
        (install_dir / "Service_Files").mkdir(parents=True)
        systemd_dir.mkdir(parents=True)
        pulse_path.parent.mkdir(parents=True)
        rtl_path.parent.mkdir(parents=True)
        output_root.mkdir(parents=True)
        temp_path.mkdir(parents=True)

        (config_dir / "common.env").write_text(old_channels)
        (config_dir / "freq160545.env").write_text("CHANNEL_NAME=freq160545\n")
        (config_dir / "oldchan.env").write_text("CHANNEL_NAME=oldchan\n")
        (config_dir / "sync.env").write_text("RCLONE_REMOTE=onedrive:test\n")
        pulse_path.write_text("old pulse config\n")
        rtl_path.write_text("old rtl config\n")
        (install_dir / "Service_Files" / "vox@.service").write_text("[Unit]\nDescription=VOX\n")

        data = sample_data(
            remote=remote,
            channels=[
                {
                    "name": "freq160545",
                    "frequency_mhz": 160.545,
                    "pulse_sink": "freq1sink",
                    "output_suffix": "_160.545",
                    "afc": True,
                    "health_check_recent_save": True,
                    "max_save_age_minutes": 1440,
                }
            ],
            output_root=str(output_root),
            temp_dir=str(temp_path),
        )
        site_config.generate_files(data, generated_dir)
        return {
            "temp_dir": temp_dir,
            "root": root,
            "config_dir": config_dir,
            "install_dir": install_dir,
            "generated_dir": generated_dir,
            "systemd_dir": systemd_dir,
            "pulse_path": pulse_path,
            "rtl_path": rtl_path,
            "output_root": output_root,
            "temp_path": temp_path,
            "data": data,
        }

    def test_show_plan_mentions_stale_files_and_local_only_sync(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir)
            (config_dir / "common.env").write_text('VOX_CHANNELS="oldchan"\n')
            (config_dir / "oldchan.env").write_text("CHANNEL_NAME=oldchan\n")
            (config_dir / "sync.env").write_text("RCLONE_REMOTE=onedrive:test\n")

            data = sample_data(
                remote="",
                channels=[
                    {
                        "name": "freq160545",
                        "frequency_mhz": 160.545,
                        "pulse_sink": "freq1sink",
                        "output_suffix": "_160.545",
                    }
                ],
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                site_config.show_plan(data, config_dir=config_dir)
            plan_text = stdout.getvalue()

            self.assertIn("Disable train-recorder-sync.timer and remove sync.env for local-only mode", plan_text)
            self.assertIn(f"Remove stale generated file {config_dir / 'oldchan.env'}", plan_text)
            self.assertIn(f"Remove stale generated file {config_dir / 'sync.env'}", plan_text)

    def test_apply_config_removes_stale_channel_env_and_sync_env(self):
        fixture = self.build_apply_fixture(remote="")
        self.addCleanup(fixture["temp_dir"].cleanup)
        config_dir = fixture["config_dir"]
        install_dir = fixture["install_dir"]
        generated_dir = fixture["generated_dir"]
        systemd_dir = fixture["systemd_dir"]
        pulse_path = fixture["pulse_path"]
        rtl_path = fixture["rtl_path"]
        data = fixture["data"]

        commands = []

        def fake_run(command, check=True):
            commands.append((command, check))
            return SimpleNamespace(returncode=0)

        with mock.patch.object(site_config, "RTL_AIRBAND_CONF", rtl_path), \
            mock.patch.object(site_config, "PULSE_SYSTEM_PA", pulse_path), \
            mock.patch.object(site_config, "SYSTEMD_DIR", systemd_dir), \
            mock.patch.object(site_config, "run", side_effect=fake_run):
            site_config.apply_config(
                data,
                generated_dir,
                yes=True,
                config_dir=config_dir,
                install_dir=install_dir,
            )

        self.assertFalse((config_dir / "oldchan.env").exists())
        self.assertFalse((config_dir / "sync.env").exists())
        self.assertTrue((config_dir / "freq160545.env").exists())
        self.assertTrue(any(command[-3:] == ["disable", "--now", "train-recorder-sync.timer"] for command, _ in commands))
        self.assertTrue(any(command[-3:] == ["disable", "--now", "vox@oldchan.service"] for command, _ in commands))

        backup_root = next((config_dir / "backups").iterdir())
        self.assertTrue((backup_root / "oldchan.env").exists())
        self.assertTrue((backup_root / "sync.env").exists())

    def test_apply_config_fails_when_runtime_path_missing(self):
        fixture = self.build_apply_fixture(remote="")
        self.addCleanup(fixture["temp_dir"].cleanup)
        fixture["temp_path"].rmdir()

        with mock.patch.object(site_config, "RTL_AIRBAND_CONF", fixture["rtl_path"]), \
            mock.patch.object(site_config, "PULSE_SYSTEM_PA", fixture["pulse_path"]), \
            mock.patch.object(site_config, "SYSTEMD_DIR", fixture["systemd_dir"]):
            with self.assertRaises(SystemExit) as raised:
                site_config.apply_config(
                    fixture["data"],
                    fixture["generated_dir"],
                    yes=True,
                    config_dir=fixture["config_dir"],
                    install_dir=fixture["install_dir"],
                )

        self.assertIn("required directory missing", str(raised.exception))
        self.assertFalse((fixture["config_dir"] / "backups").exists())

    def test_apply_config_reports_restore_notes_on_partial_copy_failure(self):
        fixture = self.build_apply_fixture(remote="")
        self.addCleanup(fixture["temp_dir"].cleanup)
        config_dir = fixture["config_dir"]
        install_dir = fixture["install_dir"]
        generated_dir = fixture["generated_dir"]
        data = fixture["data"]

        original_copy = site_config.copy_with_backup
        calls = {"count": 0}

        def flaky_copy(src, dest, backup_dir):
            calls["count"] += 1
            if calls["count"] == 2:
                raise OSError("simulated copy failure")
            return original_copy(src, dest, backup_dir)

        stdout = io.StringIO()
        with mock.patch.object(site_config, "RTL_AIRBAND_CONF", fixture["rtl_path"]), \
            mock.patch.object(site_config, "PULSE_SYSTEM_PA", fixture["pulse_path"]), \
            mock.patch.object(site_config, "SYSTEMD_DIR", fixture["systemd_dir"]), \
            mock.patch.object(site_config, "copy_with_backup", side_effect=flaky_copy), \
            contextlib.redirect_stdout(stdout):
            with self.assertRaises(SystemExit) as raised:
                site_config.apply_config(
                    data,
                    generated_dir,
                    yes=True,
                    config_dir=config_dir,
                    install_dir=install_dir,
                )

        output = stdout.getvalue()
        self.assertIn("apply failed while updating files; backup files are available for restore.", output)
        self.assertIn("Restore notes:", output)
        self.assertIn("apply failed while updating files: simulated copy failure", str(raised.exception))
        backup_root = next((config_dir / "backups").iterdir())
        self.assertTrue((backup_root / "common.env").exists())

    def test_apply_config_reports_restore_notes_on_systemctl_failure(self):
        fixture = self.build_apply_fixture(remote="")
        self.addCleanup(fixture["temp_dir"].cleanup)
        config_dir = fixture["config_dir"]
        install_dir = fixture["install_dir"]
        generated_dir = fixture["generated_dir"]
        data = fixture["data"]

        commands = []

        def fake_run(command, check=True):
            commands.append(command)
            if command[-2:] == ["restart", "rtl_airband.service"]:
                raise site_config.subprocess.CalledProcessError(returncode=1, cmd=command)
            return SimpleNamespace(returncode=0)

        stdout = io.StringIO()
        with mock.patch.object(site_config, "RTL_AIRBAND_CONF", fixture["rtl_path"]), \
            mock.patch.object(site_config, "PULSE_SYSTEM_PA", fixture["pulse_path"]), \
            mock.patch.object(site_config, "SYSTEMD_DIR", fixture["systemd_dir"]), \
            mock.patch.object(site_config, "run", side_effect=fake_run), \
            contextlib.redirect_stdout(stdout):
            with self.assertRaises(SystemExit) as raised:
                site_config.apply_config(
                    data,
                    generated_dir,
                    yes=True,
                    config_dir=config_dir,
                    install_dir=install_dir,
                )

        output = stdout.getvalue()
        self.assertIn("apply failed; backup files are available for restore.", output)
        self.assertIn("Restore notes:", output)
        self.assertIn("apply failed while running: sudo systemctl restart rtl_airband.service", str(raised.exception))
        backup_root = next((config_dir / "backups").iterdir())
        self.assertTrue((backup_root / "rtl_airband.conf").exists())

    def test_apply_config_refuses_to_remove_non_file_stale_target(self):
        fixture = self.build_apply_fixture(remote="")
        self.addCleanup(fixture["temp_dir"].cleanup)
        stale = fixture["config_dir"] / "oldchan.env"
        stale.unlink()
        stale.mkdir()

        stdout = io.StringIO()
        with mock.patch.object(site_config, "RTL_AIRBAND_CONF", fixture["rtl_path"]), \
            mock.patch.object(site_config, "PULSE_SYSTEM_PA", fixture["pulse_path"]), \
            mock.patch.object(site_config, "SYSTEMD_DIR", fixture["systemd_dir"]), \
            contextlib.redirect_stdout(stdout):
            with self.assertRaises(SystemExit) as raised:
                site_config.apply_config(
                    fixture["data"],
                    fixture["generated_dir"],
                    yes=True,
                    config_dir=fixture["config_dir"],
                    install_dir=fixture["install_dir"],
                )

        self.assertIn("refusing to remove non-file path during apply", str(raised.exception))
        self.assertIn("apply failed while updating files; backup files are available for restore.", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
