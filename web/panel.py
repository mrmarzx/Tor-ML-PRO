#!/usr/bin/env python3
# tor-ml Web Panel 4.3.1 – English admin UI (Tor + Psiphon)
from __future__ import annotations

import hashlib, hmac, json, os, secrets, subprocess, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE = Path(os.environ.get("TOR_ML_BASE", "/opt/tor-ml"))
CFG = BASE / "config"
PANEL_CONF = CFG / "panel.json"
CLI = Path(os.environ.get("TOR_ML_CLI", "/usr/local/bin/tor"))
SALT = "tor-ml-v4.3.1"
SESSION_TTL = 86400 * 7
SESSIONS: dict[str, float] = {}

def hash_password(pw: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", pw.encode(), SALT.encode(), 120_000).hex()

def verify_password(pw: str, stored: str) -> bool:
    return hmac.compare_digest(hash_password(pw), stored)

def load_panel_conf() -> dict:
    data = {
        "username": "admin",
        "password_hash": hash_password("admin123"),
        "host": "0.0.0.0",
        "port": 8080,
        "session_secret": secrets.token_hex(32),
        "setup_done": False,
    }
    if PANEL_CONF.exists():
        try:
            data.update(json.loads(PANEL_CONF.read_text()))
        except Exception:
            pass
    return data

def save_panel_conf(data: dict) -> None:
    CFG.mkdir(parents=True, exist_ok=True)
    PANEL_CONF.write_text(json.dumps(data, indent=2))
    os.chmod(PANEL_CONF, 0o600)

def run_cli(*args: str, timeout: int = 120):
    try:
        p = subprocess.run([str(CLI), *args], capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, "TERM": "dumb"})
        return p.returncode, p.stdout or "", p.stderr or ""
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except FileNotFoundError:
        return 127, "", f"CLI not found: {CLI}"
    except Exception as e:
        return 1, "", str(e)

def cpu_percent() -> float:
    try:
        with open("/proc/stat") as f:
            parts = [float(x) for x in f.readline().split()[1:]]
        idle1, total1 = parts[3], sum(parts)
        time.sleep(0.08)
        with open("/proc/stat") as f:
            parts = [float(x) for x in f.readline().split()[1:]]
        idle2, total2 = parts[3], sum(parts)
        di, dt = idle2 - idle1, total2 - total1
        return round(max(0.0, min(100.0, (1.0 - di / dt) * 100)), 1) if dt > 0 else 0.0
    except Exception:
        return 0.0

def mem_percent() -> float:
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, v, *_ = line.replace(":", " ").split()
                if k in ("MemTotal", "MemAvailable"):
                    info[k] = float(v)
        if "MemTotal" in info and "MemAvailable" in info:
            return round((info["MemTotal"] - info["MemAvailable"]) / info["MemTotal"] * 100, 1)
    except Exception:
        pass
    return 0.0

def status_json() -> dict:
    code, out, err = run_cli("--json-status", timeout=45)
    if code == 0 and out.strip():
        try:
            data = json.loads(out)
            data.setdefault("cpu", cpu_percent())
            data.setdefault("mem", mem_percent())
            return data
        except json.JSONDecodeError:
            pass
    return {"ok": False, "error": err or out or "status failed", "cpu": cpu_percent(), "mem": mem_percent(),
            "locations": [], "running_count": 0, "balancer": {"active": False, "port": 49000},
            "mode": "normal", "version": "4.3.1"}

def make_session() -> str:
    token = secrets.token_urlsafe(32)
    SESSIONS[token] = time.time() + SESSION_TTL
    return token

def valid_session(token: str | None) -> bool:
    if not token: return False
    exp = SESSIONS.get(token)
    if not exp or time.time() > exp:
        SESSIONS.pop(token, None)
        return False
    return True

