#!/usr/bin/env python3
"""Read-only localhost dashboard for the CSV created by monitor.sh. Python stdlib only."""
import argparse
import csv
from datetime import datetime, timedelta
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
MAX_ROWS = 10000
METRICS = {'cpu': 'CPU', 'load': 'Load / core', 'memory': 'Memory', 'disk': 'Disk', 'inode': 'Inodes'}
COLORS = {'cpu':'#70e7bc','load':'#8eaeff','memory':'#f9b872','disk':'#df8ffc','inode':'#65d4e8'}

def load_rows(path):
    if not path.is_file(): return []
    rows = []
    try:
        with path.open(newline='', encoding='utf-8', errors='replace') as f:
            for row in csv.reader(f):
                if len(row) < 5: continue
                ts, metric, value, status = row[:4]
                try: dt = datetime.strptime(ts, '%Y-%m-%d %H:%M:%S')
                except ValueError: continue
                if status not in ('OK','WARN','CRIT','UNKNOWN'): continue
                try: numeric = float(value)
                except ValueError: numeric = None
                rows.append((dt, metric, numeric, status, ','.join(row[4:])))
                if len(rows) > MAX_ROWS: rows.pop(0)
    except OSError: return []
    return sorted(rows, key=lambda r: r[0])

def chart(rows, key, label, color, hours):
    end = rows[-1][0] if rows else datetime.now()
    data = [(dt,v) for dt,m,v,_,_ in rows if m == key and v is not None and dt >= end - timedelta(hours=hours)]
    if not data: return '<div class="empty">No samples yet. Run <code>./monitor.sh --test</code> first.</div>'
    data = data[-120:]
    values = [v for _,v in data]
    last_sample = data[-1][0]
    hi = max(100 if key != 'load' else 1, max(values)*1.12)
    if len(data) == 1: data = [data[0], data[0]]
    points = ' '.join(f'{20+i*680/(len(data)-1):.1f},{158-v/hi*125:.1f}' for i,(_,v) in enumerate(data))
    last = values[-1]
    units = '%' if key != 'load' else ''
    return (f'<div class="chart-meta"><strong>{last:.1f}{units}</strong><span>{len(values)} samples · last {escape(last_sample.strftime("%d %b %H:%M"))}</span></div>'
            f'<svg viewBox="0 0 720 190" role="img" aria-label="{escape(label)} history, latest {last:.1f}{units}">'
            f'<path d="M20 158 H700 M20 96 H700 M20 33 H700" stroke="#28364a" stroke-dasharray="3 6" fill="none"/>'
            f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>'
            f'<text x="20" y="182" fill="#8393a8" font-size="12">{escape(data[0][0].strftime("%d %b %H:%M"))}</text>'
            f'<text x="700" y="182" text-anchor="end" fill="#8393a8" font-size="12">{escape(data[-1][0].strftime("%d %b %H:%M"))}</text></svg>')

