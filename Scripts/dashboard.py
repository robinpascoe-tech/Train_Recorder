#!/usr/bin/env python3
"""Small read-only Flask dashboard for Train Recorder."""

from __future__ import annotations

import os
from html import escape

from flask import Flask, jsonify

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
    main {{
      padding: 24px 0 40px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 14px;
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
    <div class="grid">
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
    </div>
    <div class="grid" id="channels" style="margin-top:14px"></div>
    <section style="margin-top:14px">
      <h2>Checks</h2>
      <div id="checks" class="checks"></div>
    </section>
  </main>
  <script>
    const text = value => value === null || value === undefined || value === '' ? 'none' : String(value);
    const cls = value => value === 'fail' ? 'fail' : value === 'warn' ? 'warn' : 'ok';
    const row = (k, v, c = '') => `<tr><th>${{k}}</th><td class="${{c}}">${{v}}</td></tr>`;
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
    function fillTable(id, rows) {{
      document.getElementById(id).innerHTML = rows.join('');
    }}
    function render(data) {{
      const overall = document.getElementById('overall');
      overall.className = `status ${{cls(data.overall)}}`;
      overall.lastElementChild.textContent = data.overall;
      document.getElementById('generated').textContent = `${{data.host}} · ${{new Date(data.generated_at).toLocaleString()}}`;
      fillTable('summary', [
        row('Overall', data.overall, cls(data.overall)),
        row('Failures', data.summary.failures, data.summary.failures ? 'fail' : 'ok'),
        row('Warnings', data.summary.warnings, data.summary.warnings ? 'warn' : 'ok'),
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
        row('Last sync', age(data.events.sync?.age_seconds)),
        row('Last cleanup', age(data.events.cleanup?.age_seconds)),
        row('Last health', age(data.events.health?.age_seconds)),
        row('SOX clipping', `${{data.clipping.count}} warnings, max ${{data.clipping.max_samples}} samples`, data.clipping.count ? 'warn' : 'ok')
      ]);
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
    return jsonify(status_json.collect_status())


def main() -> None:
    host = os.environ.get("DASHBOARD_HOST", "0.0.0.0")
    port = int(os.environ.get("DASHBOARD_PORT", "8080"))
    app.run(host=host, port=port)


if __name__ == "__main__":
    main()