CSS = """
:root{--bg:#070b14;--panel:#0f1624;--card:#151e30;--line:#243049;--text:#eaf0ff;--muted:#8fa0bf;--accent:#4f8cff;--ok:#22c55e;--warn:#f59e0b;--bad:#ef4444}
*{box-sizing:border-box}body{margin:0;font-family:Inter,system-ui,sans-serif;color:var(--text);min-height:100vh;
background:radial-gradient(1000px 500px at 0% -10%,#1d4ed833,transparent),radial-gradient(900px 500px at 100% 0%,#7e22ce22,transparent),var(--bg)}
body::before{content:"";position:fixed;inset:0;pointer-events:none;background-image:linear-gradient(rgba(255,255,255,.015) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.015) 1px,transparent 1px);background-size:40px 40px;animation:gridMove 28s linear infinite}
@keyframes gridMove{to{background-position:40px 40px}}
@keyframes fadeUp{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes shimmer{0%{background-position:-200% 0}100%{background-position:200% 0}}
.wrap{position:relative;z-index:1;max-width:1280px;margin:0 auto;padding:18px}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:12px 16px;border:1px solid var(--line);border-radius:16px;margin-bottom:16px;background:linear-gradient(180deg,#121a2bcc,#0d1422cc);backdrop-filter:blur(10px);animation:fadeUp .45s ease both}
.brand{display:flex;align-items:center;gap:10px;font-weight:700}
.brand .dot{width:11px;height:11px;border-radius:50%;background:var(--ok);animation:pulse 1.6s infinite}
.nav{display:flex;gap:7px;flex-wrap:wrap}
.nav button,.btn{background:var(--card);color:var(--text);border:1px solid var(--line);border-radius:11px;padding:8px 12px;cursor:pointer;font-size:13px;transition:transform .15s,border-color .15s}
.nav button:hover,.btn:hover{border-color:var(--accent);transform:translateY(-1px)}
.btn.primary{background:linear-gradient(135deg,#2563eb,#7c3aed);border:none;box-shadow:0 8px 24px #2563eb33}
.btn.ok{background:#14532d;border-color:#166534}.btn.bad{background:#7f1d1d;border-color:#991b1b}.btn.warn{background:#78350f;border-color:#92400e}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:14px}
@media(max-width:900px){.grid{grid-template-columns:repeat(2,1fr)}}
.card,.section{background:linear-gradient(180deg,#152036,#101827);border:1px solid var(--line);border-radius:16px;animation:fadeUp .5s ease both}
.card{padding:14px 16px;position:relative;overflow:hidden}
.card::after{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(110deg,transparent 20%,rgba(255,255,255,.04) 45%,transparent 70%);background-size:200% 100%;animation:shimmer 4.5s linear infinite}
.card .k{color:var(--muted);font-size:11px;letter-spacing:.7px;text-transform:uppercase}
.card .v{font-size:24px;font-weight:700;margin-top:6px}
.section{padding:14px;margin-bottom:14px}
.section h2{margin:0 0 12px;font-size:14px;color:var(--muted);font-weight:600}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:10px 8px;border-bottom:1px solid var(--line);text-align:left}
th{color:var(--muted);font-size:11px}
.badge{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:700}
.badge.on{background:#14532d;color:#86efac}.badge.off{background:#27272a;color:#a1a1aa}
.badge.tor{background:#0c4a6e;color:#7dd3fc}.badge.psi{background:#4c1d95;color:#e9d5ff}
.row-actions{display:flex;gap:6px;flex-wrap:wrap}
.login-box,.setup-box{max-width:420px;margin:9vh auto;padding:28px;background:linear-gradient(180deg,#152036,#0f172a);border:1px solid var(--line);border-radius:18px;box-shadow:0 20px 60px #0008;animation:fadeUp .5s ease both}
.login-box h1,.setup-box h1{margin:0 0 6px;font-size:22px}
.login-box p,.setup-box p{color:var(--muted);margin:0 0 16px;font-size:13px}
input,select{width:100%;background:#0b1220;border:1px solid var(--line);color:var(--text);border-radius:11px;padding:11px 12px;margin-bottom:10px;font-size:14px}
input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px #3b82f633}
pre.log{background:#070d18;border:1px solid var(--line);border-radius:12px;padding:12px;max-height:420px;overflow:auto;font-size:12px;line-height:1.45;color:#cbd5e1;white-space:pre-wrap;word-break:break-word}
.toast{position:fixed;right:16px;bottom:16px;z-index:60;min-width:220px;max-width:380px;background:#0b1220;border:1px solid var(--line);border-radius:12px;padding:12px 14px;display:none;animation:fadeUp .25s ease both}
.muted{color:var(--muted)}.flex{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.bar{height:8px;background:#1f2937;border-radius:99px;overflow:hidden;margin-top:8px}
.bar>i{display:block;height:100%;width:0;transition:width .6s ease;background:linear-gradient(90deg,#22c55e,#eab308,#ef4444)}
.mini{height:6px;width:70px;background:#1f2937;border-radius:99px;overflow:hidden;display:inline-block;vertical-align:middle}
.mini>i{display:block;height:100%;background:linear-gradient(90deg,#38bdf8,#a78bfa);transition:width .5s ease}
.spinner{width:14px;height:14px;border:2px solid #334155;border-top-color:#60a5fa;border-radius:50%;display:inline-block;animation:spin .7s linear infinite;margin-right:6px}
.live-tag{font-size:11px;color:#86efac}
"""

