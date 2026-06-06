#!/usr/bin/env bash
set -euo pipefail

python3 - "$@" <<'PY'
import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_SITE = Path("/etc/train-recorder/site.yaml")
DEFAULT_OUTPUT = Path("/tmp/train-recorder-generated")
DEFAULT_CONFIG_DIR = Path("/etc/train-recorder")
DEFAULT_INSTALL_DIR = Path("/opt/train-recorder")
RTL_AIRBAND_CONF = Path("/usr/local/etc/rtl_airband.conf")
PULSE_SYSTEM_PA = Path("/etc/pulse/system.pa")
SYSTEMD_DIR = Path("/etc/systemd/system")


def parse_scalar(value):
    value = value.strip()
    if value == "":
        return ""
    if value[0:1] in ("'", '"') and value[-1:] == value[0]:
        return value[1:-1]
    if value.lower() in ("true", "yes", "on"):
        return True
    if value.lower() in ("false", "no", "off"):
        return False
    if value.lower() in ("null", "none", "~"):
        return None
    try:
        if re.match(r"^-?\d+$", value):
            return int(value)
        if re.match(r"^-?\d+\.\d+$", value):
            return float(value)
    except ValueError:
        pass
    return value


def simple_yaml_load(path):
    root = {}
    current_key = None
    current_item = None

    for raw in Path(path).read_text().splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        indent = len(line) - len(line.lstrip(" "))
        text = line.strip()

        if indent == 0:
            if text.endswith(":"):
                key = text[:-1].strip()
                root[key] = [] if key == "channels" else {}
                current_key = key
                current_item = None
            else:
                key, value = text.split(":", 1)
                root[key.strip()] = parse_scalar(value)
                current_key = None
                current_item = None
        elif current_key == "channels" and indent == 2 and text.startswith("- "):
            current_item = {}
            root["channels"].append(current_item)
            rest = text[2:].strip()
            if rest:
                key, value = rest.split(":", 1)
                current_item[key.strip()] = parse_scalar(value)
        elif current_key == "channels" and indent >= 4 and current_item is not None:
            key, value = text.split(":", 1)
            current_item[key.strip()] = parse_scalar(value)
        elif current_key and isinstance(root.get(current_key), dict):
            key, value = text.split(":", 1)
            root[current_key][key.strip()] = parse_scalar(value)
        else:
            raise ValueError(f"Cannot parse line: {raw}")

    return root


def load_site(path):
    path = Path(path)
    if not path.exists():
        raise SystemExit(f"site config not found: {path}")
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(path.read_text())
    except Exception:
        data = simple_yaml_load(path)
    validate_site(data)
    return data


def yaml_bool(value):
    return "true" if bool(value) else "false"


