#!/usr/bin/env python3
# =============================================================================
# tor-ml Web Panel 1.1  –  English admin UI paired with CLI v4.4
# Live dashboard, full location tables, start/stop/ping, balancer, performance,
# session auth, actions executed on server via /usr/local/bin/tor
# =============================================================================
from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE = Path(os.environ.get("TOR_ML_BASE", "/opt/tor-ml"))
CFG = BASE / "config"
PANEL_CONF = CFG / "panel.json"
TOKEN_FILE = CFG / "api.token"
CLI = Path(os.environ.get("TOR_ML_CLI", "/usr/local/bin/tor"))
SALT = "tor-ml-v4.4"
SESSION_TTL = 86400 * 7
SESSIONS: dict[str, float] = {}
PANEL_VER = "1.1"


def hash_password(pw: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", pw.encode(), SALT.encode(), 120_000).hex()


def verify_password(pw: str, stored: str) -> bool:
    try:
        return hmac.compare_digest(hash_password(pw), stored)
    except Exception:
        return False


def load_panel_conf() -> dict:
    data = {
        "username": "admin",
        "password_hash": hash_password("admin123"),
        "host": "0.0.0.0",
        "port": 8080,
        "session_secret": secrets.token_hex(32),
        "setup_done": False,
        "api_token": "",
        "panel_version": PANEL_VER,
    }
    if PANEL_CONF.exists():
        try:
            data.update(json.loads(PANEL_CONF.read_text()))
        except Exception:
            pass
    if TOKEN_FILE.exists() and not data.get("api_token"):
        try:
            data["api_token"] = TOKEN_FILE.read_text().strip()
        except Exception:
            pass
    return data


def save_panel_conf(data: dict) -> None:
    CFG.mkdir(parents=True, exist_ok=True)
    PANEL_CONF.write_text(json.dumps(data, indent=2))
    try:
        os.chmod(PANEL_CONF, 0o600)
    except Exception:
        pass


def run_cli(*args: str, timeout: int = 300) -> tuple[int, str, str]:
    env = {**os.environ, "TERM": "dumb", "TOR_ML_BASE": str(BASE)}
    conf = load_panel_conf()
    if conf.get("api_token"):
        env["TOR_ML_TOKEN"] = str(conf["api_token"])
    try:
        p = subprocess.run(
            [str(CLI), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
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
        time.sleep(0.06)
        with open("/proc/stat") as f:
            parts = [float(x) for x in f.readline().split()[1:]]
        idle2, total2 = parts[3], sum(parts)
        di, dt = idle2 - idle1, total2 - total1
        if dt <= 0:
            return 0.0
        return round(max(0.0, min(100.0, (1.0 - di / dt) * 100)), 1)
    except Exception:
        return 0.0


def mem_percent() -> float:
    try:
        info: dict[str, float] = {}
        with open("/proc/meminfo") as f:
            for line in f:
                bits = line.replace(":", " ").split()
                if len(bits) >= 2 and bits[0] in ("MemTotal", "MemAvailable"):
                    info[bits[0]] = float(bits[1])
        if "MemTotal" in info and "MemAvailable" in info and info["MemTotal"] > 0:
            return round((info["MemTotal"] - info["MemAvailable"]) / info["MemTotal"] * 100, 1)
    except Exception:
        pass
    return 0.0


def status_json() -> dict:
    code, out, err = run_cli("--json-status", timeout=90)
    if code == 0 and out.strip():
        try:
            # take last JSON object if any noise
            text = out.strip()
            start = text.find("{")
            end = text.rfind("}")
            if start >= 0 and end > start:
                text = text[start : end + 1]
            data = json.loads(text)
            data.setdefault("cpu", cpu_percent())
            data.setdefault("mem", mem_percent())
            data["panel"] = PANEL_VER
            data["cli_ok"] = True
            return data
        except json.JSONDecodeError as e:
            return {
                "ok": False,
                "error": f"json parse: {e}; out={out[:300]}",
                "cpu": cpu_percent(),
                "mem": mem_percent(),
                "locations": [],
                "running_count": 0,
                "balancer": {"active": False, "port": 49000},
                "mode": "normal",
                "version": "?",
                "panel": PANEL_VER,
                "cli_ok": False,
            }
    return {
        "ok": False,
        "error": (err or out or "status failed")[:600],
        "cpu": cpu_percent(),
        "mem": mem_percent(),
        "locations": [],
        "running_count": 0,
        "balancer": {"active": False, "port": 49000},
        "mode": "normal",
        "version": "?",
        "panel": PANEL_VER,
        "cli_ok": False,
    }


def make_session() -> str:
    token = secrets.token_urlsafe(32)
    SESSIONS[token] = time.time() + SESSION_TTL
    return token


def valid_session(token: str | None) -> bool:
    if not token:
        return False
    exp = SESSIONS.get(token)
    if not exp or time.time() > exp:
        SESSIONS.pop(token, None)
        return False
    # sliding expiry
    SESSIONS[token] = time.time() + SESSION_TTL
    return True


CSS = r"""
:root{
  --bg:#070b14;--panel:#0f1624;--card:#151e30;--line:#243049;
  --text:#eaf0ff;--muted:#8fa0bf;--accent:#4f8cff;--ok:#22c55e;
  --warn:#f59e0b;--bad:#ef4444;--pink:#ec4899;--orange:#f97316
}
*{box-sizing:border-box}
body{margin:0;font-family:Inter,system-ui,Segoe UI,sans-serif;color:var(--text);min-height:100vh;
background:radial-gradient(1000px 500px at 0% -10%,#1d4ed833,transparent),
radial-gradient(900px 500px at 100% 0%,#7e22ce22,transparent),var(--bg)}
body::before{content:"";position:fixed;inset:0;pointer-events:none;
background-image:linear-gradient(rgba(255,255,255,.015) 1px,transparent 1px),
linear-gradient(90deg,rgba(255,255,255,.015) 1px,transparent 1px);background-size:40px 40px;
animation:gridMove 28s linear infinite}
@keyframes gridMove{to{background-position:40px 40px}}
@keyframes fadeUp{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes shimmer{0%{background-position:-200% 0}100%{background-position:200% 0}}
.wrap{position:relative;z-index:1;max-width:1320px;margin:0 auto;padding:18px}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;
padding:12px 16px;border:1px solid var(--line);border-radius:16px;margin-bottom:16px;
background:linear-gradient(180deg,#121a2bcc,#0d1422cc);backdrop-filter:blur(10px);animation:fadeUp .45s ease both}
.brand{display:flex;align-items:center;gap:10px;font-weight:700}
.brand .dot{width:11px;height:11px;border-radius:50%;background:var(--ok);animation:pulse 1.6s infinite}
.nav{display:flex;gap:7px;flex-wrap:wrap}
.nav button,.btn{background:var(--card);color:var(--text);border:1px solid var(--line);border-radius:11px;
padding:8px 12px;cursor:pointer;font-size:13px;transition:transform .15s,border-color .15s}
.nav button:hover,.btn:hover{border-color:var(--accent);transform:translateY(-1px)}
.btn.primary{background:linear-gradient(135deg,#2563eb,#7c3aed);border:none}
.btn.ok{background:#14532d;border-color:#166534}.btn.bad{background:#7f1d1d;border-color:#991b1b}
.btn.warn{background:#78350f;border-color:#92400e}.btn.pink{background:#9d174d;border-color:#be185d}
.btn:disabled{opacity:.55;cursor:wait}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:14px}
@media(max-width:960px){.grid{grid-template-columns:repeat(2,1fr)}}
.card,.section{background:linear-gradient(180deg,#152036,#101827);border:1px solid var(--line);
border-radius:16px;animation:fadeUp .5s ease both}
.card{padding:14px 16px;position:relative;overflow:hidden}
.card::after{content:"";position:absolute;inset:0;pointer-events:none;
background:linear-gradient(110deg,transparent 20%,rgba(255,255,255,.04) 45%,transparent 70%);
background-size:200% 100%;animation:shimmer 4.5s linear infinite}
.card .k{color:var(--muted);font-size:11px;letter-spacing:.7px;text-transform:uppercase}
.card .v{font-size:24px;font-weight:700;margin-top:6px}
.section{padding:14px;margin-bottom:14px}
.section h2{margin:0 0 12px;font-size:14px;color:var(--muted);font-weight:600}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:9px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:middle}
th{color:var(--muted);font-size:11px;position:sticky;top:0;background:#101827}
.table-wrap{max-height:520px;overflow:auto;border-radius:12px}
.badge{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:700}
.badge.on{background:#14532d;color:#86efac}.badge.off{background:#27272a;color:#a1a1aa}
.badge.tor{background:#0c4a6e;color:#7dd3fc}.badge.psi{background:#4c1d95;color:#e9d5ff}
.row-actions{display:flex;gap:6px;flex-wrap:wrap}
.login-box,.setup-box{max-width:440px;margin:9vh auto;padding:28px;
background:linear-gradient(180deg,#152036,#0f172a);border:1px solid var(--line);border-radius:18px;
box-shadow:0 20px 60px #0008;animation:fadeUp .5s ease both}
.login-box h1,.setup-box h1{margin:0 0 6px;font-size:22px}
.login-box p,.setup-box p{color:var(--muted);margin:0 0 16px;font-size:13px}
input,select{width:100%;background:#0b1220;border:1px solid var(--line);color:var(--text);
border-radius:11px;padding:11px 12px;margin-bottom:10px;font-size:14px}
input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px #3b82f633}
.toast{position:fixed;right:16px;bottom:16px;z-index:60;min-width:220px;max-width:420px;
background:#0b1220;border:1px solid var(--line);border-radius:12px;padding:12px 14px;display:none;
animation:fadeUp .25s ease both;white-space:pre-wrap;font-size:13px}
.muted{color:var(--muted)}.flex{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.bar{height:8px;background:#1f2937;border-radius:99px;overflow:hidden;margin-top:8px}
.bar>i{display:block;height:100%;width:0;transition:width .6s ease;background:linear-gradient(90deg,#22c55e,#eab308,#ef4444)}
.live-tag{font-size:11px;color:#86efac}
.err{color:#fca5a5;font-size:13px;margin-top:8px}
.search{max-width:280px;margin-bottom:10px}
.pill{font-size:11px;padding:2px 8px;border-radius:999px;background:#1e293b;color:#94a3b8}
"""

SETUP_HTML = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tor-ml Setup</title><style>""" + CSS + """</style></head><body>
<div class="setup-box"><h1>First-time setup</h1>
<p>Create admin account and bind settings for the control panel.</p>
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
<p>Manage Tor &amp; Psiphon · Web Panel """ + PANEL_VER + """</p>
<form method="POST" action="/login">
<input name="username" placeholder="Username" autocomplete="username" required>
<input name="password" type="password" placeholder="Password" autocomplete="current-password" required>
<button class="btn primary" style="width:100%;padding:12px" type="submit">Sign in</button>
</form>{err}</div></body></html>"""

APP_HTML = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tor-ml Control Panel</title><style>""" + CSS + """</style></head><body>
<div class="wrap">
  <div class="top">
    <div class="brand"><span class="dot" id="liveDot"></span> tor-ml
      <span class="muted" id="ver"></span>
      <span class="live-tag" id="liveTag">● live</span>
      <span class="pill" id="cliPill">CLI</span>
    </div>
    <div class="nav">
      <button type="button" onclick="show('dash')">Dashboard</button>
      <button type="button" onclick="show('locs')">Locations</button>
      <button type="button" onclick="show('bal')">Balancer</button>
      <button type="button" onclick="show('perf')">Performance</button>
      <button type="button" onclick="show('tools')">Tools</button>
      <button type="button" onclick="logout()">Logout</button>
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
        <button class="btn ok" type="button" onclick="act('start-all-tor')">Start all Tor</button>
        <button class="btn ok" type="button" onclick="act('start-all-psi')">Start all Psiphon</button>
        <button class="btn bad" type="button" onclick="act('stop-all')">Stop all</button>
        <button class="btn primary" type="button" onclick="act('balancer-start')">Start balancer</button>
        <button class="btn" type="button" onclick="act('balancer-stop')">Stop balancer</button>
        <button class="btn warn" type="button" onclick="refresh(true)">Refresh now</button>
      </div>
    </div>
    <div class="section"><h2>Active instances · live CPU / RAM</h2>
      <div id="activeTable"></div>
    </div>
  </div>

  <div id="view-locs" style="display:none">
    <div class="section">
      <h2>Filter</h2>
      <input class="search" id="q" placeholder="Search name / CC / ID..." oninput="render()">
      <div class="flex" style="margin-bottom:10px">
        <button class="btn" type="button" onclick="filterType('all')">All</button>
        <button class="btn" type="button" onclick="filterType('tor')">Tor only</button>
        <button class="btn" type="button" onclick="filterType('psi')">Psiphon only</button>
        <button class="btn" type="button" onclick="filterType('on')">Running only</button>
      </div>
    </div>
    <div class="section"><h2>Tor locations</h2><div id="torTable" class="table-wrap"></div></div>
    <div class="section"><h2>Psiphon locations</h2><div id="psiTable" class="table-wrap"></div></div>
  </div>

  <div id="view-bal" style="display:none">
    <div class="section"><h2>Balancer (best-ping → :49000)</h2>
      <p class="muted">Forwards local SOCKS :49000 to the lowest-latency running node (Tor or Psiphon).</p>
      <div class="flex">
        <button class="btn primary" type="button" onclick="act('balancer-start')">Start</button>
        <button class="btn bad" type="button" onclick="act('balancer-stop')">Stop</button>
      </div>
      <div id="balInfo" class="card" style="margin-top:12px"></div>
    </div>
  </div>

  <div id="view-perf" style="display:none">
    <div class="section"><h2>Performance mode</h2>
      <p class="muted">Weak = low CPU · Normal = recommended · Max = more circuits (higher CPU). Applies on next instance start.</p>
      <div class="flex">
        <button class="btn" type="button" onclick="act('mode-weak')">Weak</button>
        <button class="btn primary" type="button" onclick="act('mode-normal')">Normal</button>
        <button class="btn warn" type="button" onclick="act('mode-max')">Maximum</button>
      </div>
      <div id="perfInfo" class="card" style="margin-top:12px"></div>
    </div>
  </div>

  <div id="view-tools" style="display:none">
    <div class="section"><h2>Ping / latency (running nodes)</h2>
      <p class="muted">Uses Cloudflare + ipify through each SOCKS port.</p>
      <div id="toolsTable" class="table-wrap"></div>
      <div id="pingOut" class="card" style="margin-top:12px;display:none"></div>
    </div>
  </div>
</div>
<div class="toast" id="toast"></div>
<script>
let DATA = {locations: [], ok:true};
let FILTER = 'all';
let BUSY = false;

function toast(m, ok){
  const t = document.getElementById('toast');
  t.style.display = 'block';
  t.style.borderColor = (ok === false) ? '#991b1b' : '#243049';
  t.textContent = m;
  clearTimeout(window.__tt);
  window.__tt = setTimeout(()=>{ t.style.display='none'; }, 4200);
}
function show(n){
  ['dash','locs','bal','perf','tools'].forEach(v=>{
    const el = document.getElementById('view-'+v);
    if(el) el.style.display = (v===n) ? 'block' : 'none';
  });
}
function logout(){ fetch('/api/logout',{method:'POST'}).finally(()=> location.href='/login'); }
function esc(s){
  return String(s??'').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function filterType(t){ FILTER = t; render(); }
function matchFilter(loc){
  const q = (document.getElementById('q')?.value || '').trim().toLowerCase();
  if(FILTER === 'tor' && loc.type !== 'tor') return false;
  if(FILTER === 'psi' && loc.type !== 'psi') return false;
  if(FILTER === 'on' && !loc.running) return false;
  if(!q) return true;
  return (loc.id+' '+loc.cc+' '+loc.name+' '+loc.port).toLowerCase().includes(q);
}
function rowActions(loc){
  const id = loc.id;
  if(loc.running){
    return `<div class="row-actions">
      <button class="btn bad" type="button" onclick="act('stop','${id}')">Stop</button>
      <button class="btn" type="button" onclick="act('ping','${id}')">Ping</button>
    </div>`;
  }
  return `<div class="row-actions"><button class="btn ok" type="button" onclick="act('start','${id}')">Start</button></div>`;
}
function table(list){
  if(!list.length) return '<p class="muted">No rows</p>';
  let h = '<table><thead><tr><th>ID</th><th>Type</th><th>CC</th><th>Name</th><th>Port</th><th>State</th><th>CPU</th><th>RAM</th><th></th></tr></thead><tbody>';
  for(const loc of list){
    h += `<tr>
      <td><b>${esc(loc.id)}</b></td>
      <td><span class="badge ${loc.type==='tor'?'tor':'psi'}">${esc(loc.type)}</span></td>
      <td>${esc(loc.cc)}</td>
      <td>${esc(loc.name)}</td>
      <td>${esc(loc.port)}</td>
      <td><span class="badge ${loc.running?'on':'off'}">${loc.running?'ON':'off'}</span></td>
      <td>${loc.running ? esc(loc.cpu)+'%' : '—'}</td>
      <td>${loc.running ? esc(loc.mem)+'%' : '—'}</td>
      <td>${rowActions(loc)}</td>
    </tr>`;
  }
  return h + '</tbody></table>';
}
function render(){
  const d = DATA;
  document.getElementById('ver').textContent = 'v'+(d.version||'?')+' · panel '+(d.panel||'1.1');
  document.getElementById('s-run').textContent = d.running_count ?? 0;
  document.getElementById('s-cpu').textContent = (d.cpu ?? 0) + '%';
  document.getElementById('s-mem').textContent = (d.mem ?? 0) + '%';
  document.getElementById('b-cpu').style.width = Math.min(100, Number(d.cpu)||0) + '%';
  document.getElementById('b-mem').style.width = Math.min(100, Number(d.mem)||0) + '%';
  const bal = d.balancer || {};
  document.getElementById('s-mode').textContent = (d.mode||'normal') + (bal.active ? ' · BAL' : '');
  document.getElementById('cliPill').textContent = d.cli_ok === false ? 'CLI ERR' : 'CLI OK';
  document.getElementById('cliPill').style.color = d.cli_ok === false ? '#fca5a5' : '#86efac';
  document.getElementById('balInfo').innerHTML =
    `<div class="k">Status</div><div class="v">${bal.active ? 'ACTIVE' : 'off'}</div>
     <p class="muted">Listen port ${esc(bal.port||49000)} · backend target ${esc(bal.target||'—')}</p>`;
  document.getElementById('perfInfo').innerHTML =
    `<div class="k">Current mode</div><div class="v">${esc(d.mode||'normal')}</div>
     <p class="muted">Restart instances after changing mode for full effect.</p>`;
  const locs = (d.locations || []).filter(matchFilter);
  const tor = locs.filter(x => x.type === 'tor');
  const psi = locs.filter(x => x.type === 'psi');
  const active = (d.locations || []).filter(x => x.running);
  document.getElementById('torTable').innerHTML = table(tor);
  document.getElementById('psiTable').innerHTML = table(psi);
  document.getElementById('activeTable').innerHTML = active.length ? table(active) : '<p class="muted">No running instances — start from Locations</p>';
  document.getElementById('toolsTable').innerHTML = active.length ? table(active) : '<p class="muted">Start a location first, then use Ping</p>';
  if(d.ok === false && d.error){
    document.getElementById('liveTag').textContent = '● error';
    document.getElementById('liveTag').style.color = '#fca5a5';
  } else {
    document.getElementById('liveTag').textContent = '● live';
    document.getElementById('liveTag').style.color = '#86efac';
  }
}
async function refresh(manual){
  try{
    const r = await fetch('/api/status', {cache:'no-store'});
    if(r.status === 401){ location.href='/login'; return; }
    DATA = await r.json();
    render();
    if(manual) toast('Refreshed', true);
  }catch(e){
    toast('Status failed: '+e, false);
  }
}
async function act(action, id){
  if(BUSY){ toast('Wait for previous action…', false); return; }
  BUSY = true;
  toast('Working: '+action+(id?(' '+id):'')+' …');
  try{
    const r = await fetch('/api/action', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({action, id: id||''})
    });
    if(r.status === 401){ location.href='/login'; return; }
    const j = await r.json();
    if(!j.ok){
      toast((j.error || 'Failed').slice(0,500), false);
    } else {
      let msg = j.message || 'OK';
      if(action === 'ping'){
        try{
          const p = JSON.parse(j.message);
          msg = (p.id||id)+'  lat='+(p.latency||'?')+'s  ip='+(p.ip||'?');
          const box = document.getElementById('pingOut');
          box.style.display = 'block';
          box.textContent = msg;
        }catch(_e){}
      }
      toast(String(msg).slice(0,500), true);
    }
    await refresh(false);
  }catch(e){
    toast(String(e), false);
  }finally{
    BUSY = false;
  }
}
refresh(false);
setInterval(()=> refresh(false), 4000);
</script>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = f"tor-ml-panel/{PANEL_VER}"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        # keep journal clean; enable by uncommenting
        # sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))
        pass

    def _cookie_token(self) -> str | None:
        raw = self.headers.get("Cookie", "") or ""
        for part in raw.split(";"):
            part = part.strip()
            if part.startswith("session="):
                return part.split("=", 1)[1].strip()
        return None

    def _authed(self) -> bool:
        return valid_session(self._cookie_token())

    def _send(self, code: int, body: bytes, content_type: str = "text/html; charset=utf-8", extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("X-Panel-Version", PANEL_VER)
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _html(self, code: int, html: str, extra: dict | None = None) -> None:
        self._send(code, html.encode("utf-8"), extra=extra)

    def _json(self, code: int, obj: dict) -> None:
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _read_body(self) -> bytes:
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0:
            return b""
        return self.rfile.read(n)

    def _read_json(self) -> dict:
        raw = self._read_body()
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _read_form(self) -> dict:
        raw = self._read_body()
        try:
            q = parse_qs(raw.decode("utf-8"), keep_blank_values=True)
            return {k: (v[0] if v else "") for k, v in q.items()}
        except Exception:
            return {}

    def do_HEAD(self) -> None:
        # health / probes
        self._send(200, b"")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        conf = load_panel_conf()

        if path in ("/", "/index", "/index.html"):
            if not conf.get("setup_done"):
                self.send_response(302)
                self.send_header("Location", "/setup")
                self.end_headers()
                return
            if not self._authed():
                self.send_response(302)
                self.send_header("Location", "/login")
                self.end_headers()
                return
            self._html(200, APP_HTML)
            return

        if path == "/setup":
            if conf.get("setup_done"):
                self.send_response(302)
                self.send_header("Location", "/login")
                self.end_headers()
                return
            self._html(200, SETUP_HTML.replace("{err}", ""))
            return

        if path == "/login":
            if not conf.get("setup_done"):
                self.send_response(302)
                self.send_header("Location", "/setup")
                self.end_headers()
                return
            self._html(200, LOGIN_HTML.replace("{err}", ""))
            return

        if path == "/api/status":
            if not self._authed():
                self._json(401, {"ok": False, "error": "auth required"})
                return
            self._json(200, status_json())
            return

        if path == "/api/health":
            self._json(200, {"ok": True, "panel": PANEL_VER})
            return

        self._html(404, "<h1>404</h1><p>Not found</p>")

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        conf = load_panel_conf()

        if path == "/setup":
            form = self._read_form()
            if (form.get("password") or "") != (form.get("password2") or ""):
                self._html(400, SETUP_HTML.replace("{err}", '<p class="err">Passwords do not match</p>'))
                return
            if len(form.get("password") or "") < 6:
                self._html(400, SETUP_HTML.replace("{err}", '<p class="err">Password too short</p>'))
                return
            conf["username"] = (form.get("username") or "admin").strip()
            conf["password_hash"] = hash_password(form.get("password") or "admin123")
            try:
                conf["port"] = int(form.get("port") or 8080)
            except ValueError:
                conf["port"] = 8080
            conf["host"] = (form.get("host") or "0.0.0.0").strip()
            conf["setup_done"] = True
            conf["session_secret"] = secrets.token_hex(32)
            conf["panel_version"] = PANEL_VER
            save_panel_conf(conf)
            self.send_response(302)
            self.send_header("Location", "/login")
            self.end_headers()
            return

        if path == "/login":
            form = self._read_form()
            u = form.get("username") or ""
            p = form.get("password") or ""
            if u == conf.get("username") and verify_password(p, conf.get("password_hash") or ""):
                tok = make_session()
                self.send_response(302)
                self.send_header("Location", "/")
                self.send_header("Set-Cookie", f"session={tok}; Path=/; HttpOnly; SameSite=Lax")
                self.end_headers()
                return
            self._html(401, LOGIN_HTML.replace("{err}", '<p class="err">Invalid username or password</p>'))
            return

        if path == "/api/logout":
            tok = self._cookie_token()
            if tok:
                SESSIONS.pop(tok, None)
            self._json(200, {"ok": True})
            return

        if path == "/api/action":
            if not self._authed():
                self._json(401, {"ok": False, "error": "auth required"})
                return
            body = self._read_json()
            action = str(body.get("action") or "").strip()
            lid = str(body.get("id") or "").strip().upper()

            simple = {
                "start-all-tor": ["--start-all-tor"],
                "start-all-psi": ["--start-all-psi"],
                "stop-all": ["--stop-all"],
                "balancer-start": ["--balancer-start"],
                "balancer-stop": ["--balancer-stop"],
                "mode-weak": ["--mode", "weak"],
                "mode-normal": ["--mode", "normal"],
                "mode-max": ["--mode", "max"],
            }
            if action in simple:
                code, out, err = run_cli(*simple[action])
                ok = code == 0
                self._json(
                    200,
                    {
                        "ok": ok,
                        "message": (out or action)[:800],
                        "error": None if ok else (err or out or "failed")[:800],
                    },
                )
                return

            if action == "start" and lid:
                code, out, err = run_cli("--start", lid)
                ok = code == 0
                self._json(200, {"ok": ok, "message": (out or f"start {lid}")[:800], "error": None if ok else (err or out)[:800]})
                return

            if action == "stop" and lid:
                code, out, err = run_cli("--stop", lid)
                ok = code == 0
                self._json(200, {"ok": ok, "message": (out or f"stop {lid}")[:800], "error": None if ok else (err or out)[:800]})
                return

            if action == "ping" and lid:
                code, out, err = run_cli("--ping", lid, timeout=30)
                text = (out or "").strip()
                try:
                    data = json.loads(text[text.find("{") : text.rfind("}") + 1]) if "{" in text else {"ok": False, "error": text or err}
                except Exception:
                    data = {"ok": False, "error": text or err or "ping failed"}
                self._json(
                    200,
                    {
                        "ok": bool(data.get("ok")),
                        "message": json.dumps(data, ensure_ascii=False),
                        "error": data.get("error"),
                    },
                )
                return

            self._json(400, {"ok": False, "error": f"unknown action: {action}"})
            return

        self._html(404, "not found")


def main() -> None:
    conf = load_panel_conf()
    host = str(conf.get("host") or "0.0.0.0")
    try:
        port = int(conf.get("port") or 8080)
    except Exception:
        port = 8080
    print(f"[tor-ml-panel {PANEL_VER}] http://{host}:{port} setup_done={conf.get('setup_done')} cli={CLI}", flush=True)
    httpd = ThreadingHTTPServer((host, port), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
