#!/usr/bin/env bash
# =============================================================================
# tor-ml v4.4  –  Multi Tor + Psiphon Manager + Web Panel 1.1
# Full production script: CLI menu, JSON API for web, balancer, perf modes,
# sticky exit, bandwidth, logs, port change, watchdog, SSL-ready install,
# complete uninstall. Optimized for low-end VPS, works on Ubuntu 20/22/24.
# =============================================================================
set -euo pipefail

VERSION="4.4"
PANEL_VER="1.1"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
M='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'
OR='\033[1;38;5;208m'; PK='\033[1;38;5;205m'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE="/opt/tor-ml"
CFG="$BASE/config"
DAT="$BASE/data"
LOG="$BASE/logs"
STA="$BASE/status"
BIN="$BASE/bin"
WEB="$BASE/web"
CMD="/usr/local/bin/tor"
SETTINGS="$CFG/settings.db"
PERF_FILE="$CFG/perf.mode"
PANEL_JSON="$CFG/panel.json"
TOKEN_FILE="$CFG/api.token"
AUTO_PORT=49000
AUTO_PID_FILE="$STA/auto.pid"
AUTO_TARGET_FILE="$STA/auto.target"
WATCHDOG_PID_FILE="$STA/watchdog.pid"
PSI_BIN="$BIN/psiphon-tunnel-core"
SELF_SCRIPT="$BASE/tor-ml.sh"

# ---------------------------------------------------------------------------
# Tor locations  ID -> CC:Name:default_port
# ---------------------------------------------------------------------------
declare -A TOR_LOC=(
  [T01]="DE:Germany:48180"
  [T02]="US:United States:48181"
  [T03]="NL:Netherlands:48182"
  [T04]="FR:France:48183"
  [T05]="GB:United Kingdom:48184"
  [T06]="CA:Canada:48185"
  [T07]="SG:Singapore:48186"
  [T08]="JP:Japan:48187"
  [T09]="SE:Sweden:48188"
  [T10]="CH:Switzerland:48189"
  [T11]="AT:Austria:48190"
  [T12]="BE:Belgium:48191"
  [T13]="PL:Poland:48192"
  [T14]="IT:Italy:48193"
  [T15]="ES:Spain:48194"
  [T16]="NO:Norway:48195"
  [T17]="DK:Denmark:48196"
  [T18]="FI:Finland:48197"
  [T19]="IE:Ireland:48198"
  [T20]="AU:Australia:48199"
  [T21]="BR:Brazil:48200"
  [T22]="IN:India:48201"
  [T23]="KR:South Korea:48202"
  [T24]="HK:Hong Kong:48203"
  [T25]="TR:Turkey:48204"
  [T26]="RO:Romania:48205"
  [T27]="CZ:Czech Republic:48206"
  [T28]="PT:Portugal:48207"
  [T29]="UA:Ukraine:48208"
  [T30]="MX:Mexico:48209"
  [T31]="AR:Argentina:48210"
  [T32]="CL:Chile:48211"
  [T33]="ZA:South Africa:48212"
  [T34]="IL:Israel:48213"
  [T35]="AE:United Arab Emirates:48214"
  [T36]="TH:Thailand:48215"
  [T37]="MY:Malaysia:48216"
  [T38]="ID:Indonesia:48217"
  [T39]="PH:Philippines:48218"
  [T40]="NZ:New Zealand:48219"
  [T41]="HU:Hungary:48220"
  [T42]="GR:Greece:48221"
  [T43]="BG:Bulgaria:48222"
  [T44]="HR:Croatia:48223"
  [T45]="SK:Slovakia:48224"
  [T46]="SI:Slovenia:48225"
  [T47]="LT:Lithuania:48226"
  [T48]="LV:Latvia:48227"
  [T49]="EE:Estonia:48228"
  [T50]="IS:Iceland:48229"
  [T51]="LU:Luxembourg:48230"
  [T52]="MD:Moldova:48231"
  [T53]="RS:Serbia:48232"
  [T54]="TW:Taiwan:48233"
  [T55]="VN:Vietnam:48234"
  [T56]="CR:Costa Rica:48235"
  [T57]="PA:Panama:48236"
  [T58]="CO:Colombia:48237"
  [T59]="PE:Peru:48238"
  [T60]="NG:Nigeria:48239"
)
TOR_ORDER=()
for __i in $(seq -w 1 60); do TOR_ORDER+=("T${__i}"); done

# Psiphon egress regions
declare -A PSI_LOC=(
  [P01]="DE:Germany:49100"
  [P02]="US:United States:49101"
  [P03]="NL:Netherlands:49102"
  [P04]="GB:United Kingdom:49103"
  [P05]="FR:France:49104"
  [P06]="CA:Canada:49105"
  [P07]="SG:Singapore:49106"
  [P08]="JP:Japan:49107"
  [P09]="AU:Australia:49108"
  [P10]="SE:Sweden:49109"
  [P11]="CH:Switzerland:49110"
  [P12]="AT:Austria:49111"
  [P13]="BE:Belgium:49112"
  [P14]="PL:Poland:49113"
  [P15]="IT:Italy:49114"
  [P16]="ES:Spain:49115"
  [P17]="RO:Romania:49116"
  [P18]="NO:Norway:49120"
  [P19]="IE:Ireland:49121"
  [P20]="IN:India:49122"
  [P21]="BR:Brazil:49123"
  [P22]="HK:Hong Kong:49124"
  [P23]="KR:South Korea:49125"
  [P24]="MX:Mexico:49126"
  [P25]="TR:Turkey:49127"
  [P26]="ZA:South Africa:49128"
  [P27]="AR:Argentina:49129"
  [P28]="DK:Denmark:49130"
)
PSI_ORDER=()
for __i in $(seq -w 1 28); do PSI_ORDER+=("P${__i}"); done

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------
need_root() {
  [[ ${EUID:-0} -eq 0 ]] || { echo -e "${R}[!] Run as root (sudo su)${N}"; exit 1; }
}