def yaml_quote(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    text = str(value)
    if text == "" or any(ch in text for ch in [":", "#", '"', "'"]) or text.lower() in ("true", "false", "null"):
        return '"' + text.replace('"', '\\"') + '"'
    return text


def write_site_yaml(data, path):
    path = Path(path)
    lines = []
    site = data.get("site", {})
    sdr = data.get("sdr", {})
    broadcastify = data.get("broadcastify", {})
    channels = data.get("channels", [])

    lines.append("site:")
    for key in [
        "name",
        "output_root",
        "temp_dir",
        "pulse_server",
        "audio_format",
        "sox_volume",
        "stop_duration",
        "stop_threshold",
        "recording_umask",
        "check_recent_local_recordings",
        "check_recent_sync_success",
        "max_sync_success_age_minutes",
        "rclone_remote",
        "rclone_min_age",
    ]:
        if key in site:
            lines.append(f"  {key}: {yaml_quote(site[key])}")

    lines.append("")
    lines.append("sdr:")
    for key in ["type", "index", "gain", "correction", "bandwidth_mhz", "center_frequency_mhz"]:
        if key in sdr and sdr[key] not in (None, ""):
            lines.append(f"  {key}: {yaml_quote(sdr[key])}")

    lines.append("")
    lines.append("broadcastify:")
    for key in [
        "enabled",
        "channel",
        "server",
        "port",
        "mountpoint",
        "username",
        "password",
        "name",
        "genre",
        "description",
        "send_scan_freq_tags",
    ]:
        if key in broadcastify:
            lines.append(f"  {key}: {yaml_quote(broadcastify[key])}")

    lines.append("")
    lines.append("channels:")
    for channel in channels:
        first = True
        for key in [
            "name",
            "frequency_mhz",
            "pulse_sink",
            "output_suffix",
            "sox_volume",
            "start_duration",
            "min_bytes",
            "health_check_recent_save",
            "max_save_age_minutes",
            "afc",
            "stream_ampfactor",
        ]:
            if key not in channel:
                continue
            prefix = "  - " if first else "    "
            first = False
            lines.append(f"{prefix}{key}: {yaml_quote(channel[key])}")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def env_name_for_frequency(freq):
    return "freq" + str(freq).replace(".", "").replace("_", "")


def bool_value(value, default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).lower() in ("1", "true", "yes", "on")


def validate_site(data):
    if not isinstance(data, dict):
        raise SystemExit("site config must be a mapping")
    channels = data.get("channels")
    if not channels:
        raise SystemExit("site config must define at least one channel")
    names = set()
    freqs = []
    for idx, channel in enumerate(channels, 1):
        if "frequency_mhz" not in channel:
            raise SystemExit(f"channel {idx} is missing frequency_mhz")
        freq = float(channel["frequency_mhz"])
        freqs.append(freq)
        name = channel.get("name") or env_name_for_frequency(freq)
        if not re.match(r"^[A-Za-z0-9_.-]+$", name):
            raise SystemExit(f"channel name has unsupported characters: {name}")
        if name in names:
            raise SystemExit(f"duplicate channel name: {name}")
        names.add(name)
    sdr = data.get("sdr", {})
    bandwidth = float(sdr.get("bandwidth_mhz", 2.4))
    spread = max(freqs) - min(freqs)
    if spread > bandwidth:
        raise SystemExit(
            f"frequency spread {spread:.6f} MHz exceeds configured SDR bandwidth {bandwidth:.6f} MHz"
        )


def channel_name(channel):
    return str(channel.get("name") or env_name_for_frequency(channel["frequency_mhz"]))


def pulse_sink(channel, idx):
    return str(channel.get("pulse_sink") or f"freq{idx + 1}sink")


def output_suffix(channel):
    return str(channel.get("output_suffix") or f"_{float(channel['frequency_mhz']):.3f}")


def center_frequency(data):
    sdr = data.get("sdr", {})
    if sdr.get("center_frequency_mhz"):
        return float(sdr["center_frequency_mhz"])
    freqs = [float(ch["frequency_mhz"]) for ch in data["channels"]]
    return round((min(freqs) + max(freqs)) / 2, 6)


def generated_paths(outdir, data):
    paths = [
        Path(outdir) / "rtl_airband.conf",
        Path(outdir) / "system.pa",
        Path(outdir) / "common.env",
    ]
    site = data.get("site", {})
    if site.get("rclone_remote"):
        paths.append(Path(outdir) / "sync.env")
    for channel in data["channels"]:
        paths.append(Path(outdir) / f"{channel_name(channel)}.env")
    return paths


def q(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def env_line(key, value):
    if isinstance(value, bool):
        value = "true" if value else "false"
    return f"{key}={value}"


def generate_common_env(data):
    site = data.get("site", {})
    channels = ",".join(channel_name(ch) for ch in data["channels"])
    lines = [
        env_line("OUTPUT_ROOT", site.get("output_root", "/home/pi/Recordings")),
        env_line("TEMP_DIR", site.get("temp_dir", "/mnt/ramdisk")),
        env_line("PULSE_SERVER", site.get("pulse_server", "unix:/run/pulse/native")),
        env_line("VOX_CHANNELS", channels),
        env_line("AUDIO_FORMAT", site.get("audio_format", "mp3")),
        env_line("SOX_VOLUME", site.get("sox_volume", 4)),
        env_line("START_THRESHOLD", site.get("start_threshold", "0.1%")),
        env_line("STOP_DURATION", site.get("stop_duration", "13.0")),
        env_line("STOP_THRESHOLD", site.get("stop_threshold", "0.1%")),
        env_line("RECORDING_UMASK", site.get("recording_umask", "0002")),
        env_line("CHECK_RECENT_LOCAL_RECORDINGS", yaml_bool(site.get("check_recent_local_recordings", False))),
        env_line("CHECK_RECENT_SYNC_SUCCESS", yaml_bool(site.get("check_recent_sync_success", True))),
        env_line("MAX_SYNC_SUCCESS_AGE_MINUTES", site.get("max_sync_success_age_minutes", 30)),
    ]
    return "\n".join(lines) + "\n"


def generate_sync_env(data):
    site = data.get("site", {})
    lines = [
        env_line("RECORDINGS_DIR", site.get("output_root", "/home/pi/Recordings")),
        env_line("RCLONE_REMOTE", site.get("rclone_remote", "")),
        env_line("RCLONE_MIN_AGE", site.get("rclone_min_age", "15s")),
    ]
    return "\n".join(lines) + "\n"


def generate_channel_env(channel, idx):
    sink = pulse_sink(channel, idx)
    lines = [
        env_line("CHANNEL_NAME", channel_name(channel)),
        env_line("FREQUENCY_MHZ", channel["frequency_mhz"]),
        env_line("PULSE_MONITOR", f"{sink}.monitor"),
        env_line("OUTPUT_SUFFIX", output_suffix(channel)),
    ]
    for src, dest in [
        ("sox_volume", "SOX_VOLUME"),
        ("start_duration", "START_DURATION"),
        ("start_threshold", "START_THRESHOLD"),
        ("stop_duration", "STOP_DURATION"),
        ("stop_threshold", "STOP_THRESHOLD"),
        ("min_bytes", "MIN_BYTES"),
    ]:
        if src in channel:
            lines.append(env_line(dest, channel[src]))
    lines.append(env_line("HEALTH_CHECK_RECENT_SAVE", yaml_bool(channel.get("health_check_recent_save", True))))
    lines.append(env_line("MAX_SAVE_AGE_MINUTES", channel.get("max_save_age_minutes", 1440)))
    return "\n".join(lines) + "\n"


def generate_system_pa(data):
    lines = [
        "#!/usr/bin/pulseaudio -nF",
        "# Generated by train-recorder site_config.sh. Local edits may be overwritten by apply.",
        "load-module module-device-restore",
        "load-module module-stream-restore",
        "load-module module-card-restore",
        ".ifexists module-udev-detect.so",
        "load-module module-udev-detect",
        ".else",
        "load-module module-detect",
        ".endif",
        ".ifexists module-esound-protocol-unix.so",
        "load-module module-esound-protocol-unix",
        ".endif",
        "load-module module-native-protocol-unix",
        "load-module module-default-device-restore",
        "load-module module-always-sink",
        "load-module module-suspend-on-idle",
        "load-module module-position-event-sounds",
        "",
    ]
    for idx, channel in enumerate(data["channels"]):
        sink = pulse_sink(channel, idx)
        lines.append(f"load-module module-null-sink sink_name={sink} sink_properties=device.description={sink}")
    return "\n".join(lines) + "\n"


def generate_rtl_airband(data):
    sdr = data.get("sdr", {})
    broadcastify = data.get("broadcastify", {})
    broadcastify_enabled = bool_value(broadcastify.get("enabled"), False)
    mixer_name = "mixer1"
    lines = [
        "# Generated by train-recorder site_config.sh. Local edits may be overwritten by apply.",
        "log_scan_activity = true;",
        "",
    ]
    if broadcastify_enabled:
        lines.extend(
            [
                "mixers: {",
                f"  {mixer_name}: {{",
                "    outputs: (",
                "      {",
                '        disable = false;',
                '        type = "icecast";',
                f"        server = {q(broadcastify.get('server', 'audio9.broadcastify.com'))};",
                f"        port = {int(broadcastify.get('port', 80))};",
                f"        mountpoint = {q(broadcastify.get('mountpoint', 'YOUR_MOUNTPOINT'))};",
                f"        name = {q(broadcastify.get('name', data.get('site', {}).get('name', 'Train Recorder')))};",
                f"        genre = {q(broadcastify.get('genre', 'RAIL'))};",
                f"        username = {q(broadcastify.get('username', 'source'))};",
                f"        password = {q(broadcastify.get('password', 'YOUR_BROADCASTIFY_PASSWORD'))};",
                f"        send_scan_freq_tags = {str(bool_value(broadcastify.get('send_scan_freq_tags'), False)).lower()};",
                f"        description = {q(broadcastify.get('description', data.get('site', {}).get('name', 'Train Recorder')))};",
                "      }",
                "    );",
                "  }",
                "};",
                "",
            ]
        )
    lines.extend(
        [
            "devices:",
            "({",
            f"  type = {q(sdr.get('type', 'rtlsdr'))};",
            f"  index = {int(sdr.get('index', 0))};",
            f"  gain = {sdr.get('gain', 48)};",
            f"  centerfreq = {center_frequency(data)};",
            f"  correction = {sdr.get('correction', 0)};",
            "  channels:",
            "  (",
        ]
    )
    broadcast_channel = str(broadcastify.get("channel", ""))
    for idx, channel in enumerate(data["channels"]):
        sink = pulse_sink(channel, idx)
        name = channel_name(channel)
        outputs = [
            [
                '          type = "pulse";',
                f"          sink = {q(sink)};",
            ]
        ]
        if broadcastify_enabled and name == broadcast_channel:
            outputs.append(
                [
                    '          type = "mixer";',
                    f"          name = {q(mixer_name)};",
                    f"          ampfactor = {channel.get('stream_ampfactor', 1.0)};",
                ]
            )
        lines.extend(
            [
                "    {",
                f"      freq = {channel['frequency_mhz']};",
                f"      modulation = {q(channel.get('modulation', 'nfm'))};",
                f"      afc = {1 if bool_value(channel.get('afc'), False) else 0};",
                "      outputs: (",
            ]
        )
        for out_idx, output in enumerate(outputs):
            lines.append("        {")
            lines.extend(output)
            lines.append("        }" + ("," if out_idx < len(outputs) - 1 else ""))
        lines.extend(["      );", "    }" + ("," if idx < len(data["channels"]) - 1 else "")])
    lines.extend(["  );", " }", ");", ""])
    return "\n".join(lines)


def generate_files(data, outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "common.env").write_text(generate_common_env(data))
    if data.get("site", {}).get("rclone_remote"):
        (outdir / "sync.env").write_text(generate_sync_env(data))
    (outdir / "system.pa").write_text(generate_system_pa(data))
    (outdir / "rtl_airband.conf").write_text(generate_rtl_airband(data))
    for idx, channel in enumerate(data["channels"]):
        (outdir / f"{channel_name(channel)}.env").write_text(generate_channel_env(channel, idx))
    return outdir


def old_channels(config_dir):
    common = Path(config_dir) / "common.env"
    if not common.exists():
        return []
    for line in common.read_text().splitlines():
        if line.startswith("VOX_CHANNELS="):
            value = line.split("=", 1)[1].strip().strip('"').strip("'")
            return [v for v in re.split(r"[,\s]+", value) if v]
    return []


def new_channels(data):
    return [channel_name(ch) for ch in data["channels"]]


def show_plan(data, config_dir=DEFAULT_CONFIG_DIR):
    old = set(old_channels(config_dir))
    new = set(new_channels(data))
    print("Plan:")
    print(f"- Generate {len(new)} channel env files: {', '.join(sorted(new))}")
    for channel in sorted(new - old):
        print(f"- Enable/start vox@{channel}.service")
    for channel in sorted(old - new):
        print(f"- Stop/disable vox@{channel}.service")
    print("- Regenerate common.env, channel env files, rtl_airband.conf, and system.pa")
    if data.get("site", {}).get("rclone_remote"):
        print("- Regenerate sync.env")
    print("- Back up replaced files under /etc/train-recorder/backups/<timestamp>/")
    print("- Restart pulseaudio.service, rtl_airband.service, and configured vox@ services")


def run(command, check=True):
    print("+ " + " ".join(str(c) for c in command), flush=True)
    return subprocess.run(command, check=check)


def sudo_prefix():
    return [] if os.geteuid() == 0 else ["sudo"]


def copy_with_backup(src, dest, backup_dir):
    src = Path(src)
    dest = Path(dest)
    if dest.exists():
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dest, backup_dir / dest.name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def apply_config(data, generated, yes=False, config_dir=DEFAULT_CONFIG_DIR, install_dir=DEFAULT_INSTALL_DIR):
    generated = Path(generated)
    if not generated.exists():
        raise SystemExit(f"generated directory does not exist: {generated}")
    show_plan(data, config_dir)
    if not yes:
        answer = input("Apply this plan? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("aborted")
            return

    ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root = Path(config_dir) / "backups" / ts
    backup_root.mkdir(parents=True, exist_ok=True)
    old = set(old_channels(config_dir))
    new = set(new_channels(data))
    sudo = sudo_prefix()

    temp_apply = Path(tempfile.mkdtemp(prefix="train-recorder-apply."))
    for path in generated_paths(generated, data):
        if path.exists():
            shutil.copy2(path, temp_apply / path.name)

    mapping = {
        "common.env": Path(config_dir) / "common.env",
        "sync.env": Path(config_dir) / "sync.env",
        "rtl_airband.conf": RTL_AIRBAND_CONF,
        "system.pa": PULSE_SYSTEM_PA,
    }
    for channel in data["channels"]:
        mapping[f"{channel_name(channel)}.env"] = Path(config_dir) / f"{channel_name(channel)}.env"

    for name, dest in mapping.items():
        src = temp_apply / name
        if src.exists():
            copy_with_backup(src, dest, backup_root)

    template = Path(install_dir) / "Service_Files" / "vox@.service"
    if template.exists():
        copy_with_backup(template, SYSTEMD_DIR / "vox@.service", backup_root)

    run(sudo + ["systemctl", "daemon-reload"])
    for channel in sorted(old - new):
        run(sudo + ["systemctl", "disable", "--now", f"vox@{channel}.service"], check=False)
    for channel in sorted(old | new):
        run(sudo + ["systemctl", "stop", f"vox@{channel}.service"], check=False)
    run(sudo + ["systemctl", "restart", "pulseaudio.service"])
    run(sudo + ["systemctl", "restart", "rtl_airband.service"])
    for channel in sorted(new):
        run(sudo + ["systemctl", "enable", "--now", f"vox@{channel}.service"])
    print(f"Backups written to {backup_root}")


def prompt(prompt_text, default=None):
    suffix = f" [{default}]" if default not in (None, "") else ""
    answer = input(f"{prompt_text}{suffix}: ").strip()
    return answer if answer else default


def prompt_bool(prompt_text, default=False):
    suffix = "Y/n" if default else "y/N"
    answer = input(f"{prompt_text} [{suffix}]: ").strip().lower()
    if not answer:
        return default
    return answer in ("y", "yes", "true", "1")


def wizard(path):
    channels = []
    site_name = prompt("Site name", "Train Recorder")
    count = int(prompt("How many frequencies should be recorded", "2"))
    for idx in range(count):
        freq = float(prompt(f"Frequency {idx + 1} in MHz"))
        name = prompt("Channel env name", env_name_for_frequency(freq))
        sink = prompt("PulseAudio sink name", f"freq{idx + 1}sink")
        channels.append(
            {
                "name": name,
                "frequency_mhz": freq,
                "pulse_sink": sink,
                "output_suffix": f"_{freq:.3f}",
                "start_duration": "0.2",
                "min_bytes": 700,
                "health_check_recent_save": prompt_bool("Require recent-save health warning for this channel", idx == 0),
                "max_save_age_minutes": int(prompt("Max save age minutes", "1440" if idx == 0 else "4320")),
                "afc": prompt_bool("Enable RTLSDR-Airband AFC for this channel", idx == 0),
            }
        )
    stream_enabled = prompt_bool("Stream one channel to Broadcastify/Icecast", False)
    broadcastify = {"enabled": stream_enabled}
    if stream_enabled:
        default_channel = channels[0]["name"]
        broadcastify.update(
            {
                "channel": prompt("Channel to stream", default_channel),
                "server": prompt("Icecast server", "audio9.broadcastify.com"),
                "port": int(prompt("Icecast port", "80")),
                "mountpoint": prompt("Icecast mountpoint", "YOUR_MOUNTPOINT"),
                "username": prompt("Icecast username", "source"),
                "password": prompt("Icecast password", "YOUR_PASSWORD"),
                "name": prompt("Feed name", site_name),
                "genre": prompt("Genre", "RAIL"),
                "description": prompt("Description", site_name),
                "send_scan_freq_tags": False,
            }
        )
    data = {
        "site": {
            "name": site_name,
            "output_root": prompt("Recording output root", "/home/pi/Recordings"),
            "temp_dir": prompt("RAM disk/temp dir", "/mnt/ramdisk"),
            "pulse_server": "unix:/run/pulse/native",
            "audio_format": "mp3",
            "sox_volume": 4,
            "stop_duration": "13.0",
            "stop_threshold": "0.1%",
            "recording_umask": "0002",
            "check_recent_local_recordings": False,
            "check_recent_sync_success": True,
            "max_sync_success_age_minutes": 30,
            "rclone_remote": prompt("rclone remote, blank to skip", ""),
            "rclone_min_age": "15s",
        },
        "sdr": {
            "type": "rtlsdr",
            "index": 0,
            "gain": prompt("RTL-SDR gain", "48"),
            "correction": 0,
            "bandwidth_mhz": float(prompt("Usable SDR bandwidth MHz", "2.4")),
        },
        "broadcastify": broadcastify,
        "channels": channels,
    }
    validate_site(data)
    write_site_yaml(data, path)
    print(f"wrote {path}")


def cmd_generate(args):
    data = load_site(args.site)
    outdir = generate_files(data, args.output)
    print(f"generated files in {outdir}")
    for path in generated_paths(outdir, data):
        if path.exists():
            print(f"- {path}")


def cmd_plan(args):
    data = load_site(args.site)
    show_plan(data)


def cmd_apply(args):
    if os.geteuid() != 0:
        raise SystemExit("apply must be run as root, for example: sudo Scripts/site_config.sh apply")
    data = load_site(args.site)
    outdir = Path(args.output)
    generate_files(data, outdir)
    apply_config(data, outdir, yes=args.yes)


def cmd_status(_args):
    run(["systemctl", "is-active", "pulseaudio.service", "rtl_airband.service"], check=False)
    run(["systemctl", "list-units", "vox@*.service", "--no-pager"], check=False)


def main():
    parser = argparse.ArgumentParser(description="Train Recorder site configuration tool")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("wizard", help="interactively write a site.yaml")
    p.add_argument("--site", default=str(DEFAULT_SITE))
    def wizard_command(args):
        path = Path(args.site)
        if str(path).startswith("/etc/") and os.geteuid() != 0:
            raise SystemExit("writing to /etc requires root, for example: sudo Scripts/site_config.sh wizard")
        wizard(path)
    p.set_defaults(func=wizard_command)

    p = sub.add_parser("generate", help="generate config files from site.yaml")
    p.add_argument("--site", default=str(DEFAULT_SITE))
    p.add_argument("--output", default=str(DEFAULT_OUTPUT))
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("plan", help="show changes needed to apply site.yaml")
    p.add_argument("--site", default=str(DEFAULT_SITE))
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser("apply", help="generate and apply site.yaml to the live system")
    p.add_argument("--site", default=str(DEFAULT_SITE))
    p.add_argument("--output", default=str(DEFAULT_OUTPUT))
    p.add_argument("--yes", action="store_true")
    p.set_defaults(func=cmd_apply)

    p = sub.add_parser("status", help="show current templated VOX unit state")
    p.set_defaults(func=cmd_status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
PY