def render(rows, hours=24):
    latest = {}
    for row in rows: latest[row[1]] = row
    counts = {s:sum(r[3]==s for r in latest.values()) for s in ('OK','WARN','CRIT','UNKNOWN')}
    timestamp = max((r[0] for r in rows), default=None)
    stale = timestamp and datetime.now()-timestamp > timedelta(minutes=15)
    freshness = 'No checks recorded' if not timestamp else f'Last check: {escape(timestamp.strftime("%d %b %Y, %H:%M:%S"))} (server time)'
    if stale: freshness += ' · Data is older than 15 minutes'
    cards = ''.join(f'<div class="stat {s.lower()}"><span>{s.title()}</span><strong>{counts[s]}</strong></div>' for s in counts)
    graph_specs = [('cpu','CPU'), ('load','Load / core'), ('memory','Memory')]
    for family, title in (('disk','Disk'), ('inode','Inodes')):
        graph_specs.extend((metric, f'{title} · {metric.split(":",1)[1]}') for metric in sorted(latest) if metric.startswith(family+':'))
    graphs = ''.join(f'<article class="panel"><div class="panel-head"><div><span class="eyebrow">HISTORY</span><h2>{escape(label)}</h2></div><span class="legend" style="--c:{COLORS[key.split(":",1)[0]]}">Last {hours}h</span></div>{chart(rows,key,label,COLORS[key.split(":",1)[0]],hours)}</article>' for key,label in graph_specs[:11])
    # Friendly names for mount-specific charts while keeping safely escaped labels.
    table = ''.join(f'<tr><td><strong>{escape(m)}</strong></td><td>{escape("N/A" if v is None else f"{v:g}")}</td><td><span class="badge {s.lower()}">{s}</span></td><td>{escape(msg)}</td></tr>' for _,m,v,s,msg in sorted(latest.values(), key=lambda r:r[1])) or '<tr><td colspan="4">No checks yet. Run ./monitor.sh --test in this repository.</td></tr>'
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="60"><title>Server Pulse | Monitoring</title><style>
:root{{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif;background:#0b111c;color:#edf5fa}}*{{box-sizing:border-box}}body{{margin:0;min-height:100vh;background:radial-gradient(circle at 85% 0%,#182e3b 0%,transparent 34%),#0b111c}}.shell{{max-width:1160px;margin:auto;padding:30px 28px 70px}}header{{display:flex;align-items:center;gap:12px;padding:4px 0 32px;border-bottom:1px solid #243242}}.brand{{background:#70e7bc;color:#0b111c;border-radius:13px;font-size:22px;font-weight:900;padding:9px 13px}}.name{{font-size:16px;font-weight:750;letter-spacing:.01em}}.hint,.muted{{color:#91a4b7}}.hint{{font-size:12px}}.local{{margin-left:auto;border:1px solid #3c6c65;border-radius:99px;color:#96e8c9;font-size:12px;padding:7px 12px}}.hero{{padding:45px 0 31px}}.eyebrow{{color:#76dfc2;font-size:11px;font-weight:800;letter-spacing:.18em}}h1{{font-size:clamp(32px,5vw,52px);line-height:1.1;margin:12px 0 10px;letter-spacing:-.04em}}p{{margin:0;color:#a1b1c1;line-height:1.6}}.stats{{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:8px 0 34px}}.stat,.panel{{background:#121e2b;border:1px solid #263646;border-radius:19px}}.stat{{padding:21px 23px;display:flex;flex-direction:column;gap:8px}}.stat span{{text-transform:uppercase;color:#a7b6c7;letter-spacing:.13em;font-size:11px;font-weight:800}}.stat strong{{font-size:31px;letter-spacing:-.04em}}.stat.ok strong{{color:#70e7bc}}.stat.warn strong{{color:#ffd082}}.stat.crit strong{{color:#ff8f9c}}.grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}}.panel{{padding:23px;min-width:0}}.panel-head{{display:flex;align-items:center;justify-content:space-between;gap:12px}}h2{{font-size:19px;margin:5px 0 0}}.legend{{font-size:12px;color:#a4b5c7;white-space:nowrap}}.legend:before{{content:"";display:inline-block;background:var(--c);width:7px;height:7px;border-radius:50%;margin-right:7px}}.chart-meta{{display:flex;gap:15px;align-items:baseline;margin-top:21px}}.chart-meta strong{{font-size:31px;letter-spacing:-.04em}}.chart-meta span{{font-size:12px;color:#8193a8}}svg{{display:block;width:100%;height:auto;margin-top:10px}}.empty{{padding:46px 0;color:#9aadc0;font-size:13px}}code{{color:#b8e9d8}}.section-head{{margin:37px 0 16px}}.tablewrap{{overflow:auto}}table{{border-collapse:collapse;width:100%;min-width:620px;text-align:left;font-size:13px}}th{{color:#8fa4b7;font-size:11px;letter-spacing:.12em;text-transform:uppercase}}th,td{{padding:14px 12px;border-bottom:1px solid #253544}}td:last-child{{color:#afbecd}}.badge{{border-radius:99px;padding:4px 9px;font-weight:750;font-size:11px}}.badge.ok{{background:#173c36;color:#7de9be}}.badge.warn{{background:#4b3921;color:#ffd082}}.badge.crit{{background:#4b2934;color:#ff9aaa}}.badge.unknown{{background:#343c49;color:#b4c0cd}}footer{{font-size:12px;color:#788da0;margin-top:30px;line-height:1.6}}@media(max-width:700px){{.shell{{padding:18px 16px 48px}}header{{padding-bottom:22px}}.hero{{padding:30px 0 20px}}.stats{{grid-template-columns:repeat(2,1fr);gap:9px}}.stat{{padding:16px}}.grid{{grid-template-columns:1fr}}.panel{{padding:16px}}}}
</style></head><body><div class="shell"><header><div class="brand">↗</div><div><div class="name">Server Pulse</div><div class="hint">LOCAL MONITORING DASHBOARD</div></div><div class="local">● On this device only</div></header><div class="hero"><span class="eyebrow">YOUR SERVER AT A GLANCE</span><h1>System health, made clear.</h1><p>{freshness} · Page refreshes every minute</p></div><div class="stats">{cards}</div><div class="grid">{graphs}</div><div class="section-head"><span class="eyebrow">CHECK BY CHECK</span><h2>Latest results</h2></div><div class="panel tablewrap"><table><thead><tr><th>Check</th><th>Value</th><th>Status</th><th>What it means</th></tr></thead><tbody>{table}</tbody></table></div><footer>Read-only · Data comes from logs/metrics.csv · WARN means check soon, CRIT means act now, UNKNOWN means the check could not run. This page is not a substitute for external alerting.</footer></div></body></html>'''

class Handler(BaseHTTPRequestHandler):
    metrics = None
    def do_GET(self):
        path = urlparse(self.path).path
        if path not in ('/', '/healthz'):
            self.send_error(404); return
        if path == '/healthz':
            body = b'ok\n'; content_type='text/plain; charset=utf-8'
        else:
            body = render(load_rows(self.metrics)).encode('utf-8'); content_type='text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'")
        self.end_headers(); self.wfile.write(body)

if __name__ == '__main__':
    p=argparse.ArgumentParser(description='Local, read-only dashboard for server-monitoring')
    p.add_argument('--metrics', type=Path, default=ROOT.parent/'logs'/'metrics.csv', help='Path to metrics.csv')
    p.add_argument('--port', type=int, default=8765)
    args=p.parse_args()
    if not 1 <= args.port <= 65535: p.error('port must be 1-65535')
    Handler.metrics=args.metrics.expanduser().resolve()
    try:
        with ThreadingHTTPServer(('127.0.0.1', args.port), Handler) as server:
            print(f'Dashboard: http://127.0.0.1:{args.port}/ (only on this device)')
            print(f'Reading: {Handler.metrics} | Ctrl+C to stop')
            server.serve_forever()
    except KeyboardInterrupt: print('\nStopped.')
