#!/usr/bin/env python3
"""Small read-only Flask dashboard for Train Recorder."""

from __future__ import annotations

import os
import sys
from html import escape

sys.dont_write_bytecode = True

from flask import Flask, jsonify

import status_history
import status_json


app = Flask(__name__)


def render_page() -> str:
    status = status_json.collect_status()
    data = escape(status["overall"])
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Train Recorder</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #f4f2ee;
      --surface: #ffffff;
      --ink: #202124;
      --muted: #626b73;
      --line: #d7d2c8;
      --ok: #1f7a4d;
      --warn: #a86600;
      --fail: #b3261e;
      --accent: #245f73;
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #17191a;
        --surface: #222629;
        --ink: #eceff1;
        --muted: #aeb7bd;
        --line: #394146;
        --ok: #6fd19a;
        --warn: #f4bd61;
        --fail: #ff8a80;
        --accent: #8bc5d6;
      }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      letter-spacing: 0;
    }}
    header {{
      border-bottom: 1px solid var(--line);
      background: var(--surface);
    }}
    .wrap {{
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
    }}
    .top {{
      min-height: 72px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      flex-wrap: wrap;
    }}
    h1 {{
      margin: 0;
      font-size: clamp(1.35rem, 2.5vw, 2rem);
      font-weight: 700;
    }}
    .status {{
      display: inline-flex;
      align-items: center;
      gap: 10px;
      min-height: 36px;
      padding: 6px 12px;
      border: 1px solid var(--line);
      border-radius: 6px;
      font-weight: 700;
      text-transform: uppercase;
    }}
    .dot {{
      width: 12px;
      height: 12px;
      border-radius: 50%;
      background: var(--muted);
    }}
    .status.ok .dot {{ background: var(--ok); }}
    .status.warn .dot {{ background: var(--warn); }}
    .status.fail .dot {{ background: var(--fail); }}
    .headline {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 14px;
      margin-bottom: 14px;
    }}
    .metric {{
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px;
      min-width: 0;
    }}
    .metric span {{
      display: block;
      color: var(--muted);
      font-size: 0.82rem;
      font-weight: 700;
      text-transform: uppercase;
    }}
    .metric strong {{
      display: block;
      margin-top: 4px;
      font-size: 1.7rem;
      line-height: 1;
      overflow-wrap: anywhere;
    }}
    .metric small {{
      display: block;
      margin-top: 6px;
      color: var(--muted);
      font-size: 0.82rem;
    }}
    main {{
      padding: 24px 0 40px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 14px;
    }}
    .overview {{
      grid-template-columns: 1.1fr 1fr 1fr;
    }}
    section {{
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px;
      min-width: 0;
    }}
    h2 {{
      margin: 0 0 10px;
      font-size: 1rem;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 0.92rem;
    }}
    th, td {{
      padding: 7px 0;
      border-top: 1px solid var(--line);
      text-align: left;
      vertical-align: top;
    }}
    th {{
      color: var(--muted);
      font-weight: 600;
      width: 46%;
      padding-right: 12px;
    }}
    .muted {{ color: var(--muted); }}
    .ok {{ color: var(--ok); }}
    .warn {{ color: var(--warn); }}
    .fail {{ color: var(--fail); }}
    .mono {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      overflow-wrap: anywhere;
    }}
    .checks {{
      display: grid;
      gap: 8px;
    }}
    .history {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 10px;
    }}
    .history-item {{
      border-top: 1px solid var(--line);
      padding-top: 10px;
      min-width: 0;
    }}
    .history-item span {{
      display: block;
      color: var(--muted);
      font-size: 0.8rem;
      font-weight: 700;
      text-transform: uppercase;
    }}
    .history-item strong {{
      display: block;
      margin-top: 4px;
      font-size: 1.35rem;
      line-height: 1.15;
      overflow-wrap: anywhere;
    }}
    .check {{
      display: grid;
      grid-template-columns: 58px 1fr;
      gap: 10px;
      align-items: baseline;
      border-top: 1px solid var(--line);
      padding-top: 8px;
      font-size: 0.92rem;
    }}
    .pill {{
      display: inline-block;
      border-radius: 5px;
      border: 1px solid currentColor;
      padding: 2px 6px;
      font-size: 0.78rem;
      font-weight: 700;
      text-transform: uppercase;
    }}
    .toolbar {{
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      color: var(--muted);
      font-size: 0.92rem;
    }}
    button, a.button {{
      color: var(--ink);
      background: transparent;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 7px 10px;
      text-decoration: none;
      cursor: pointer;
    }}
    @media (max-width: 720px) {{
      .headline {{
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }}
      .overview {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <header>
    <div class="wrap top">
      <h1>Train Recorder</h1>
      <div class="toolbar">
        <span id="generated">Loading</span>
        <button type="button" id="refresh">Refresh</button>
        <a class="button" href="/api/status">JSON</a>
        <span id="overall" class="status {data}"><span class="dot"></span><span>{data}</span></span>
      </div>
    </div>
  </header>
  <main class="wrap">
    <div class="headline" id="headline"></div>
    <div class="grid overview">
      <section>
        <h2>Summary</h2>
        <table id="summary"></table>
      </section>
      <section>
        <h2>Services</h2>
        <table id="services"></table>
      </section>
      <section>
        <h2>Storage</h2>
        <table id="storage"></table>
      </section>
      <section>
        <h2>Events</h2>
        <table id="events"></table>
      </section>
      <section>
        <h2>Activity</h2>
        <table id="activity"></table>
      </section>
    </div>
    <div class="grid" id="channels" style="margin-top:14px"></div>
    <section style="margin-top:14px">
      <h2>History</h2>
      <div id="history" class="history"></div>
    </section>
    <section style="margin-top:14px">
      <h2>Checks</h2>
      <div id="checks" class="checks"></div>
    </section>
  </main>
  <script>
    const text = value => value === null || value === undefined || value === '' ? 'none' : String(value);
    const cls = value => value === 'fail' ? 'fail' : value === 'warn' ? 'warn' : 'ok';
    const row = (k, v, c = '') => `<tr><th>${{k}}</th><td class="${{c}}">${{v}}</td></tr>`;
    const hist = (label, value, note = '', c = '') => `<div class="history-item"><span>${{label}}</span><strong class="${{c}}">${{value}}</strong><small>${{note}}</small></div>`;
    let currentChecks = [];
    const checkClass = item => item && item.ok === false ? cls(item.level) : 'ok';
    const bytes = value => {{
      if (!value) return '0 B';
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      let idx = 0, num = value;
      while (num >= 1024 && idx < units.length - 1) {{ num /= 1024; idx++; }}
      return `${{num.toFixed(idx ? 1 : 0)}} ${{units[idx]}}`;
    }};
    const age = seconds => {{
      if (seconds === null || seconds === undefined) return 'none';
      if (seconds < 60) return `${{seconds}}s ago`;
      if (seconds < 3600) return `${{Math.floor(seconds / 60)}}m ago`;
      if (seconds < 86400) return `${{Math.floor(seconds / 3600)}}h ago`;
      return `${{Math.floor(seconds / 86400)}}d ago`;
    }};
    const duration = seconds => {{
      if (seconds === null || seconds === undefined) return 'unknown';
      if (seconds < 60) return `${{seconds}}s`;
      if (seconds < 3600) return `${{Math.floor(seconds / 60)}}m`;
      if (seconds < 86400) return `${{Math.floor(seconds / 3600)}}h ${{Math.floor((seconds % 3600) / 60)}}m`;
      return `${{Math.floor(seconds / 86400)}}d ${{Math.floor((seconds % 86400) / 3600)}}h`;
    }};
    const ageIso = value => {{
      if (!value) return 'none';
      const parsed = Date.parse(value);
      if (Number.isNaN(parsed)) return text(value);
      return age(Math.max(0, Math.floor((Date.now() - parsed) / 1000)));
    }};
    const findCheck = name => currentChecks.find(item => item.name === name);
    function fillTable(id, rows) {{
      document.getElementById(id).innerHTML = rows.join('');
    }}
    function render(data) {{
      currentChecks = data.checks || [];
      const overall = document.getElementById('overall');
      overall.className = `status ${{cls(data.overall)}}`;
      overall.lastElementChild.textContent = data.overall;
      document.getElementById('generated').textContent = `${{data.host}} - ${{new Date(data.generated_at).toLocaleString()}}`;
      const nonOk = currentChecks.filter(item => !item.ok);
      const pending = data.storage.pending_recordings;
      const networkStatus = data.network.latest_check.available ? data.network.latest_check.overall : 'not run';
      document.getElementById('headline').innerHTML = [
        `<div class="metric"><span>Overall</span><strong class="${{cls(data.overall)}}">${{data.overall}}</strong><small>${{data.summary.failures}} failures, ${{data.summary.warnings}} warnings</small></div>`,
        `<div class="metric"><span>Uptime</span><strong>${{duration(data.runtime?.uptime_seconds)}}</strong><small>since last boot</small></div>`,
        `<div class="metric"><span>Last Sync</span><strong class="${{checkClass(findCheck('recent sync'))}}">${{age(data.events.sync?.age_seconds)}}</strong><small>${{data.rclone.configured ? 'rclone configured' : 'local only'}}</small></div>`,
        `<div class="metric"><span>Network</span><strong class="${{networkStatus === 'ok' ? 'ok' : 'warn'}}">${{networkStatus}}</strong><small>${{data.network.wifi_ssid || data.network.ip_addresses[0] || 'no network detail'}}</small></div>`,
      ].join('');
      fillTable('summary', [
        row('Overall', data.overall, cls(data.overall)),
        row('Failures', data.summary.failures, data.summary.failures ? 'fail' : 'ok'),
        row('Warnings', data.summary.warnings, data.summary.warnings ? 'warn' : 'ok'),
        row('Hostname', data.network.hostname, 'mono'),
        row('IP address', data.network.ip_addresses.join('<br>') || 'none', 'mono'),
        row('Wi-Fi', data.network.wifi_ssid || (data.network.wifi_connected ? 'connected' : 'unavailable'), 'mono'),
        row('Attention', nonOk.length ? `${{nonOk[0].name}}: ${{nonOk[0].message}}` : 'clear', nonOk.length ? cls(nonOk[0].level) : 'ok'),
        row('Network check', networkStatus, networkStatus === 'ok' ? 'ok' : 'warn'),
        row('Channels', data.config.vox_channels.join(', '), 'mono'),
        row('Rclone', data.rclone.configured ? (data.rclone.reachable ? 'reachable' : 'not reachable') : 'not configured', data.rclone.reachable === false ? 'fail' : 'ok')
      ]);
      fillTable('services', [...data.services, ...data.timers].map(item =>
        row(item.name, `${{item.active}} / ${{item.enabled}}`, item.ok ? 'ok' : 'fail')
      ));
      fillTable('storage', [
        ...data.storage.filesystems.map(item => row(item.path, item.exists ? `${{item.used_percent}}% used, ${{bytes(item.free_bytes)}} free` : 'missing', item.ok ? 'ok' : 'fail')),
        row('Pending MP3s', `${{data.storage.pending_recordings.count}} files, ${{bytes(data.storage.pending_recordings.total_bytes)}}`)
      ]);
      fillTable('events', [
        row('Last sync', age(data.events.sync?.age_seconds), checkClass(findCheck('recent sync'))),
        row('Last health', age(data.events.health?.age_seconds), checkClass(findCheck('train-recorder-health.timer'))),
        row('Last Wi-Fi check', data.network.latest_check.available ? ageIso(data.network.latest_check.generated_at) : 'not run', data.network.latest_check.overall === 'ok' ? 'ok' : 'warn'),
        row('Last cleanup', age(data.events.cleanup?.age_seconds), checkClass(findCheck('train-recorder-cleanup.timer'))),
        row('SOX clipping', `${{data.clipping.count}} warnings, max ${{data.clipping.max_samples}} samples`, data.clipping.count ? 'warn' : 'ok')
      ]);
      fillTable('activity', [
        row('Uptime', duration(data.runtime?.uptime_seconds), 'ok'),
        row('Status age', ageIso(data.generated_at), 'ok'),
        row('Wi-Fi check age', data.network.latest_check.available ? ageIso(data.network.latest_check.generated_at) : 'not run', networkStatus === 'ok' ? 'ok' : 'warn'),
        row('Pending MP3s', `${{pending.count}} files, ${{bytes(pending.total_bytes)}}`),
        row('Pulse sources', data.pulse.sources.length, data.pulse.sources.length ? 'ok' : 'fail'),
        row('First issue', nonOk.length ? nonOk[0].name : 'none', nonOk.length ? cls(nonOk[0].level) : 'ok')
      ]);
      renderHistory(data.history || {{}});
      document.getElementById('channels').innerHTML = data.channels.map(channel => `
        <section>
          <h2>${{channel.frequency_mhz || channel.name}}</h2>
          <table>
            ${{row('Service', `${{channel.service.active}} / ${{channel.service.enabled}}`, channel.service.ok ? 'ok' : 'fail')}}
            ${{row('Pulse source', channel.pulse_monitor || 'missing', channel.pulse_source_exists ? 'ok' : 'fail')}}
            ${{row('Last save', age(channel.last_save?.age_seconds))}}
            ${{row('Clipping', `${{channel.clipping.count}} warnings`, channel.clipping.count ? 'warn' : 'ok')}}
          </table>
        </section>`).join('');
      document.getElementById('checks').innerHTML = data.checks
        .filter(item => !item.ok)
        .map(item => `<div class="check"><span class="pill ${{item.level}}">${{item.level}}</span><span>${{item.name}}: ${{item.message}}</span></div>`)
        .join('') || '<div class="muted">No warnings or failures</div>';
    }}
    function renderHistory(history) {{
      const summary = history.summary || {{}};
      const snapshots = summary.snapshots || 0;
      const latestOverall = summary.latest_operational_overall || summary.latest_overall;
      document.getElementById('history').innerHTML = [
        hist('Samples', snapshots, `${{history.retention_hours || 24}}h window`),
        hist('Last Sample', age(summary.latest_age_seconds), latestOverall || 'none', cls(latestOverall)),
        hist('Operational Warnings', summary.operational_warning_snapshots || 0, 'excluding clipping', summary.operational_warning_snapshots ? 'warn' : 'ok'),
        hist('Pending Peak', summary.max_pending_recordings || 0, 'local MP3 files'),
        hist('Clipping Samples', summary.clipping_snapshots || 0, `${{summary.clipping_total || 0}} total warnings`, summary.clipping_snapshots ? 'warn' : 'ok')
      ].join('');
    }}
    async function refresh() {{
      const response = await fetch('/api/status', {{cache: 'no-store'}});
      render(await response.json());
    }}
    document.getElementById('refresh').addEventListener('click', refresh);
    refresh();
    setInterval(refresh, 30000);
  </script>
</body>
</html>"""


@app.route("/")
def index() -> str:
    return render_page()


@app.route("/api/status")
def api_status():
    status = status_json.collect_status()
    status["history"] = status_history.read_payload()
    return jsonify(status)


@app.route("/api/history")
def api_history():
    return jsonify(status_history.read_payload())


def main() -> None:
    host = os.environ.get("DASHBOARD_HOST", "0.0.0.0")
    port = int(os.environ.get("DASHBOARD_PORT", "8080"))
    app.run(host=host, port=port)


if __name__ == "__main__":
    main()