init_dirs() {
  mkdir -p "$CFG" "$DAT" "$LOG" "$STA" "$BIN" "$WEB"
  touch "$SETTINGS"
  [[ -f "$PERF_FILE" ]] || echo "normal" > "$PERF_FILE"
  if [[ ! -f "$TOKEN_FILE" ]]; then
    tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 48 > "$TOKEN_FILE" || openssl rand -hex 24 > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
  fi
}

api_token() { cat "$TOKEN_FILE" 2>/dev/null || echo ""; }

line() { echo -e "${D}──────────────────────────────────────────────────────────────${N}"; }

pause() { read -rp "$(echo -e "  ${D}Press Enter...${N}")" _; }

# ---------------------------------------------------------------------------
# Performance mode (fixes load_perf: command not found)
# ---------------------------------------------------------------------------
load_perf() {
  local m
  m=$(cat "$PERF_FILE" 2>/dev/null || echo normal)
  case "$m" in
    weak|normal|max) printf '%s' "$m" ;;
    *) printf '%s' "normal" ;;
  esac
}

save_perf() {
  local m=${1:-normal}
  case "$m" in
    weak|1) echo weak > "$PERF_FILE" ;;
    max|3|maximum) echo max > "$PERF_FILE" ;;
    *) echo normal > "$PERF_FILE" ;;
  esac
}

perf_tor_extra() {
  case "$(load_perf)" in
    weak)
      cat <<'EOF'
MaxMemInQueues 16 MB
NumEntryGuards 1
CircuitBuildTimeout 20
MaxClientCircuitsPending 2
KeepalivePeriod 60
NewCircuitPeriod 90
MaxCircuitDirtiness 900
EOF
      ;;
    max)
      cat <<'EOF'
MaxMemInQueues 64 MB
NumEntryGuards 3
CircuitBuildTimeout 12
MaxClientCircuitsPending 8
KeepalivePeriod 30
NewCircuitPeriod 45
MaxCircuitDirtiness 400
EOF
      ;;
    *)
      cat <<'EOF'
MaxMemInQueues 32 MB
NumEntryGuards 2
CircuitBuildTimeout 15
MaxClientCircuitsPending 4
KeepalivePeriod 45
NewCircuitPeriod 60
MaxCircuitDirtiness 600
EOF
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Settings DB  id:port:bw:uptime:sticky
# ---------------------------------------------------------------------------
get_setting() {
  local id=$1 field=$2 line
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)
  if [[ -n "${line:-}" ]]; then
    IFS=':' read -r _ port bw uptime sticky <<< "$line"
    case "$field" in
      port)      echo "${port:-0}" ;;
      bandwidth) echo "${bw:-0}" ;;
      uptime)    echo "${uptime:-0}" ;;
      sticky)    echo "${sticky:-0}" ;;
      *)         echo 0 ;;
    esac
  else
    echo 0
  fi
}

set_setting() {
  local id=$1 field=$2 value=$3
  local line port=0 bw=0 uptime=0 sticky=0
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)
  if [[ -n "${line:-}" ]]; then
    IFS=':' read -r _ port bw uptime sticky <<< "$line"
  fi
  case "$field" in
    port)      port=$value ;;
    bandwidth) bw=$value ;;
    uptime)    uptime=$value ;;
    sticky)    sticky=$value ;;
  esac
  sed -i "/^${id}:/d" "$SETTINGS" 2>/dev/null || true
  echo "${id}:${port}:${bw}:${uptime}:${sticky}" >> "$SETTINGS"
}

# ---------------------------------------------------------------------------
# Parse location info
# ---------------------------------------------------------------------------
parse_tor() {
  local id=$1
  [[ -n ${TOR_LOC[$id]+x} ]] || return 1
  local code name port custom
  IFS=':' read -r code name port <<< "${TOR_LOC[$id]}"
  custom=$(get_setting "$id" port)
  [[ "$custom" != "0" && -n "$custom" ]] && port=$custom
  echo "${code}|${name}|${port}"
}

parse_psi() {
  local id=$1
  [[ -n ${PSI_LOC[$id]+x} ]] || return 1
  local code name port custom
  IFS=':' read -r code name port <<< "${PSI_LOC[$id]}"
  custom=$(get_setting "$id" port)
  [[ "$custom" != "0" && -n "$custom" ]] && port=$custom
  echo "${code}|${name}|${port}"
}