SETUP_HTML = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tor-ml Setup</title><style>""" + CSS + """</style></head><body>
<div class="setup-box"><h1>First-time setup</h1>
<p>Set admin username, password and panel port.</p>
<form method="POST" action="/setup">
<label class="muted" style="font-size:12px">Username</label>
<input name="username" value="admin" required minlength="3">
<label class="muted" style="font-size:12px">Password</label>
<input name="password" type="password" required minlength="6" placeholder="min 6 characters">
<label class="muted" style="font-size:12px">Confirm password</label>
<input name="password2" type="password" required minlength="6">
<label class="muted" style="font-size:12px">Panel port</label>
<input name="port" type="number" min="1" max="65535" value="8080" required>
<label class="muted" style="font-size:12px">Bind host</label>
<input name="host" value="0.0.0.0" required>
<button class="btn primary" style="width:100%;padding:12px" type="submit">Save &amp; continue</button>
</form>{err}</div></body></html>"""

LOGIN_HTML = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tor-ml Login</title><style>""" + CSS + """</style></head><body>
<div class="login-box"><h1>tor-ml Panel</h1>
<p>Sign in to manage Tor &amp; Psiphon.</p>
<form method="POST" action="/login">
<input name="username" placeholder="Username" required>
<input name="password" type="password" placeholder="Password" required>
<button class="btn primary" style="width:100%;padding:12px" type="submit">Sign in</button>
</form>{err}</div></body></html>"""

APP_HTML = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tor-ml Control Panel</title><style>""" + CSS + """</style></head><body>
<div class="wrap">
<div class="top">
  <div class="brand"><span class="dot" id="liveDot"></span> tor-ml <span class="muted" id="ver"></span> <span class="live-tag">● live</span></div>
  <div class="nav">
    <button onclick="show('dash')">Dashboard</button>
    <button onclick="show('locs')">Locations</button>
    <button onclick="show('bal')">Balancer</button>
    <button onclick="show('perf')">Performance</button>
    <button onclick="show('logs')">Logs</button>
    <button onclick="show('tools')">Tools</button>
    <button onclick="show('settings')">Settings</button>
    <button onclick="logout()">Logout</button>
  </div>
</div>
<div id="view-dash">
  <div class="grid">
    <div class="card"><div class="k">Running</div><div class="v" id="s-run">—</div></div>
    <div class="card"><div class="k">CPU</div><div class="v" id="s-cpu">—</div><div class="bar"><i id="b-cpu"></i></div></div>
    <div class="card"><div class="k">Memory</div><div class="v" id="s-mem">—</div><div class="bar"><i id="b-mem"></i></div></div>
    <div class="card"><div class="k">Mode / Balancer</div><div class="v" id="s-mode">—</div></div>
  </div>
  <div class="section"><h2>Quick actions</h2>
    <div class="flex">
      <button class="btn ok" onclick="act('start-all-tor')">Start all Tor</button>
      <button class="btn ok" onclick="act('start-all-psi')">Start all Psiphon</button>
      <button class="btn bad" onclick="act('stop-all')">Stop all</button>
      <button class="btn primary" onclick="act('balancer-start')">Start balancer</button>
      <button class="btn" onclick="act('balancer-stop')">Stop balancer</button>
      <button class="btn warn" onclick="refresh()">Refresh</button>
    </div>
  </div>
  <div class="section"><h2>Active instances · live CPU / RAM</h2><div id="activeTable"></div></div>
</div>
<div id="view-locs" style="display:none">
  <div class="section"><h2>Tor locations</h2><div id="torTable"></div></div>
  <div class="section"><h2>Psiphon locations</h2><div id="psiTable"></div></div>
</div>
<div id="view-bal" style="display:none">
  <div class="section"><h2>Balancer</h2>
    <div class="flex"><button class="btn primary" onclick="act('balancer-start')">Start</button>
    <button class="btn bad" onclick="act('balancer-stop')">Stop</button></div>
    <div id="balInfo" class="card" style="margin-top:12px"></div>
  </div>