resolve_id() {
  # Accept t01, T01, 01 (tor), p01, P01
  local raw=${1^^}
  raw=${raw// /}
  if [[ "$raw" =~ ^T[0-9]{2}$ ]]; then echo "$raw"; return 0; fi
  if [[ "$raw" =~ ^P[0-9]{2}$ ]]; then echo "$raw"; return 0; fi
  if [[ "$raw" =~ ^[0-9]{1,2}$ ]]; then printf 'T%02d' "$((10#$raw))"; return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
# Process detection
# ---------------------------------------------------------------------------
running_tor() {
  local code=$1 port=$2
  pgrep -f "tor -f ${CFG}/node_${code}_${port}\\.conf" >/dev/null 2>&1 \
    || pgrep -f "tor -f ${CFG}/node_${code}_${port}.conf" >/dev/null 2>&1
}

running_psi() {
  local code=$1 port=$2
  local pf="$STA/psi_${code}_${port}.pid"
  if pgrep -f "psiphon-tunnel-core" >/dev/null 2>&1; then
    if pgrep -f "psiphon-tunnel-core.*${port}" >/dev/null 2>&1; then
      return 0
    fi
    # fallback: pid file + live process
    if [[ -f "$pf" ]]; then
      local pid; pid=$(cat "$pf" 2>/dev/null || true)
      if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
      fi
    fi
  fi
  if [[ -f "$pf" ]]; then
    local pid; pid=$(cat "$pf" 2>/dev/null || true)
    [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  # port open as last resort
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -q ":${port} " && pgrep -f psiphon-tunnel-core >/dev/null 2>&1 && return 0
  fi
  return 1
}

tor_pid() {
  local code=$1 port=$2
  pgrep -f "node_${code}_${port}.conf" 2>/dev/null | head -1 || true
}

psi_pid() {
  local code=$1 port=$2
  local pf="$STA/psi_${code}_${port}.pid"
  if [[ -f "$pf" ]]; then
    local pid; pid=$(cat "$pf" 2>/dev/null || true)
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return
    fi
  fi
  pgrep -f "psiphon-tunnel-core.*${port}" 2>/dev/null | head -1 || true
}

node_cpu_mem() {
  local pid=$1
  [[ -z "${pid:-}" ]] && { echo "0.0 0.0"; return; }
  ps -p "$pid" -o %cpu=,%mem= --no-headers 2>/dev/null \
    | awk '{printf "%.1f %.1f", $1+0, $2+0}' || echo "0.0 0.0"
}

global_stats() {
  local cpu=0 mem=0 cnt=0 p
  while read -r p; do
    [[ -z "$p" ]] && continue
    local c m
    read -r c m <<< "$(node_cpu_mem "$p")"
    cpu=$(awk -v a="$cpu" -v b="${c:-0}" 'BEGIN{printf "%.1f", a+b}')
    mem=$(awk -v a="$mem" -v b="${m:-0}" 'BEGIN{printf "%.1f", a+b}')
    cnt=$((cnt + 1))
  done < <( {
      pgrep -f "tor -f ${CFG}/node_" 2>/dev/null || true
      pgrep -f "psiphon-tunnel-core" 2>/dev/null || true
    } )
  printf "%.1f %.1f %d" "$cpu" "$mem" "$cnt"
}

format_uptime() {
  local start=${1:-0}
  [[ "$start" == "0" || -z "$start" ]] && { echo "--"; return; }
  local now diff
  now=$(date +%s)
  diff=$((now - start))
  (( diff < 0 )) && { echo "--"; return; }
  if   (( diff < 60 ));    then echo "${diff}s"
  elif (( diff < 3600 ));  then echo "$((diff/60))m $((diff%60))s"
  elif (( diff < 86400 )); then echo "$((diff/3600))h $(((diff%3600)/60))m"
  else echo "$((diff/86400))d $(((diff%86400)/3600))h"
  fi
}

# ---------------------------------------------------------------------------
# Config writers
# ---------------------------------------------------------------------------
write_tor_conf() {
  local code=$1 port=$2 dir=$3 logfile=$4 bw=$5 sticky=$6
  local extra
  extra=$(perf_tor_extra)
  cat > "$CFG/node_${code}_${port}.conf" <<EOF
# tor-ml ${VERSION} – generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
SocksPort 127.0.0.1:${port} IsolateDestAddr IsolateDestPort
DataDirectory ${dir}
ExitNodes {${code}}
StrictNodes 1
ClientOnly 1
RunAsDaemon 1
Log notice file ${logfile}
AvoidDiskWrites 1
${extra}
LearnCircuitBuildTimeout 0
DisableDebuggerAttachment 1
DirReqStatistics 0
EntryStatistics 0
ExitPortStatistics 0
ConnDirectionStatistics 0
ExtraInfoStatistics 0
CellStatistics 0
ClientUseIPv6 0
SocksPolicy accept 127.0.0.1
SocksPolicy reject *
$([[ "${sticky}" == "1" ]] && echo "EnforceDistinctSubnets 0")
EOF
  if [[ "${bw}" != "0" && -n "${bw}" ]]; then
    {
      echo "BandwidthRate ${bw} MB"
      echo "BandwidthBurst $((bw * 2)) MB"
    } >> "$CFG/node_${code}_${port}.conf"
  fi
  chown debian-tor:debian-tor "$CFG/node_${code}_${port}.conf" 2>/dev/null || true
  chmod 600 "$CFG/node_${code}_${port}.conf" 2>/dev/null || true
}

write_psi_conf() {
  local code=$1 port=$2 dir=$3
  local http=$((port + 1000))
  # Official-style config fields used by current tunnel-core
  cat > "$CFG/psi_${code}_${port}.json" <<EOF
{
  "LocalSocksProxyPort": ${port},
  "LocalHttpProxyPort": ${http},
  "EgressRegion": "${code}",
  "PropagationChannelId": "FFFFFFFFFFFFFFFF",
  "SponsorId": "FFFFFFFFFFFFFFFF",
  "DataRootDirectory": "${dir}",
  "UseIndistinguishableTLS": true,
  "EmitDiagnosticNotices": true,
  "ClientPlatform": "Linux",
  "DisableLocalSocksAuth": true,
  "DisableLocalHTTPProxy": false,
  "EstablishTunnelTimeoutSeconds": 120,
  "TunnelPoolSize": 2,
  "ConnectionWorkerPoolSize": 10,
  "RemoteServerListURLs": [
    {
      "URL": "https://s3.amazonaws.com/psiphon/web/mjr4-p23r-puwl/server_list_compressed",
      "SkipVerify": false
    }
  ],
  "RemoteServerListDownloadFilename": "remote_server_list",
  "RemoteServerListSignaturePublicKey": "MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodUeWEDu5YOV0oJj1uRvvRAsGLQmRQ2SX9SJarUX+8pUWw4T2cOIyGSF91klRM0fU70jN4NVrrJrVNi+NizAsXZ4mY5g8xW2R+k8x6ZQCEBQAwEAAQ=="
}
EOF
}

# ---------------------------------------------------------------------------
# Start / Stop single
# ---------------------------------------------------------------------------
start_tor_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(parse_tor "$id")" || { echo -e "  ${R}✗${N} bad Tor id $id"; return 1; }
  local conf="$CFG/node_${code}_${port}.conf"
  local dir="$DAT/${code}_${port}"
  local logfile="$LOG/${code}_${port}.log"
  local bw sticky
  bw=$(get_setting "$id" bandwidth)
  sticky=$(get_setting "$id" sticky)

  mkdir -p "$dir" "$LOG"
  chown -R debian-tor:debian-tor "$dir" 2>/dev/null || true
  chmod 700 "$dir" 2>/dev/null || true
  write_tor_conf "$code" "$port" "$dir" "$logfile" "$bw" "$sticky"

  if running_tor "$code" "$port"; then
    echo -e "  ${Y}•${N} Tor ${name} [${code}] already running on ${port}"
    return 0
  fi

  pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
  sleep 0.2
  : > "$logfile"
  chown debian-tor:debian-tor "$logfile" 2>/dev/null || true

  if ! sudo -u debian-tor /usr/bin/tor -f "$conf" >/dev/null 2>&1; then
    echo -e "  ${R}✗${N} Tor ${name} failed to start"
    [[ -s "$logfile" ]] && tail -n 5 "$logfile" | sed 's/^/    /'
    return 1
  fi

  local i=0
  while ! running_tor "$code" "$port" && (( i < 20 )); do
    sleep 0.25
    i=$((i + 1))
  done

  if running_tor "$code" "$port"; then
    set_setting "$id" uptime "$(date +%s)"
    echo -e "  ${G}✓${N} Tor ${W}${name}${N} [${code}] → SOCKS ${W}${port}${N}"
    return 0
  fi
  echo -e "  ${R}✗${N} Tor ${name} start timeout"
  [[ -s "$logfile" ]] && tail -n 6 "$logfile" | sed 's/^/    /'
  return 1
}

stop_tor_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(parse_tor "$id")" || return 1
  if ! running_tor "$code" "$port"; then
    echo -e "  ${Y}•${N} Tor ${name} not running"
    set_setting "$id" uptime 0
    return 0
  fi
  pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
  sleep 0.25
  if running_tor "$code" "$port"; then
    pkill -9 -f "node_${code}_${port}.conf" 2>/dev/null || true
  fi
  set_setting "$id" uptime 0
  rm -f "$STA/${code}_${port}.ip"
  echo -e "  ${G}✓${N} Tor ${name} stopped"
}

start_psi_one() {
  local id=$1
  if [[ ! -x "$PSI_BIN" ]]; then
    echo -e "  ${R}✗${N} Psiphon binary missing at $PSI_BIN"
    echo -e "    Re-run install or download manually."
    return 1
  fi
  local code name port
  IFS='|' read -r code name port <<< "$(parse_psi "$id")" || { echo -e "  ${R}✗${N} bad Psi id $id"; return 1; }
  local dir="$DAT/psi_${code}_${port}"
  local conf="$CFG/psi_${code}_${port}.json"
  local logfile="$LOG/psi_${code}_${port}.log"
  local pf="$STA/psi_${code}_${port}.pid"

  mkdir -p "$dir" "$LOG"
  write_psi_conf "$code" "$port" "$dir"

  if running_psi "$code" "$port"; then
    echo -e "  ${Y}•${N} Psi ${name} [${code}] already running on ${port}"
    return 0
  fi

  # cleanup stale
  if [[ -f "$pf" ]]; then
    kill "$(cat "$pf")" 2>/dev/null || true
    rm -f "$pf"
  fi
  pkill -f "psiphon-tunnel-core.*${port}" 2>/dev/null || true
  sleep 0.2
  : > "$logfile"

  nohup "$PSI_BIN" -config "$conf" >>"$logfile" 2>&1 &
  local pid=$!
  echo "$pid" > "$pf"

  local i=0
  while ! running_psi "$code" "$port" && (( i < 30 )); do
    sleep 0.3
    i=$((i + 1))
    # process died?
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
  done

  if running_psi "$code" "$port"; then
    set_setting "$id" uptime "$(date +%s)"
    echo -e "  ${G}✓${N} Psi ${W}${name}${N} [${code}] → SOCKS ${W}${port}${N}"
    return 0
  fi
  echo -e "  ${R}✗${N} Psi ${name} failed (check log)"
  [[ -s "$logfile" ]] && tail -n 8 "$logfile" | sed 's/^/    /'
  return 1
}

stop_psi_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(parse_psi "$id")" || return 1
  local pf="$STA/psi_${code}_${port}.pid"
  if [[ -f "$pf" ]]; then
    local pid; pid=$(cat "$pf" 2>/dev/null || true)
    [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
    sleep 0.2
    [[ -n "${pid:-}" ]] && kill -9 "$pid" 2>/dev/null || true
    rm -f "$pf"
  fi
  pkill -f "psiphon-tunnel-core.*${port}" 2>/dev/null || true
  set_setting "$id" uptime 0
  echo -e "  ${G}✓${N} Psi ${name} stopped"
}

start_one() {
  local id
  id=$(resolve_id "$1") || { echo -e "  ${R}✗${N} unknown id $1"; return 1; }
  case "$id" in
    T*) start_tor_one "$id" ;;
    P*) start_psi_one "$id" ;;
  esac
}

stop_one() {
  local id
  id=$(resolve_id "$1") || { echo -e "  ${R}✗${N} unknown id $1"; return 1; }
  case "$id" in
    T*) stop_tor_one "$id" ;;
    P*) stop_psi_one "$id" ;;
  esac
}

start_all_tor() {
  local id
  echo -e "  ${C}Starting all Tor locations...${N}"
  for id in "${TOR_ORDER[@]}"; do
    start_tor_one "$id" || true
  done
}

start_all_psi() {
  local id
  echo -e "  ${C}Starting all Psiphon locations...${N}"
  for id in "${PSI_ORDER[@]}"; do
    start_psi_one "$id" || true
  done
}

stop_all() {
  local id
  echo -e "  ${Y}Stopping everything...${N}"
  for id in "${TOR_ORDER[@]}"; do stop_tor_one "$id" || true; done
  for id in "${PSI_ORDER[@]}"; do stop_psi_one "$id" || true; done
  auto_stop || true
}

# ---------------------------------------------------------------------------
# Balancer
# ---------------------------------------------------------------------------
balancer_active() {
  [[ -f "$AUTO_PID_FILE" ]] || return 1
  local pid; pid=$(cat "$AUTO_PID_FILE" 2>/dev/null || true)
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

auto_stop() {
  if [[ -f "$AUTO_PID_FILE" ]]; then
    kill "$(cat "$AUTO_PID_FILE")" 2>/dev/null || true
    sleep 0.2
    kill -9 "$(cat "$AUTO_PID_FILE")" 2>/dev/null || true
    rm -f "$AUTO_PID_FILE"
  fi
  pkill -f "socat TCP-LISTEN:${AUTO_PORT}" 2>/dev/null || true
  rm -f "$AUTO_TARGET_FILE"
  echo -e "  ${G}✓${N} Balancer stopped"
}

pick_best_port() {
  local best_port="" best_ms=999999 id code name port ms
  for id in "${TOR_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    running_tor "$code" "$port" || continue
    ms=$(curl --socks5-hostname "127.0.0.1:${port}" -o /dev/null -s -w "%{time_total}" --max-time 5 \
      https://1.1.1.1/cdn-cgi/trace 2>/dev/null || echo 99)
    ms=$(awk -v t="$ms" 'BEGIN{printf "%d", (t+0)*1000}')
    if (( ms > 0 && ms < best_ms )); then
      best_ms=$ms
      best_port=$port
    fi
  done
  for id in "${PSI_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    running_psi "$code" "$port" || continue
    ms=$(curl --socks5-hostname "127.0.0.1:${port}" -o /dev/null -s -w "%{time_total}" --max-time 5 \
      https://1.1.1.1/cdn-cgi/trace 2>/dev/null || echo 99)
    ms=$(awk -v t="$ms" 'BEGIN{printf "%d", (t+0)*1000}')
    if (( ms > 0 && ms < best_ms )); then
      best_ms=$ms
      best_port=$port
    fi
  done
  echo "${best_port}"
}

auto_start() {
  command -v socat >/dev/null 2>&1 || { echo -e "  ${R}✗${N} socat not installed"; return 1; }
  auto_stop >/dev/null 2>&1 || true
  local target
  target=$(pick_best_port)
  if [[ -z "${target}" ]]; then
    echo -e "  ${R}✗${N} No running Tor/Psiphon instance – start some locations first"
    return 1
  fi
  nohup socat TCP-LISTEN:${AUTO_PORT},fork,reuseaddr,bind=127.0.0.1 TCP:127.0.0.1:${target} >/dev/null 2>&1 &
  echo $! > "$AUTO_PID_FILE"
  echo "$target" > "$AUTO_TARGET_FILE"
  echo -e "  ${G}✓${N} Balancer listening ${W}:${AUTO_PORT}${N} → backend ${W}:${target}${N}"
}

# ---------------------------------------------------------------------------
# JSON status for web panel (must list ALL locations)
# ---------------------------------------------------------------------------
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1" 2>/dev/null \
    || echo "\"$1\""
}

json_status() {
  init_dirs
  local cpu mem cnt mode
  read -r cpu mem cnt <<< "$(global_stats)"
  mode=$(load_perf)
  local bal=false bport=$AUTO_PORT btarget=""
  if balancer_active; then
    bal=true
    btarget=$(cat "$AUTO_TARGET_FILE" 2>/dev/null || echo "")
  fi

  echo -n '{'
  echo -n '"ok":true,'
  echo -n '"version":"'"$VERSION"'",'
  echo -n '"panel":"'"$PANEL_VER"'",'
  echo -n '"cpu":'"$cpu"','
  echo -n '"mem":'"$mem"','
  echo -n '"running_count":'"$cnt"','
  echo -n '"mode":"'"$mode"'",'
  echo -n '"balancer":{"active":'"$bal"',"port":'"$bport"',"target":"'"$btarget"'"},'
  echo -n '"locations":['

  local first=1 id code name port st cpu1 mem1 pid up

  for id in "${TOR_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    st=false; cpu1="0.0"; mem1="0.0"; pid=""; up=$(get_setting "$id" uptime)
    if running_tor "$code" "$port"; then
      st=true
      pid=$(tor_pid "$code" "$port")
      read -r cpu1 mem1 <<< "$(node_cpu_mem "$pid")"
    fi
    [[ $first -eq 1 ]] || echo -n ','
    first=0
    printf '{"id":"%s","type":"tor","cc":"%s","name":"%s","port":%s,"running":%s,"cpu":%s,"mem":%s,"uptime":%s,"sticky":%s,"bandwidth":%s}' \
      "$id" "$code" "$name" "$port" "$st" "$cpu1" "$mem1" "${up:-0}" \
      "$(get_setting "$id" sticky)" "$(get_setting "$id" bandwidth)"
  done

  for id in "${PSI_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    st=false; cpu1="0.0"; mem1="0.0"; pid=""; up=$(get_setting "$id" uptime)
    if running_psi "$code" "$port"; then
      st=true
      pid=$(psi_pid "$code" "$port")
      read -r cpu1 mem1 <<< "$(node_cpu_mem "$pid")"
    fi
    [[ $first -eq 1 ]] || echo -n ','
    first=0
    printf '{"id":"%s","type":"psi","cc":"%s","name":"%s","port":%s,"running":%s,"cpu":%s,"mem":%s,"uptime":%s,"sticky":0,"bandwidth":0}' \
      "$id" "$code" "$name" "$port" "$st" "$cpu1" "$mem1" "${up:-0}"
  done

  echo ']}'
}

ping_one() {
  local raw=$1 id code name port
  id=$(resolve_id "$raw") || { echo '{"ok":false,"error":"bad id"}'; return 1; }
  if [[ "$id" == T* ]]; then
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    running_tor "$code" "$port" || { echo '{"id":"'"$id"'","ok":false,"error":"not running"}'; return 0; }
  else
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    running_psi "$code" "$port" || { echo '{"id":"'"$id"'","ok":false,"error":"not running"}'; return 0; }
  fi
  local t ip
  t=$(curl --socks5-hostname "127.0.0.1:${port}" -o /dev/null -s -w "%{time_total}" --max-time 10 \
    https://1.1.1.1/cdn-cgi/trace 2>/dev/null || echo 0)
  ip=$(curl --socks5-hostname "127.0.0.1:${port}" -s --max-time 8 https://api.ipify.org 2>/dev/null || echo "?")
  printf '{"id":"%s","ok":true,"latency":%s,"ip":"%s","port":%s,"name":"%s"}\n' \
    "$id" "$t" "$ip" "$port" "$name"
}

# ---------------------------------------------------------------------------
# Logs / port / bandwidth / sticky
# ---------------------------------------------------------------------------
view_log() {
  local id code name port logfile
  id=$(resolve_id "$1") || return 1
  if [[ "$id" == T* ]]; then
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    logfile="$LOG/${code}_${port}.log"
  else
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    logfile="$LOG/psi_${code}_${port}.log"
  fi
  echo -e "  ${C}Log: ${logfile}${N}"
  line
  if [[ -f "$logfile" ]]; then
    tail -n 40 "$logfile"
  else
    echo "  (empty)"
  fi
}

change_port() {
  local id newport code name port
  id=$(resolve_id "$1") || return 1
  newport=$2
  [[ "$newport" =~ ^[0-9]+$ ]] || { echo "bad port"; return 1; }
  stop_one "$id" || true
  set_setting "$id" port "$newport"
  echo -e "  ${G}✓${N} $id port → $newport (start again to apply)"
}

set_bw() {
  local id bw
  id=$(resolve_id "$1") || return 1
  bw=$2
  set_setting "$id" bandwidth "$bw"
  echo -e "  ${G}✓${N} $id bandwidth=${bw} MB (restart instance to apply)"
}

toggle_sticky() {
  local id cur
  id=$(resolve_id "$1") || return 1
  [[ "$id" == T* ]] || { echo "sticky only for Tor"; return 1; }
  cur=$(get_setting "$id" sticky)
  if [[ "$cur" == "1" ]]; then
    set_setting "$id" sticky 0
    echo -e "  ${Y}sticky OFF${N} for $id"
  else
    set_setting "$id" sticky 1
    echo -e "  ${G}sticky ON${N} for $id"
  fi
}

# ---------------------------------------------------------------------------
# Install helpers
# ---------------------------------------------------------------------------
download_psiphon() {
  mkdir -p "$BIN"
  if [[ -x "$PSI_BIN" ]]; then
    echo -e "  ${G}✓${N} Psiphon binary present"
    return 0
  fi
  echo "  ↓ Downloading psiphon-tunnel-core (x86_64)..."
  local urls=(
    "https://github.com/Psiphon-Labs/psiphon-tunnel-core-binaries/raw/master/linux/psiphon-tunnel-core-x86_64"
    "https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/linux/psiphon-tunnel-core-x86_64"
  )
  local u ok=0
  for u in "${urls[@]}"; do
    if curl -fsSL --connect-timeout 15 --max-time 180 "$u" -o "$PSI_BIN"; then
      chmod +x "$PSI_BIN"
      ok=1
      break
    fi
  done
  if [[ $ok -eq 1 ]]; then
    echo -e "  ${G}✓${N} Psiphon binary ready"
  else
    echo -e "  ${Y}!${N} Psiphon download failed – Tor features still work"
  fi
}

install_web_files() {
  mkdir -p "$WEB"
  local self dir candidates
  self=$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "$0")
  dir=$(dirname "$self")
  candidates=(
    "$dir/web/panel.py"
    "/root/web/panel.py"
    "/root/panel.py"
    "$WEB/panel.py"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" && -s "$c" ]]; then
      # skip if file is GitHub 404 page
      if head -1 "$c" | grep -q '404: Not Found'; then
        continue
      fi
      if head -1 "$c" | grep -q python; then
        cp -f "$c" "$WEB/panel.py"
        chmod +x "$WEB/panel.py"
        echo -e "  ${G}✓${N} panel.py → $WEB/panel.py"
        return 0
      fi
    fi
  done
  echo -e "  ${Y}!${N} panel.py not found – place it at $WEB/panel.py then: systemctl restart tor-ml-web"
  return 1
}

write_web_service() {
  local tok
  tok=$(api_token)
  cat > /etc/systemd/system/tor-ml-web.service <<EOF
[Unit]
Description=tor-ml Web Control Panel ${PANEL_VER}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=TOR_ML_BASE=${BASE}
Environment=TOR_ML_CLI=${CMD}
Environment=TOR_ML_TOKEN=${tok}
ExecStart=/usr/bin/python3 ${WEB}/panel.py
Restart=always
RestartSec=2
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable tor-ml-web.service
  systemctl restart tor-ml-web.service
}

setup_ssl() {
  local domain=$1
  [[ -n "$domain" ]] || return 0
  echo -e "  ${C}Configuring HTTPS for ${domain}...${N}"
  apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null 2>&1 || true
  local pport
  pport=$(python3 -c "import json;print(json.load(open('${PANEL_JSON}')).get('port',8080))" 2>/dev/null || echo 8080)
  cat > /etc/nginx/sites-available/tor-ml-panel <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${pport};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/tor-ml-panel /etc/nginx/sites-enabled/tor-ml-panel
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx -t 2>/dev/null && systemctl reload nginx || true
  if certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null; then
    echo -e "  ${G}✓${N} HTTPS ready: https://${domain}"
  else
    echo -e "  ${Y}!${N} certbot failed (DNS A record must point here). HTTP proxy still on :80 → panel"
  fi
}

install() {
  need_root
  # IMPORTANT: no clear during install (user complained about wiped terminal)
  echo
  echo -e "  ${C}${W}████  tor-ml v${VERSION}  –  Full Installer${N}"
  echo -e "  ${D}════════════════════════════════════════════════${N}"

  if [[ -d "$BASE" ]]; then
    echo -e "  ${Y}Existing install detected at $BASE${N}"
    read -rp "  Remove previous install and continue? [y/N]: " ans
    if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
      systemctl stop tor-ml-web 2>/dev/null || true
      pkill -f "psiphon-tunnel-core" 2>/dev/null || true
      pkill -f "tor -f ${CFG}/node_" 2>/dev/null || true
      rm -rf "$BASE"
    else
      echo "  Aborted."
      exit 0
    fi
  fi

  export DEBIAN_FRONTEND=noninteractive
  echo -e "  [1/8] apt update..."
  apt-get update -qq
  echo -e "  [2/8] packages: tor curl socat netcat python3..."
  apt-get install -y -qq tor curl socat python3 ca-certificates >/dev/null
  apt-get install -y -qq netcat-openbsd 2>/dev/null || apt-get install -y -qq netcat 2>/dev/null || true
  echo -e "  [3/8] debian-tor user..."
  id debian-tor >/dev/null 2>&1 || useradd --system --home /var/lib/tor --shell /usr/sbin/nologin debian-tor 2>/dev/null || true
  echo -e "  [4/8] directories + token..."
  init_dirs
  echo -e "  [5/8] install CLI → ${CMD}"
  local src
  src=$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "$0")
  cp -f "$src" "$CMD"
  cp -f "$src" "$SELF_SCRIPT"
  chmod +x "$CMD" "$SELF_SCRIPT"
  echo -e "  [6/8] Psiphon binary..."
  download_psiphon
  echo -e "  [7/8] Web panel files..."
  install_web_files || true

  echo -e "  ${C}Admin & panel settings${N}"
  local user pass port host domain
  read -rp "  Username [admin]: " user; user=${user:-admin}
  read -rp "  Password [admin123]: " pass; pass=${pass:-admin123}
  read -rp "  Panel port [8080]: " port; port=${port:-8080}
  read -rp "  Bind host [0.0.0.0]: " host; host=${host:-0.0.0.0}
  read -rp "  Domain for auto-HTTPS (empty = IP only): " domain

  python3 - <<PY
import json, hashlib, secrets, os
SALT = "tor-ml-v4.4"
def hp(pw):
    return hashlib.pbkdf2_hmac("sha256", pw.encode(), SALT.encode(), 120_000).hex()
tok = ""
if os.path.exists("${TOKEN_FILE}"):
    tok = open("${TOKEN_FILE}").read().strip()
cfg = {
    "username": """${user}""",
    "password_hash": hp("""${pass}"""),
    "host": """${host}""",
    "port": int("""${port}"""),
    "session_secret": secrets.token_hex(32),
    "setup_done": True,
    "api_token": tok,
    "panel_version": "${PANEL_VER}",
}
open("${PANEL_JSON}", "w").write(json.dumps(cfg, indent=2))
print("  panel.json written")
PY
  chmod 600 "$PANEL_JSON"

  echo -e "  [8/8] systemd web service..."
  if [[ -f "$WEB/panel.py" ]]; then
    write_web_service
  else
    echo -e "  ${Y}!${N} skipping web service (no panel.py)"
  fi

  if [[ -n "${domain}" ]]; then
    setup_ssl "$domain"
  fi

  echo -e "  ${D}════════════════════════════════════════════════${N}"
  echo -e "  ${G}✓ Installation complete – v${VERSION} / panel ${PANEL_VER}${N}"
  echo -e "  CLI:   ${W}tor${N}"
  echo -e "  Web:   ${W}http://SERVER_IP:${port}${N}   user=${user}"
  [[ -n "${domain}" ]] && echo -e "  HTTPS: ${W}https://${domain}${N}"
  echo -e "  Open AWS Security Group for port ${port} (and 80/443 if domain)."
  echo
}

uninstall() {
  need_root
  echo -e "  ${R}Full uninstall...${N}"
  stop_all 2>/dev/null || true
  systemctl disable --now tor-ml-web.service 2>/dev/null || true
  rm -f /etc/systemd/system/tor-ml-web.service
  systemctl daemon-reload 2>/dev/null || true
  pkill -f "psiphon-tunnel-core" 2>/dev/null || true
  pkill -f "tor -f ${CFG}/node_" 2>/dev/null || true
  pkill -f "${WEB}/panel.py" 2>/dev/null || true
  pkill -f "socat TCP-LISTEN:${AUTO_PORT}" 2>/dev/null || true
  rm -f "$CMD" /usr/local/bin/tor-ml
  rm -rf "$BASE"
  rm -f /etc/nginx/sites-enabled/tor-ml-panel /etc/nginx/sites-available/tor-ml-panel
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  echo -e "  ${G}✓ Everything related to tor-ml removed${N}"
}

# ---------------------------------------------------------------------------
# Terminal UI
# ---------------------------------------------------------------------------
header() {
  clear
  local cpu mem cnt mode
  read -r cpu mem cnt <<< "$(global_stats)"
  mode=$(load_perf)
  local bal="off"
  balancer_active && bal="ON :${AUTO_PORT}"
  echo
  echo -e "  ${C}${W}████  tor-ml  v${VERSION}${N}  ${D}• Panel ${PANEL_VER}${N}"
  echo -e "  ${D}══════════════════════════════════════════════════════════════${N}"
  echo -e "  ${G}●${N} Running ${W}${cnt}${N}  |  CPU ${OR}${cpu}%${N}  |  MEM ${OR}${mem}%${N}  |  Mode ${Y}${mode^^}${N}"
  echo -e "  ${G}●${N} Path    ${W}${BASE}${N}"
  echo -e "  ${G}●${N} Balance ${W}${bal}${N}"
  echo -e "  ${D}──────────────────────────────────────────────────────────────${N}"
  echo -e "  ${D}Tor + Psiphon multi-exit  •  web panel sync  •  low-end VPS${N}"
  echo -e "  ${D}──────────────────────────────────────────────────────────────${N}"
}

status_screen() {
  header
  printf "  ${W}%-5s %-4s %-4s %-20s %-6s %-8s %s${N}\n" ID TYPE CC NAME PORT STATE UPTIME
  line
  local id code name port up
  for id in "${TOR_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    up=$(format_uptime "$(get_setting "$id" uptime)")
    if running_tor "$code" "$port"; then
      printf "  %-5s %-4s %-4s %-20s %-6s ${G}%-8s${N} %s\n" "$id" TOR "$code" "$name" "$port" ON "$up"
    else
      printf "  %-5s %-4s %-4s %-20s %-6s ${D}%-8s${N} %s\n" "$id" TOR "$code" "$name" "$port" off "--"
    fi
  done
  line
  for id in "${PSI_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    up=$(format_uptime "$(get_setting "$id" uptime)")
    if running_psi "$code" "$port"; then
      printf "  %-5s %-4s %-4s %-20s %-6s ${G}%-8s${N} %s\n" "$id" PSI "$code" "$name" "$port" ON "$up"
    else
      printf "  %-5s %-4s %-4s %-20s %-6s ${D}%-8s${N} %s\n" "$id" PSI "$code" "$name" "$port" off "--"
    fi
  done
}

speed_screen() {
  header
  echo -e "  ${C}Latency test (running instances via Cloudflare)${N}"
  line
  local id code name port
  for id in "${TOR_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_tor "$id")"
    running_tor "$code" "$port" || continue
    echo -n "  Tor  ${name}  "
    ping_one "$id"
  done
  for id in "${PSI_ORDER[@]}"; do
    IFS='|' read -r code name port <<< "$(parse_psi "$id")"
    running_psi "$code" "$port" || continue
    echo -n "  Psi  ${name}  "
    ping_one "$id"
  done
}

main_menu() {
  while true; do
    header
    echo -e "  ${C}[1]${N}  Full status"
    echo -e "  ${C}[2]${N}  Start location(s)"
    echo -e "  ${C}[3]${N}  Stop location(s)"
    echo -e "  ${C}[4]${N}  Start all Tor"
    echo -e "  ${C}[5]${N}  Start all Psiphon"
    echo -e "  ${C}[6]${N}  Stop all"
    echo -e "  ${C}[7]${N}  Change port"
    echo -e "  ${C}[8]${N}  Speed / latency test"
    echo -e "  ${C}[9]${N}  View log"
    echo -e "  ${C}[10]${N} Set bandwidth (MB)"
    echo -e "  ${C}[11]${N} Toggle sticky exit (Tor)"
    echo -e "  ${C}[12]${N} Balancer start"
    echo -e "  ${C}[13]${N} Balancer stop"
    echo -e "  ${C}[14]${N} Performance mode (weak/normal/max)"
    echo -e "  ${R}[15]${N} Uninstall"
    echo -e "  ${Y}[0]${N}  Exit"
    echo
    read -rp "$(echo -e "  ${M}Select: ${N}")" choice
    case "$choice" in
      1) status_screen; pause ;;
      2)
        status_screen
        read -rp "  Start ID(s) e.g. T01 P03: " ids
        for x in $ids; do start_one "$x" || true; done
        pause
        ;;
      3)
        read -rp "  Stop ID(s): " ids
        for x in $ids; do stop_one "$x" || true; done
        pause
        ;;
      4) start_all_tor; pause ;;
      5) start_all_psi; pause ;;
      6) stop_all; pause ;;
      7)
        read -rp "  ID: " id
        read -rp "  New port: " p
        change_port "$id" "$p"
        pause
        ;;
      8) speed_screen; pause ;;
      9)
        read -rp "  ID: " id
        view_log "$id"
        pause
        ;;
      10)
        read -rp "  ID: " id
        read -rp "  Bandwidth MB (0=unlimited): " bw
        set_bw "$id" "$bw"
        pause
        ;;
      11)
        read -rp "  Tor ID: " id
        toggle_sticky "$id"
        pause
        ;;
      12) auto_start; pause ;;
      13) auto_stop; pause ;;
      14)
        echo -e "  Current: ${Y}$(load_perf)${N}"
        echo "  1) weak  2) normal  3) max"
        read -rp "  Choice: " m
        case "$m" in 1) save_perf weak ;; 3) save_perf max ;; *) save_perf normal ;; esac
        echo -e "  ${G}✓${N} mode=$(load_perf)"
        pause
        ;;
      15)
        read -rp "  Type YES to uninstall: " x
        [[ "$x" == "YES" ]] && { uninstall; exit 0; }
        ;;
      0) clear; exit 0 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Entry / CLI API for web panel