</div>
<div id="view-perf" style="display:none">
  <div class="section"><h2>Performance mode</h2>
    <div class="flex">
      <button class="btn" onclick="act('mode-weak')">Weak</button>
      <button class="btn primary" onclick="act('mode-normal')">Normal</button>
      <button class="btn warn" onclick="act('mode-max')">Maximum</button>
    </div>
    <div id="perfInfo" class="card" style="margin-top:12px"></div>
  </div>
  <div class="section"><h2>Sticky exit</h2>
    <div class="flex"><button class="btn" onclick="act('sticky-on')">Enable</button>
    <button class="btn" onclick="act('sticky-off')">Disable</button></div>
  </div>
</div>
<div id="view-logs" style="display:none">
  <div class="section"><h2>Logs</h2>
    <div class="flex"><select id="logId" style="max-width:300px"></select>
    <button class="btn" onclick="loadLog()">Load</button></div>
    <pre class="log" id="logBox">Select a location…</pre>
  </div>
</div>
<div id="view-tools" style="display:none">
  <div class="section"><h2>Live ping / latency</h2>
    <div class="flex">
      <button class="btn primary" onclick="runPing(false)">Ping all running</button>
      <button class="btn" onclick="runPing(true)">Full speed test</button>
    </div>
    <pre class="log" id="testBox" style="margin-top:12px">Results appear here…</pre>
  </div>
  <div class="section"><h2>Change SOCKS port</h2>
    <div class="flex">
      <input id="portId" placeholder="ID e.g. 01 or P01" style="max-width:140px">
      <input id="portVal" placeholder="New port" style="max-width:140px">
      <button class="btn" onclick="changePort()">Apply</button>
    </div>
  </div>
</div>
<div id="view-settings" style="display:none">
  <div class="section"><h2>Admin password</h2>
    <input id="np1" type="password" placeholder="New password">
    <input id="np2" type="password" placeholder="Confirm">
    <button class="btn primary" onclick="changePass()">Update password</button>
  </div>
  <div class="section"><h2>Panel bind</h2>
    <p class="muted">After port change: systemctl restart tor-ml-web</p>
    <input id="bindHost" placeholder="0.0.0.0">
    <input id="bindPort" placeholder="8080">
    <button class="btn" onclick="saveBind()">Save</button>
  </div>