# ---------------------------------------------------------------------------
case "${1:-}" in
  --install)   install; exit 0 ;;
  --uninstall) uninstall; exit 0 ;;
  --json-status)
    init_dirs
    json_status
    exit 0
    ;;
  --start)
    init_dirs
    shift
    for id in "$@"; do start_one "$id" || true; done
    exit 0
    ;;
  --stop)
    init_dirs
    shift
    for id in "$@"; do stop_one "$id" || true; done
    exit 0
    ;;
  --start-all-tor) init_dirs; start_all_tor; exit 0 ;;
  --start-all-psi) init_dirs; start_all_psi; exit 0 ;;
  --stop-all)      init_dirs; stop_all; exit 0 ;;
  --balancer-start) init_dirs; auto_start; exit 0 ;;
  --balancer-stop)  init_dirs; auto_stop; exit 0 ;;
  --mode)
    init_dirs
    save_perf "${2:-normal}"
    echo "{\"ok\":true,\"mode\":\"$(load_perf)\"}"
    exit 0
    ;;
  --ping)
    init_dirs
    ping_one "${2:-}"
    exit 0
    ;;
  --log)
    init_dirs
    view_log "${2:-}"
    exit 0
    ;;
  --version)
    echo "$VERSION"
    exit 0
    ;;
  --help|-h)
    cat <<EOF
tor-ml v${VERSION}
  tor                  interactive menu
  tor --install
  tor --uninstall
  tor --json-status
  tor --start T01 P01
  tor --stop T01
  tor --start-all-tor | --start-all-psi | --stop-all
  tor --balancer-start | --balancer-stop
  tor --mode weak|normal|max
  tor --ping T01
  tor --version
EOF
    exit 0
    ;;
esac

if [[ ! -d "$BASE" ]]; then
  echo -e "${Y}tor-ml is not installed.${N}"
  echo -e "Run: ${W}sudo bash $0 --install${N}"
  exit 1
fi

init_dirs
main_menu