</div>
</div>
<div class="toast" id="toast"></div>
<script>
let busy=false;
function $(id){return document.getElementById(id)}
function toast(msg,ok=true){const t=$('toast');t.style.display='block';t.style.borderColor=ok?'#166534':'#991b1b';
t.innerHTML=(busy?'<span class="spinner"></span>':'')+msg;clearTimeout(window.__tt);window.__tt=setTimeout(()=>t.style.display='none',3800)}
function show(n){['dash','locs','bal','perf','logs','tools','settings'].forEach(v=>$('view-'+v).style.display=v===n?'block':'none')}
async function api(path,opts={}){const r=await fetch(path,{credentials:'same-origin',headers:{'Content-Type':'application/json',...(opts.headers||{})},...opts});
if(r.status===401){location.href='/login';return null}return await r.json().catch(()=>({ok:false}))}
function badgeRunning(on){return on?'<span class="badge on">RUNNING</span>':'<span class="badge off">stopped</span>'}
function usageCell(x){if(!x.running)return '<span class="muted">—</span>';
const cpu=x.cpu_pct!=null?Number(x.cpu_pct).toFixed(1):'—';const mem=x.mem_mb!=null?Number(x.mem_mb).toFixed(0)+' MB':'—';
const w=Math.min(100,Number(x.cpu_pct||0));return `<div>${cpu}% · ${mem}<br><span class="mini"><i style="width:${w}%"></i></span></div>`}
function tableHtml(rows,actions=false){if(!rows.length)return '<p class="muted">No entries.</p>';
let h=`<table><thead><tr><th>ID</th><th>Type</th><th>Location</th><th>Port</th><th>Status</th><th>CPU/RAM</th><th>Latency</th><th>IP</th>${actions?'<th>Actions</th>':''}</tr></thead><tbody>`;
for(const x of rows){h+=`<tr><td>${x.id}</td><td><span class="badge ${x.type}">${(x.type||'').toUpperCase()}</span></td>
<td>${x.name||''} <span class="muted">${x.code||''}</span></td><td>${x.port}</td><td>${badgeRunning(!!x.running)}</td>
<td>${usageCell(x)}</td><td>${x.latency!=null?x.latency+' ms':'—'}</td><td>${x.ip||'—'}</td>
${actions?`<td class="row-actions"><button class="btn ok" onclick="act('start','${x.id}')">Start</button>
<button class="btn bad" onclick="act('stop','${x.id}')">Stop</button>
<button class="btn" onclick="pingOne('${x.id}')">Ping</button></td>`:''}</tr>`}
return h+'</tbody></table>'}
function render(s){const locs=s.locations||[];const active=locs.filter(x=>x.running);
$('activeTable').innerHTML=tableHtml(active.length?active:[]);
$('torTable').innerHTML=tableHtml(locs.filter(x=>x.type==='tor'),true);
$('psiTable').innerHTML=tableHtml(locs.filter(x=>x.type==='psi'),true);
const sel=$('logId');const cur=sel.value;
sel.innerHTML=locs.map(x=>`<option value="${x.id}">${x.id} · ${(x.type||'').toUpperCase()} · ${x.name||''}</option>`).join('');
if(cur)sel.value=cur;
$('balInfo').innerHTML=s.balancer&&s.balancer.active?`<div class="k">Status</div><div class="v">Active :${s.balancer.port}</div><p class="muted">Target ${s.balancer.target||'—'} · ${s.balancer.best_id||''}</p>`:`<div class="k">Status</div><div class="v">Inactive</div>`;
$('perfInfo').innerHTML=`<div class="k">Mode</div><div class="v">${(s.mode||'normal').toUpperCase()}</div>`;
if(s.panel){$('bindHost').value=s.panel.host||'0.0.0.0';$('bindPort').value=s.panel.port||8080}}
async function refresh(){const j=await api('/api/status');if(!j)return;
$('ver').textContent='v'+(j.version||'4.3.1');
$('s-run').textContent=j.running_count??(j.locations||[]).filter(x=>x.running).length;
$('s-cpu').textContent=(j.cpu??0)+'%';$('s-mem').textContent=(j.mem??0)+'%';
$('b-cpu').style.width=Math.min(100,j.cpu||0)+'%';$('b-mem').style.width=Math.min(100,j.mem||0)+'%';
$('s-mode').textContent=((j.mode||'normal')+'').toUpperCase()+(j.balancer?.active?' · BAL '+j.balancer.port:'');
$('liveDot').style.background=j.ok===false?'var(--bad)':'var(--ok)';render(j)}
async function act(name,id){if(busy)return;busy=true;toast('Running '+name+'…');
const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:name,id:id||null})});busy=false;
if(!j)return;toast(j.message||(j.ok?'Done':'Failed'),!!j.ok);await refresh()}
async function loadLog(){const j=await api('/api/log?id='+encodeURIComponent($('logId').value));$('logBox').textContent=j?.log||'(empty)'}
async function runPing(full){$('testBox').textContent=full?'Full speed test…':'Pinging…';
const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:full?'speed-test':'ping-test'})});
$('testBox').textContent=j?.output||j?.message||'No output';toast(j?.ok?'Done':'Failed',!!j?.ok);await refresh()}
async function pingOne(id){show('tools');$('testBox').textContent='Pinging '+id+'…';
const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:'ping-one',id})});
$('testBox').textContent=j?.output||j?.message||'';toast(j?.ok?'Ping done':'Failed',!!j?.ok);await refresh()}
async function changePort(){const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:'change-port',id:$('portId').value.trim(),port:$('portVal').value.trim()})});toast(j?.message||'',!!j?.ok);refresh()}
async function changePass(){const a=$('np1').value,b=$('np2').value;if(!a||a!==b){toast('Mismatch',false);return}
const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:'set-password',password:a})});toast(j?.message||'',!!j?.ok)}
async function saveBind(){const j=await api('/api/action',{method:'POST',body:JSON.stringify({action:'set-bind',host:$('bindHost').value.trim(),port:parseInt($('bindPort').value,10)})});toast((j?.message||'')+' Restart service to apply.',!!j?.ok)}
async function logout(){await api('/api/logout',{method:'POST',body:'{}'});location.href='/login'}
refresh();setInterval(refresh,3000);
</script></body></html>
"""

class Handler(BaseHTTPRequestHandler):
    server_version = "tor-ml-panel/4.3.1"
    def log_message(self, fmt, *args):
        if args and "api/status" in str(args[0]): return
        super().log_message(fmt, *args)
    def _conf(self): return load_panel_conf()
    def _token(self):
        for part in self.headers.get("Cookie","").split(";"):
            part=part.strip()
            if part.startswith("tml_sess="): return part.split("=",1)[1].strip()
        return None
    def _authed(self): return valid_session(self._token())
    def _send(self, code, body, content_type="text/html; charset=utf-8", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if headers:
            for k,v in headers.items(): self.send_header(k,v)
        self.end_headers(); self.wfile.write(body)
    def _json(self, code, obj):
        self._send(code, json.dumps(obj).encode(), "application/json; charset=utf-8")
    def _read_json(self):
        n=int(self.headers.get("Content-Length") or 0)
        if n<=0: return {}
        try: return json.loads(self.rfile.read(n).decode() or "{}")
        except Exception: return {}
    def do_GET(self):
        path=urlparse(self.path).path; conf=self._conf()
        if path=="/setup":
            if conf.get("setup_done"):
                self.send_response(302); self.send_header("Location","/login"); self.end_headers(); return
            self._send(200, SETUP_HTML.replace("{err}","").encode()); return
        if path=="/login":
            if not conf.get("setup_done"):
                self.send_response(302); self.send_header("Location","/setup"); self.end_headers(); return
            self._send(200, LOGIN_HTML.replace("{err}","").encode()); return
        if path in ("/","/index.html"):
            if not conf.get("setup_done"):
                self.send_response(302); self.send_header("Location","/setup"); self.end_headers(); return
            if not self._authed():
                self.send_response(302); self.send_header("Location","/login"); self.end_headers(); return
            self._send(200, APP_HTML.encode()); return
        if path=="/api/status":
            if not self._authed(): self._json(401,{"ok":False}); return
            data=status_json(); data["ok"]=True
            data["panel"]={"host":conf.get("host","0.0.0.0"),"port":conf.get("port",8080)}
            self._json(200, data); return
        if path=="/api/log":
            if not self._authed(): self._json(401,{"ok":False}); return
            qs=parse_qs(urlparse(self.path).query); lid=(qs.get("id") or [""])[0]
            code,out,err=run_cli("--json-log", lid, timeout=20)
            if code==0 and out.strip():
                try: self._json(200, json.loads(out)); return
                except Exception: pass
            self._json(200,{"ok":True,"log":out or err or "(empty)"}); return
        self._send(404,b"Not found")
    def do_POST(self):
        path=urlparse(self.path).path; conf=self._conf()
        if path=="/setup":
            if conf.get("setup_done"):
                self.send_response(302); self.send_header("Location","/login"); self.end_headers(); return
            n=int(self.headers.get("Content-Length") or 0)
            form=parse_qs(self.rfile.read(n).decode(errors="replace"))
            user=(form.get("username") or ["admin"])[0].strip()
            pw=(form.get("password") or [""])[0]; pw2=(form.get("password2") or [""])[0]
            host=(form.get("host") or ["0.0.0.0"])[0].strip() or "0.0.0.0"
            try: port=int((form.get("port") or ["8080"])[0])
            except Exception: port=0
            err=""
            if len(user)<3: err="Username too short"
            elif len(pw)<6: err="Password min 6 chars"
            elif pw!=pw2: err="Passwords do not match"
            elif port<1 or port>65535: err="Invalid port"
            if err:
                self._send(400, SETUP_HTML.replace("{err}", f'<p style="color:#f87171">{err}</p>').encode()); return
            conf.update({"username":user,"password_hash":hash_password(pw),"host":host,"port":port,"setup_done":True})
            conf.setdefault("session_secret", secrets.token_hex(32))
            save_panel_conf(conf)
            msg=f'<p style="color:#86efac">Saved. Open login. If port is {port}, run: systemctl restart tor-ml-web</p><p><a class="btn primary" href="/login">Go to login</a></p>'
            self._send(200, SETUP_HTML.replace("{err}", msg).encode()); return
        if path=="/login":
            if not conf.get("setup_done"):
                self.send_response(302); self.send_header("Location","/setup"); self.end_headers(); return
            n=int(self.headers.get("Content-Length") or 0)
            form=parse_qs(self.rfile.read(n).decode(errors="replace"))
            user=(form.get("username") or [""])[0]; pw=(form.get("password") or [""])[0]
            if user==conf.get("username") and verify_password(pw, conf.get("password_hash","")):
                token=make_session()
                self.send_response(302); self.send_header("Location","/")
                self.send_header("Set-Cookie", f"tml_sess={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_TTL}")
                self.end_headers(); return
            self._send(401, LOGIN_HTML.replace("{err}",'<p style="color:#f87171">Invalid credentials</p>').encode()); return
        if path=="/api/logout":
            tok=self._token()
            if tok: SESSIONS.pop(tok, None)
            self._json(200,{"ok":True}); return
        if path=="/api/action":
            if not self._authed(): self._json(401,{"ok":False}); return
            body=self._read_json(); self._json(200, handle_action(body.get("action") or "", body)); return
        self._send(404,b"Not found")

def handle_action(action: str, body: dict) -> dict:
    if action=="start":
        c,o,e=run_cli("--start", str(body.get("id") or ""), timeout=90); return {"ok":c==0,"message":(o or e).strip() or "started"}
    if action=="stop":
        c,o,e=run_cli("--stop", str(body.get("id") or ""), timeout=30); return {"ok":c==0,"message":(o or e).strip() or "stopped"}
    if action=="start-all-tor": run_cli("--start-all-tor", timeout=300); return {"ok":True,"message":"Started all Tor"}
    if action=="start-all-psi": run_cli("--start-all-psi", timeout=300); return {"ok":True,"message":"Started all Psiphon"}
    if action=="stop-all": run_cli("--stop-all", timeout=60); return {"ok":True,"message":"All stopped"}
    if action=="balancer-start":
        c,o,e=run_cli("--balancer-start", timeout=90); return {"ok":c==0,"message":(o or e).strip() or "balancer started"}
    if action=="balancer-stop": run_cli("--balancer-stop", timeout=30); return {"ok":True,"message":"balancer stopped"}
    if action=="mode-weak": run_cli("--set-mode","weak"); return {"ok":True,"message":"WEAK"}
    if action=="mode-normal": run_cli("--set-mode","normal"); return {"ok":True,"message":"NORMAL"}
    if action=="mode-max": run_cli("--set-mode","max"); return {"ok":True,"message":"MAXIMUM"}
    if action=="sticky-on": run_cli("--sticky","on"); return {"ok":True,"message":"Sticky on"}
    if action=="sticky-off": run_cli("--sticky","off"); return {"ok":True,"message":"Sticky off"}
    if action=="speed-test":
        c,o,e=run_cli("--speed-test", timeout=180); return {"ok":True,"output":o or e,"message":"test done"}
    if action=="ping-test":
        c,o,e=run_cli("--ping-test", timeout=120); return {"ok":True,"output":o or e,"message":"ping done"}
    if action=="ping-one":
        c,o,e=run_cli("--ping-one", str(body.get("id") or ""), timeout=40); return {"ok":c==0,"output":o or e,"message":"ping done"}
    if action=="change-port":
        c,o,e=run_cli("--change-port", str(body.get("id")), str(body.get("port")), timeout=30); return {"ok":c==0,"message":(o or e).strip() or "port updated"}
    if action=="set-password":
        pw=str(body.get("password") or "")
        if len(pw)<6: return {"ok":False,"message":"min 6 chars"}
        conf=load_panel_conf(); conf["password_hash"]=hash_password(pw); conf["setup_done"]=True; save_panel_conf(conf)
        return {"ok":True,"message":"Password updated"}
    if action=="set-bind":
        conf=load_panel_conf(); host=str(body.get("host") or "0.0.0.0").strip() or "0.0.0.0"
        try: port=int(body.get("port") or conf.get("port") or 8080)
        except Exception: return {"ok":False,"message":"Invalid port"}
        if port<1 or port>65535: return {"ok":False,"message":"Invalid port"}
        conf["host"]=host; conf["port"]=port; save_panel_conf(conf)
        return {"ok":True,"message":f"Bind saved {host}:{port}"}
    return {"ok":False,"message":f"Unknown action: {action}"}

def main():
    conf=load_panel_conf()
    if not PANEL_CONF.exists():
        conf["setup_done"]=False; save_panel_conf(conf)
    host=conf.get("host") or "0.0.0.0"; port=int(conf.get("port") or 8080)
    print(f"[tor-ml-panel 4.3.1] http://{host}:{port} setup_done={conf.get('setup_done')}", flush=True)
    ThreadingHTTPServer((host, port), Handler).serve_forever()

if __name__ == "__main__":
    main()
