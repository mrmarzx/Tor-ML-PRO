#!/usr/bin/env bash
# =============================================================================
#  tor-ml v4.2  –  Multi-Exit Tor + Psiphon Manager
#  Modern • Clean • Low-resource • Full featured
#  Author: mrmarzx  |  2026
#  Fix: install never clears screen, full visible progress
# =============================================================================
set -euo pipefail
shopt -s nullglob 2>/dev/null || true

VERSION="4.2.0"

# Colours
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
M='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'
OR='\033[1;38;5;208m'; PK='\033[1;38;5;205m'; CY='\033[1;38;5;51m'
LG='\033[1;38;5;118m'; LB='\033[1;38;5;39m'; LR='\033[1;38;5;196m'

# Paths
BASE="/opt/tor-ml"
CFG="$BASE/config"
DAT="$BASE/data"
LOG="$BASE/logs"
STA="$BASE/status"
BIN="$BASE/bin"
PSI="$BASE/psiphon"
CMD="/usr/local/bin/tor"
SETTINGS="$CFG/settings.db"
GLOBAL="$CFG/global.conf"
AUTO_PORT=49000
AUTO_PID_FILE="$STA/auto.pid"
PERF_MODE="normal"

# Tor Locations
declare -A TOR_LOC=(
  [01]="DE:Germany:48180"
  [02]="TR:Turkey:48181"
  [03]="US:United States:48182"
  [04]="FR:France:48183"
  [05]="AT:Austria:48184"
  [06]="BE:Belgium:48185"
  [07]="RO:Romania:48186"
  [08]="CA:Canada:48187"
  [09]="SG:Singapore:48188"
  [10]="JP:Japan:48189"
  [11]="IE:Ireland:48190"
  [12]="FI:Finland:48191"
  [13]="ES:Spain:48192"
  [14]="PL:Poland:48193"
  [15]="NL:Netherlands:48194"
  [16]="IT:Italy:48195"
  [17]="CH:Switzerland:48196"
  [18]="SE:Sweden:48197"
  [19]="NO:Norway:48198"
  [20]="DK:Denmark:48199"
  [21]="IS:Iceland:48200"
  [22]="AU:Australia:48201"
  [23]="IN:India:48202"
  [24]="HK:Hong Kong:48203"
  [25]="UA:Ukraine:48204"
  [26]="CZ:Czech Republic:48205"
  [27]="KR:South Korea:48206"
  [28]="ZA:South Africa:48207"
  [29]="MX:Mexico:48208"
  [30]="MY:Malaysia:48209"
  [31]="AZ:Azerbaijan:48210"
  [32]="CY:Cyprus:48211"
  [33]="GR:Greece:48212"
  [34]="PT:Portugal:48213"
  [35]="HU:Hungary:48214"
  [36]="LU:Luxembourg:48215"
  [37]="GB:United Kingdom:48216"
  [38]="AR:Argentina:48217"
  [39]="TW:Taiwan:48218"
  [40]="BG:Bulgaria:48219"
  [41]="IL:Israel:48220"
  [42]="MD:Moldova:48221"
  [43]="RU:Russia:48222"
  [44]="CL:Chile:48223"
  [45]="CR:Costa Rica:48224"
  [46]="VN:Vietnam:48225"
  [47]="ID:Indonesia:48226"
  [48]="SC:Seychelles:48227"
  [49]="HR:Croatia:48228"
  [50]="TN:Tunisia:48229"
  [51]="BR:Brazil:48230"
  [52]="TH:Thailand:48231"
  [53]="PH:Philippines:48232"
  [54]="NZ:New Zealand:48233"
  [55]="EE:Estonia:48234"
  [56]="LT:Lithuania:48235"
  [57]="LV:Latvia:48236"
  [58]="SK:Slovakia:48237"
  [59]="SI:Slovenia:48238"
  [60]="RS:Serbia:48239"
)
TOR_ORDER=({01..60})

# Psiphon Locations
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
  [P18]="CZ:Czechia:49117"
  [P19]="DK:Denmark:49118"
  [P20]="FI:Finland:49119"
  [P21]="NO:Norway:49120"
  [P22]="IE:Ireland:49121"
  [P23]="IN:India:49122"
  [P24]="BR:Brazil:49123"
  [P25]="RS:Serbia:49124"
  [P26]="ID:Indonesia:49125"
  [P27]="LT:Lithuania:49126"
  [P28]="KR:South Korea:49127"
)
PSI_ORDER=(P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26 P27 P28)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
need_root() {
  [[ $EUID -eq 0 ]] || { echo -e "${R}[!] Must run as root${N}"; exit 1; }
}

parse_id() {
  local raw=$1
  if [[ "$raw" =~ ^[Pp]([0-9]+)$ ]]; then
    printf "P%02d" "$((10#${BASH_REMATCH[1]}))"
  elif [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf "%02d" "$((10#$raw))"
  else
    echo ""
  fi
}

is_tor_id()   { [[ -n ${TOR_LOC[$1]+x} ]]; }
is_psi_id()   { [[ -n ${PSI_LOC[$1]+x} ]]; }

init_dirs() {
  mkdir -p "$CFG" "$DAT" "$LOG" "$STA" "$BIN" "$PSI"
  touch "$SETTINGS"
  [[ -f "$GLOBAL" ]] || echo "perf=normal" > "$GLOBAL"
}

load_global() {
  [[ -f "$GLOBAL" ]] || return
  source <(grep -E '^[a-zA-Z_]+=' "$GLOBAL" 2>/dev/null || true)
  PERF_MODE="${perf:-normal}"
}

save_global() {
  echo "perf=${PERF_MODE}" > "$GLOBAL"
}

get_setting() {
  local id=$1 field=$2
  local line
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)
  if [[ -n "$line" ]]; then
    IFS=':' read -r _ port bw uptime sticky typ <<< "$line"
    case "$field" in
      port)      echo "${port:-0}" ;;
      bandwidth) echo "${bw:-0}" ;;
      uptime)    echo "${uptime:-0}" ;;
      sticky)    echo "${sticky:-0}" ;;
      type)      echo "${typ:-tor}" ;;
    esac
  else
    echo "0"
  fi
}

set_setting() {
  local id=$1 field=$2 value=$3
  local line port bw uptime sticky typ
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)
  if [[ -n "$line" ]]; then
    IFS=':' read -r _ port bw uptime sticky typ <<< "$line"
  else
    if is_tor_id "$id"; then
      IFS=':' read -r _ _ port <<< "${TOR_LOC[$id]}"
      typ="tor"
    else
      IFS=':' read -r _ _ port <<< "${PSI_LOC[$id]}"
      typ="psi"
    fi
    bw=0; uptime=0; sticky=0
  fi
  case "$field" in
    port)      port="$value" ;;
    bandwidth) bw="$value" ;;
    uptime)    uptime="$value" ;;
    sticky)    sticky="$value" ;;
    type)      typ="$value" ;;
  esac
  sed -i "/^${id}:/d" "$SETTINGS" 2>/dev/null || true
  echo "${id}:${port}:${bw}:${uptime}:${sticky}:${typ}" >> "$SETTINGS"
}

migrate_settings() {
  for id in "${TOR_ORDER[@]}"; do
    grep -q "^${id}:" "$SETTINGS" 2>/dev/null && continue
    IFS=':' read -r _ _ port <<< "${TOR_LOC[$id]}"
    echo "${id}:${port}:0:0:0:tor" >> "$SETTINGS"
  done
  for id in "${PSI_ORDER[@]}"; do
    grep -q "^${id}:" "$SETTINGS" 2>/dev/null && continue
    IFS=':' read -r _ _ port <<< "${PSI_LOC[$id]}"
    echo "${id}:${port}:0:0:0:psi" >> "$SETTINGS"
  done
}

info() {
  local id=$1
  local code name port
  if is_tor_id "$id"; then
    IFS=':' read -r code name port <<< "${TOR_LOC[$id]}"
  elif is_psi_id "$id"; then
    IFS=':' read -r code name port <<< "${PSI_LOC[$id]}"
  else
    echo "??|Unknown|0"
    return
  fi
  local custom
  custom=$(get_setting "$id" "port")
  [[ "$custom" != "0" && -n "$custom" ]] && port="$custom"
  echo "${code}|${name}|${port}"
}

running_tor() {
  local code=$1 port=$2
  pgrep -f "tor -f $CFG/node_${code}_${port}.conf" >/dev/null 2>&1
}

running_psi() {
  local code=$1 port=$2
  if [[ -f "$STA/psi_${code}_${port}.pid" ]]; then
    local pid
    pid=$(cat "$STA/psi_${code}_${port}.pid" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    return 0
  fi
  return 1
}

running() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  if is_tor_id "$id"; then
    running_tor "$code" "$port"
  else
    running_psi "$code" "$port"
  fi
}

get_pid() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  if is_tor_id "$id"; then
    pgrep -f "node_${code}_${port}.conf" 2>/dev/null | head -1 || true
  else
    if [[ -f "$STA/psi_${code}_${port}.pid" ]]; then
      cat "$STA/psi_${code}_${port}.pid" 2>/dev/null || true
    else
      pgrep -f "psiphon-tunnel-core" 2>/dev/null | head -1 || true
    fi
  fi
}

list_running() {
  local out=()
  for id in "${TOR_ORDER[@]}" "${PSI_ORDER[@]}"; do
    running "$id" && out+=("$id")
  done
  echo "${out[*]}"
}

list_running_tor() {
  local out=()
  for id in "${TOR_ORDER[@]}"; do
    running "$id" && out+=("$id")
  done
  echo "${out[*]}"
}

list_running_psi() {
  local out=()
  for id in "${PSI_ORDER[@]}"; do
    running "$id" && out+=("$id")
  done
  echo "${out[*]}"
}

get_stats() {
  local cpu=0 mem=0 cnt=0
  local pids
  pids=$(pgrep -f "node_.*\.conf|psiphon-tunnel-core" 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      local c m
      read -r c m <<< "$(ps -p "$pid" -o %cpu=,%mem= --no-headers 2>/dev/null || echo "0 0")"
      cpu=$(awk -v a="$cpu" -v b="${c:-0}" 'BEGIN{printf "%.1f",a+b}')
      mem=$(awk -v a="$mem" -v b="${m:-0}" 'BEGIN{printf "%.1f",a+b}')
      cnt=$((cnt+1))
    done <<< "$pids"
  fi
  printf "%.1f %.1f %d" "$cpu" "$mem" "$cnt"
}

get_node_stats() {
  local pid=$1
  [[ -z "$pid" ]] && { echo "0.0 0.0"; return; }
  ps -p "$pid" -o %cpu=,%mem= --no-headers 2>/dev/null || echo "0.0 0.0"
}

check_bootstrap() {
  local logfile=$1 port=$2 typ=${3:-tor}
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "Active"
    return
  fi
  if [[ "$typ" == "tor" ]]; then
    if grep -q "Bootstrapped 100%" "$logfile" 2>/dev/null; then
      echo "Active"
    elif grep -q "Bootstrapped" "$logfile" 2>/dev/null; then
      echo "Connecting"
    else
      echo "Inactive"
    fi
  else
    if grep -qE "Tunnels|ListeningSocksProxyPort|Connected|established" "$logfile" 2>/dev/null; then
      echo "Active"
    elif [[ -s "$logfile" ]]; then
      echo "Connecting"
    else
      echo "Inactive"
    fi
  fi
}

get_ip() {
  local port=$1 code=$2
  local ip_file="$STA/${code}_${port}.ip"
  if [[ -f "$ip_file" ]] && [[ $(find "$ip_file" -mmin -20 2>/dev/null) ]]; then
    cat "$ip_file"
    return
  fi
  local ip
  ip=$(curl --socks5-hostname "127.0.0.1:$port" -s --max-time 5 \
       https://api.ipify.org 2>/dev/null || echo "?")
  echo "$ip" > "$ip_file"
  echo "$ip"
}

format_uptime() {
  local start=$1
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

line()  { echo -e "${D}──────────────────────────────────────────────────────────────${N}"; }
line2() { echo -e "${D}══════════════════════════════════════════════════════════════${N}"; }

get_perf_params() {
  case "$PERF_MODE" in
    weak)
      echo "MaxMemInQueues 16 MB
NumEntryGuards 1
CircuitBuildTimeout 20
MaxClientCircuitsPending 2
KeepalivePeriod 60
NewCircuitPeriod 90
MaxCircuitDirtiness 900
NumCPUs 1"
      ;;
    max)
      echo "MaxMemInQueues 64 MB
NumEntryGuards 3
CircuitBuildTimeout 12
MaxClientCircuitsPending 8
KeepalivePeriod 30
NewCircuitPeriod 40
MaxCircuitDirtiness 400
NumCPUs 0"
      ;;
    *)
      echo "MaxMemInQueues 32 MB
NumEntryGuards 2
CircuitBuildTimeout 15
MaxClientCircuitsPending 4
KeepalivePeriod 45
NewCircuitPeriod 60
MaxCircuitDirtiness 600
NumCPUs 1"
      ;;
  esac
}

# Header is ONLY for interactive menu – NEVER used in install
header() {
  clear
  load_global
  local cpu mem cnt
  read -r cpu mem cnt <<< "$(get_stats)"
  local mode_col
  case "$PERF_MODE" in
    weak)   mode_col="${LG}WEAK${N}" ;;
    max)    mode_col="${LR}MAX${N}" ;;
    *)      mode_col="${CY}NORMAL${N}" ;;
  esac
  echo
  echo -e "  ${LB}████${N}  ${W}tor-ml${N}  ${PK}v${VERSION}${N}  ${D}• Multi Tor + Psiphon Manager${N}"
  line2
  echo -e "  ${G}●${N} Running  ${W}${cnt}${N}   ${D}|${N}  CPU ${OR}${cpu}%${N}   ${D}|${N}  MEM ${OR}${mem}%${N}   ${D}|${N}  Mode ${mode_col}"
  echo -e "  ${C}●${N} Config   ${D}$BASE${N}"
  echo -e "  ${M}●${N} Auto     ${W}${AUTO_PORT}${N}  ${D}(best-ping / balancer)${N}"
  line
  echo -e "  ${D}Optimized for low-end VPS  •  modern UI  •  Tor + Psiphon${N}"
  line
  echo
}

write_tor_conf() {
  local code=$1 port=$2 dir=$3 logfile=$4 bw=$5 sticky=$6
  local perf_extra
  perf_extra=$(get_perf_params)
  cat > "$CFG/node_${code}_${port}.conf" <<EOF
# tor-ml v${VERSION} – ${PERF_MODE} profile
SocksPort 127.0.0.1:$port IsolateDestAddr IsolateDestPort
DataDirectory $dir
ExitNodes {$code}
StrictNodes 1
ClientOnly 1
RunAsDaemon 1
Log notice file $logfile

AvoidDiskWrites 1
$perf_extra
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

$([[ "$sticky" == "1" ]] && echo "EnforceDistinctSubnets 0")
EOF
  if [[ "$bw" != "0" && -n "$bw" ]]; then
    cat >> "$CFG/node_${code}_${port}.conf" <<EOF
BandwidthRate ${bw} MB
BandwidthBurst $((bw * 2)) MB
EOF
  fi
  chown debian-tor:debian-tor "$CFG/node_${code}_${port}.conf" 2>/dev/null || true
  chmod 600 "$CFG/node_${code}_${port}.conf" 2>/dev/null || true
}

ensure_psiphon_binary() {
  local bin="$BIN/psiphon-tunnel-core"
  if [[ -x "$bin" ]]; then
    return 0
  fi
  echo -e "  ${Y}↓ Downloading psiphon-tunnel-core ...${N}"
  local arch url
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)
      url="https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/linux/psiphon-tunnel-core-x86_64"
      ;;
    aarch64|arm64)
      echo -e "  ${R}Official Psiphon binary for ARM64 is not published by Psiphon-Labs.${N}"
      echo -e "  ${D}Psiphon locations will not work on this architecture.${N}"
      echo -e "  ${D}Tor locations work normally.${N}"
      return 1
      ;;
    *)
      echo -e "  ${R}Unsupported architecture: $arch${N}"
      return 1
      ;;
  esac
  if ! curl -fsSL --retry 3 --connect-timeout 15 -o "$bin" "$url"; then
    echo -e "  ${R}Failed to download Psiphon binary${N}"
    rm -f "$bin"
    return 1
  fi
  chmod +x "$bin"
  if ! file "$bin" 2>/dev/null | grep -q "executable"; then
    echo -e "  ${R}Downloaded file is not a valid binary${N}"
    rm -f "$bin"
    return 1
  fi
  echo -e "  ${G}✓ Psiphon binary ready${N}"
}

write_psi_conf() {
  local code=$1 port=$2 dir=$3
  local http_port=$((port + 1000))
  cat > "$CFG/psi_${code}_${port}.json" <<EOF
{
  "LocalSocksProxyPort": $port,
  "LocalHttpProxyPort": $http_port,
  "EgressRegion": "$code",
  "PropagationChannelId": "FFFFFFFFFFFFFFFF",
  "SponsorId": "FFFFFFFFFFFFFFFF",
  "DataRootDirectory": "$dir",
  "UseIndistinguishableTLS": true,
  "EmitDiagnosticNotices": true,
  "EmitBytesTransferred": false
}
EOF
}

start_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  local bw sticky
  bw=$(get_setting "$id" "bandwidth")
  sticky=$(get_setting "$id" "sticky")

  if is_tor_id "$id"; then
    local conf="$CFG/node_${code}_${port}.conf"
    local dir="$DAT/tor_${code}_${port}"
    local logfile="$LOG/tor_${code}_${port}.log"
    mkdir -p "$dir" "$LOG"
    chown -R debian-tor:debian-tor "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true
    write_tor_conf "$code" "$port" "$dir" "$logfile" "$bw" "$sticky"
    if running_tor "$code" "$port"; then
      echo -e "  ${Y}•${N} $name [${code}] (Tor) already running on $port"
      return 0
    fi
    pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
    sleep 0.15
    : > "$logfile"
    chown debian-tor:debian-tor "$logfile" 2>/dev/null || true
    if ! sudo -u debian-tor /usr/bin/tor -f "$conf" >/dev/null 2>&1; then
      echo -e "  ${R}✗${N} $name [${code}] Tor failed to start"
      [[ -s "$logfile" ]] && tail -n 4 "$logfile" | sed 's/^/    /'
      return 1
    fi
    local i=0
    while ! running_tor "$code" "$port" && (( i < 15 )); do
      sleep 0.3
      i=$((i+1))
    done
    if running_tor "$code" "$port"; then
      set_setting "$id" "uptime" "$(date +%s)"
      local pid
      pid=$(get_pid "$id")
      if [[ -n "$pid" ]]; then
        case "$PERF_MODE" in
          weak) renice 10 -p "$pid" >/dev/null 2>&1 || true ;;
          max)  renice -5 -p "$pid" >/dev/null 2>&1 || true ;;
        esac
      fi
      echo -e "  ${G}✓${N} $name [${code}] ${C}Tor${N} started on ${W}$port${N}"
      return 0
    fi
    echo -e "  ${R}✗${N} $name [${code}] Tor failed"
    [[ -s "$logfile" ]] && tail -n 5 "$logfile" | sed 's/^/    /'
    return 1
  else
    ensure_psiphon_binary || return 1
    local dir="$DAT/psi_${code}_${port}"
    local logfile="$LOG/psi_${code}_${port}.log"
    local conf="$CFG/psi_${code}_${port}.json"
    mkdir -p "$dir" "$LOG"
    write_psi_conf "$code" "$port" "$dir"
    if running_psi "$code" "$port"; then
      echo -e "  ${Y}•${N} $name [${code}] (Psiphon) already running on $port"
      return 0
    fi
    if [[ -f "$STA/psi_${code}_${port}.pid" ]]; then
      kill "$(cat "$STA/psi_${code}_${port}.pid" 2>/dev/null)" 2>/dev/null || true
      rm -f "$STA/psi_${code}_${port}.pid"
    fi
    pkill -f "psiphon-tunnel-core.*${port}" 2>/dev/null || true
    sleep 0.2
    : > "$logfile"
    nohup "$BIN/psiphon-tunnel-core" -config "$conf" >> "$logfile" 2>&1 &
    local pid=$!
    echo "$pid" > "$STA/psi_${code}_${port}.pid"
    local i=0
    while ! nc -z 127.0.0.1 "$port" 2>/dev/null && (( i < 40 )); do
      sleep 0.5
      i=$((i+1))
      kill -0 "$pid" 2>/dev/null || break
    done
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
      set_setting "$id" "uptime" "$(date +%s)"
      echo -e "  ${G}✓${N} $name [${code}] ${PK}Psiphon${N} started on ${W}$port${N}"
      return 0
    fi
    echo -e "  ${R}✗${N} $name [${code}] Psiphon failed / still connecting"
    [[ -s "$logfile" ]] && tail -n 8 "$logfile" | sed 's/^/    /'
    return 1
  fi
}

stop_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  if ! running "$id"; then
    echo -e "  ${Y}•${N} $name [${code}] not running"
    return 0
  fi
  if is_tor_id "$id"; then
    pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
    sleep 0.25
    if running_tor "$code" "$port"; then
      pkill -9 -f "node_${code}_${port}.conf" 2>/dev/null || true
    fi
  else
    if [[ -f "$STA/psi_${code}_${port}.pid" ]]; then
      kill "$(cat "$STA/psi_${code}_${port}.pid")" 2>/dev/null || true
      sleep 0.3
      kill -9 "$(cat "$STA/psi_${code}_${port}.pid")" 2>/dev/null || true
      rm -f "$STA/psi_${code}_${port}.pid"
    fi
    pkill -f "psiphon-tunnel-core" 2>/dev/null || true
    sleep 0.1
  fi
  set_setting "$id" "uptime" "0"
  rm -f "$STA/${code}_${port}.ip" 2>/dev/null || true
  echo -e "  ${G}✓${N} $name [${code}] stopped"
}

auto_start() {
  if [[ -f "$AUTO_PID_FILE" ]] && kill -0 "$(cat "$AUTO_PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo -e "  ${Y}•${N} Auto balancer already running"
    return
  fi
  (
    local last_port=""
    while true; do
      local best_port="" best_lat=99999 best_id=""
      local ids
      ids=$(list_running)
      for id in $ids; do
        local code name port
        IFS='|' read -r code name port <<< "$(info "$id")"
        local lat
        lat=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{time_total}" \
              --max-time 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || echo "9")
        lat=$(awk -v t="$lat" 'BEGIN{printf "%.0f", t*1000}')
        if (( lat < best_lat )); then
          best_lat=$lat
          best_port=$port
          best_id=$id
        fi
      done
      if [[ -n "$best_port" ]]; then
        echo "$best_port" > "$STA/best.port"
        echo "$best_id" > "$STA/best.id"
        if [[ "$best_port" != "$last_port" ]]; then
          pkill -f "socat.*TCP-LISTEN:$AUTO_PORT" 2>/dev/null || true
          sleep 0.15
          socat TCP-LISTEN:$AUTO_PORT,fork,reuseaddr,bind=127.0.0.1 TCP:127.0.0.1:$best_port >/dev/null 2>&1 &
          echo $! > "$STA/socat.pid"
          last_port="$best_port"
        fi
      fi
      sleep 40
    done
  ) &
  echo $! > "$AUTO_PID_FILE"
  echo -e "  ${G}✓${N} Auto balancer started on port ${W}$AUTO_PORT${N}"
  echo -e "  ${D}  mixes Tor + Psiphon, picks lowest latency (no flicker when same)${N}"
}

auto_stop() {
  if [[ -f "$AUTO_PID_FILE" ]]; then
    kill "$(cat "$AUTO_PID_FILE")" 2>/dev/null || true
    [[ -f "$STA/socat.pid" ]] && kill "$(cat "$STA/socat.pid")" 2>/dev/null || true
    pkill -f "socat.*$AUTO_PORT" 2>/dev/null || true
    rm -f "$AUTO_PID_FILE" "$STA/best.port" "$STA/best.id" "$STA/socat.pid"
    echo -e "  ${G}✓${N} Auto balancer stopped"
  else
    echo -e "  ${Y}•${N} Auto not running"
  fi
}

show_running_table() {
  local ids
  ids=$(list_running)
  if [[ -z "$ids" ]]; then
    echo -e "  ${Y}No running locations.${N}"
    return 1
  fi
  echo -e "  ${C}ID    Type   CC   Location                 Port${N}"
  line
  for id in $ids; do
    local code name port typ
    IFS='|' read -r code name port <<< "$(info "$id")"
    if is_tor_id "$id"; then typ="${C}Tor${N}"; else typ="${PK}Psi${N}"; fi
    printf "  ${G}%-5s${N} %-12b %-4s %-24s ${W}%s${N}\n" "$id" "$typ" "$code" "$name" "$port"
  done
  line
  return 0
}

full_status() {
  header
  echo -e "  ${C}ID    Type   CC   Location                 Port     CPU   MEM   Status     Uptime       IP${N}"
  line
  for id in "${TOR_ORDER[@]}" "${PSI_ORDER[@]}"; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    local typ_col
    if is_tor_id "$id"; then typ_col="${C}Tor${N}"; else typ_col="${PK}Psi${N}"; fi
    local pid
    pid=$(get_pid "$id")
    if running "$id"; then
      local cpu mem boot_status ip uptime_display
      read -r cpu mem <<< "$(get_node_stats "$pid")"
      local typ="tor"
      is_psi_id "$id" && typ="psi"
      boot_status=$(check_bootstrap "$LOG/${typ}_${code}_${port}.log" "$port" "$typ")
      ip=$(get_ip "$port" "$code")
      uptime_display=$(format_uptime "$(get_setting "$id" "uptime")")
      local col
      case "$boot_status" in
        Active)     col="$G" ;;
        Connecting) col="$Y" ;;
        *)          col="$R" ;;
      esac
      printf "  ${G}%-5s${N} %-12b %-4s %-24s %-8s ${G}%-5s${N} ${G}%-5s${N}  ${col}%-10s${N}  ${W}%-12s${N}  ${W}%s${N}\n" \
        "$id" "$typ_col" "$code" "$name" "$port" "$cpu%" "$mem%" "$boot_status" "$uptime_display" "$ip"
    else
      printf "  ${D}%-5s %-12b %-4s %-24s %-8s${N} ${R}OFFLINE${N}\n" "$id" "$typ_col" "$code" "$name" "$port"
    fi
  done
  line
  if [[ -f "$STA/best.port" ]]; then
    echo -e "  ${M}Auto best${N} → port ${W}$(cat "$STA/best.port")${N}  (public ${W}$AUTO_PORT${N})"
  fi
  echo
  read -rp "  Press Enter..."
}

do_start() {
  header
  echo -e "  ${C}Start Location(s)${N}"
  echo
  echo -e "  ${LB}── Tor ──${N}"
  for i in {1..30}; do
    local a b na nb
    a=$(printf "%02d" "$i")
    b=$(printf "%02d" "$((i+30))")
    IFS='|' read -r _ na _ <<< "$(info "$a")"
    IFS='|' read -r _ nb _ <<< "$(info "$b")"
    printf "  ${C}[%s]${N} %-18s  ${C}[%s]${N} %-18s\n" "$a" "$na" "$b" "$nb"
  done
  echo
  echo -e "  ${PK}── Psiphon ──${N}"
  local c=0
  for id in "${PSI_ORDER[@]}"; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    printf "  ${PK}[%s]${N} %-18s" "$id" "$name"
    c=$((c+1))
    (( c % 2 == 0 )) && echo || printf "  "
  done
  echo
  echo
  echo -e "  ${D}Format: 1   or  3.7.P02   or  P1 P5 12${N}"
  echo
  read -rp "$(echo -e "  ${C}Location(s): ${N}")" raw
  [[ -z "$raw" ]] && return
  raw=${raw//./ }; raw=${raw//,/ }
  echo
  for x in $raw; do
    local id
    id=$(parse_id "$x")
    if [[ -z "$id" ]] || { ! is_tor_id "$id" && ! is_psi_id "$id"; }; then
      echo -e "  ${R}Invalid: $x${N}"
      continue
    fi
    start_one "$id"
  done
  echo
  read -rp "  Press Enter..."
}

do_stop() {
  header
  echo -e "  ${C}Stop Location(s)${N}"
  echo
  if ! show_running_table; then
    echo; read -rp "  Press Enter..."; return
  fi
  echo -e "  ${D}Format: 3   or  3.7.P02${N}"
  echo
  read -rp "$(echo -e "  ${C}Location(s): ${N}")" raw
  [[ -z "$raw" ]] && return
  raw=${raw//./ }; raw=${raw//,/ }
  echo
  for x in $raw; do
    local id
    id=$(parse_id "$x")
    [[ -z "$id" ]] && continue
    stop_one "$id"
  done
  echo
  read -rp "  Press Enter..."
}

start_all_tor() {
  header
  echo -e "  ${Y}Starting all Tor locations (careful on 1G RAM)...${N}"
  echo
  ulimit -n 65535 2>/dev/null || true
  for id in "${TOR_ORDER[@]}"; do
    start_one "$id" || true
    sleep 0.06
  done
  echo
  echo -e "  ${G}Done.${N}"
  read -rp "  Press Enter..."
}

start_all_psi() {
  header
  echo -e "  ${Y}Starting all Psiphon locations...${N}"
  echo
  ensure_psiphon_binary || { read -rp "  Press Enter..."; return; }
  for id in "${PSI_ORDER[@]}"; do
    start_one "$id" || true
    sleep 0.3
  done
  echo
  echo -e "  ${G}Done.${N}"
  read -rp "  Press Enter..."
}

stop_all() {
  header
  echo -e "  ${Y}Stopping everything...${N}"
  echo
  for id in "${TOR_ORDER[@]}" "${PSI_ORDER[@]}"; do
    stop_one "$id" || true
  done
  auto_stop
  echo
  echo -e "  ${G}All stopped.${N}"
  read -rp "  Press Enter..."
}

change_port() {
  header
  echo -e "  ${C}Change Location Port${N}"
  echo
  show_running_table || true
  echo
  read -rp "$(echo -e "  ${C}Location ID: ${N}")" raw
  local id
  id=$(parse_id "$raw")
  if [[ -z "$id" ]] || { ! is_tor_id "$id" && ! is_psi_id "$id"; }; then
    echo -e "  ${R}Invalid ID${N}"; sleep 1; return
  fi
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  echo
  echo -e "  Current: $name [${code}] on port ${W}$port${N}"
  read -rp "  New port (40000-60000): " new
  if ! [[ "$new" =~ ^[0-9]+$ ]] || (( new < 40000 || new > 60000 )); then
    echo -e "  ${R}Invalid port${N}"; sleep 1; return
  fi
  stop_one "$id"
  set_setting "$id" "port" "$new"
  echo -e "  ${G}Port updated to $new${N}"
  sleep 1.2
}

toggle_sticky() {
  header
  echo -e "  ${C}Toggle Sticky Exit (keep same exit IP as long as possible)${N}"
  echo
  for id in "${TOR_ORDER[@]}"; do
    local code name port sticky
    IFS='|' read -r code name port <<< "$(info "$id")"
    sticky=$(get_setting "$id" "sticky")
    local st="${D}off${N}"
    [[ "$sticky" == "1" ]] && st="${G}ON${N}"
    printf "  ${C}[%s]${N} %-20s %b\n" "$id" "$name" "$st"
  done
  line
  echo
  read -rp "$(echo -e "  ${C}Location ID (Tor only): ${N}")" raw
  local id
  id=$(parse_id "$raw")
  if [[ -z "$id" ]] || ! is_tor_id "$id"; then
    echo -e "  ${R}Invalid (Tor only)${N}"; sleep 1; return
  fi
  local cur
  cur=$(get_setting "$id" "sticky")
  if [[ "$cur" == "1" ]]; then
    set_setting "$id" "sticky" "0"
    echo -e "  ${Y}Sticky disabled${N}"
  else
    set_setting "$id" "sticky" "1"
    echo -e "  ${G}Sticky enabled${N}"
  fi
  echo -e "  ${D}Restart the location to apply${N}"
  sleep 1.5
}

set_bandwidth() {
  header
  echo -e "  ${C}Set Bandwidth Limit (MB) per location${N}"
  echo
  for id in "${TOR_ORDER[@]}"; do
    local code name port bw
    IFS='|' read -r code name port <<< "$(info "$id")"
    bw=$(get_setting "$id" "bandwidth")
    local disp="${D}unlimited${N}"
    [[ "$bw" != "0" ]] && disp="${G}${bw} MB${N}"
    printf "  ${C}[%s]${N} %-20s %b\n" "$id" "$name" "$disp"
  done
  line
  echo
  read -rp "$(echo -e "  ${C}Location ID (Tor): ${N}")" raw
  local id
  id=$(parse_id "$raw")
  if [[ -z "$id" ]] || ! is_tor_id "$id"; then
    echo -e "  ${R}Invalid${N}"; sleep 1; return
  fi
  read -rp "$(echo -e "  ${M}Bandwidth MB (0=unlimited): ${N}")" bw
  if ! [[ "$bw" =~ ^[0-9]+$ ]]; then
    echo -e "  ${R}Invalid${N}"; sleep 1; return
  fi
  set_setting "$id" "bandwidth" "$bw"
  echo -e "  ${G}Set to ${bw} MB (restart to apply)${N}"
  sleep 1.3
}

set_perf_mode() {
  header
  echo -e "  ${C}Bandwidth / Performance Profile${N}"
  echo
  echo -e "  ${LG}[1]${N}  Weak     ${D}– low CPU, minimal circuits, gentle${N}"
  echo -e "  ${CY}[2]${N}  Normal   ${D}– recommended balanced profile${N}"
  echo -e "  ${LR}[3]${N}  Maximum  ${D}– more circuits, higher throughput (more CPU)${N}"
  echo
  echo -e "  Current: ${W}${PERF_MODE}${N}"
  echo
  echo -e "  ${D}Type 1 / 2 / 3  or  weak / normal / max${N}"
  echo
  read -rp "$(echo -e "  ${M}Select: ${N}")" choice
  case "$choice" in
    1|weak|w)   PERF_MODE="weak" ;;
    2|normal|n) PERF_MODE="normal" ;;
    3|max|m)    PERF_MODE="max" ;;
    *) echo -e "  ${Y}No change${N}"; sleep 1; return ;;
  esac
  save_global
  echo -e "  ${G}✓ Mode set to ${PERF_MODE}${N}"
  echo -e "  ${D}Restart running locations to fully apply new profile${N}"
  sleep 1.8
}

speed_test() {
  header
  echo -e "  ${C}Latency / Speed Test${N}"
  echo
  if ! show_running_table; then
    echo; read -rp "  Press Enter..."; return
  fi
  echo -e "  ${D}Testing via Cloudflare...${N}"
  echo
  local ids
  ids=$(list_running)
  for id in $ids; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    local typ
    is_tor_id "$id" && typ="Tor" || typ="Psi"
    printf "  %-6s %-18s " "$typ" "$name"
    local lat
    lat=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{time_total}" \
          --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || echo "fail")
    if [[ "$lat" == "fail" ]]; then
      echo -e "${R}unreachable${N}"; continue
    fi
    local speed_raw
    speed_raw=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{speed_download}" \
                --max-time 10 "https://speed.cloudflare.com/__down?bytes=1500000" 2>/dev/null || echo "0")
    local speed_kb
    speed_kb=$(awk -v s="$speed_raw" 'BEGIN{printf "%.0f", s/1024}')
    local ip
    ip=$(get_ip "$port" "$code")
    echo -e "lat ${Y}${lat}s${N}  ~${G}${speed_kb} KB/s${N}  ip ${W}${ip}${N}"
  done
  echo
  read -rp "  Press Enter..."
}

view_log() {
  header
  echo -e "  ${C}View Log (last 30 lines)${N}"
  echo
  show_running_table || true
  echo
  read -rp "$(echo -e "  ${C}Location ID: ${N}")" raw
  local id
  id=$(parse_id "$raw")
  if [[ -z "$id" ]]; then
    echo -e "  ${R}Invalid${N}"; sleep 1; return
  fi
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  local typ="tor"
  is_psi_id "$id" && typ="psi"
  local logfile="$LOG/${typ}_${code}_${port}.log"
  if [[ ! -f "$logfile" ]]; then
    echo -e "  ${Y}No log${N}"; sleep 1; return
  fi
  echo
  line
  tail -n 30 "$logfile" | sed 's/^/  /'
  line
  echo
  read -rp "  Press Enter..."
}

uninstall() {
  header
  echo -e "  ${R}WARNING: Complete removal of tor-ml + Psiphon data${N}"
  echo
  echo -e "  • All Tor & Psiphon processes will be killed"
  echo -e "  • $BASE will be deleted"
  echo -e "  • Command 'tor' removed from /usr/local/bin"
  echo -e "  • Any leftover socat/auto processes cleaned"
  echo
  echo -ne "  Type ${R}YES${N} to confirm: "
  read -r conf
  if [[ "$conf" != "YES" ]]; then
    echo -e "  ${Y}Cancelled${N}"; sleep 1; return
  fi
  echo
  echo -e "  ${Y}Stopping everything...${N}"
  pkill -f "node_.*\.conf" 2>/dev/null || true
  pkill -f "psiphon-tunnel-core" 2>/dev/null || true
  pkill -f "socat.*$AUTO_PORT" 2>/dev/null || true
  [[ -f "$AUTO_PID_FILE" ]] && kill "$(cat "$AUTO_PID_FILE")" 2>/dev/null || true
  sleep 0.8
  pkill -9 -f "node_.*\.conf" 2>/dev/null || true
  pkill -9 -f "psiphon-tunnel-core" 2>/dev/null || true
  pkill -9 -f "socat.*$AUTO_PORT" 2>/dev/null || true
  sleep 0.3
  echo -e "  ${Y}Removing files...${N}"
  rm -rf "$BASE"
  rm -f "$CMD"
  rm -rf /opt/tor-ml 2>/dev/null || true
  echo -e "  ${G}✓ tor-ml completely removed from the system.${N}"
  exit 0
}

# =============================================================================
# INSTALL – NEVER calls clear / header. Full visible progress.
# =============================================================================
install() {
  need_root

  echo
  echo -e "  ${LB}████  tor-ml v${VERSION}  –  Installer${N}"
  echo -e "  ${D}════════════════════════════════════════${N}"
  echo

  if [[ -d "$BASE" ]]; then
    echo -e "  ${Y}Previous installation found at $BASE${N}"
    echo -ne "  Remove old version and install fresh? [y/N]: "
    read -r ans
    case "${ans,,}" in
      y|yes)
        echo -e "  ${Y}Cleaning old version...${N}"
        pkill -f "node_.*\.conf" 2>/dev/null || true
        pkill -f "psiphon-tunnel-core" 2>/dev/null || true
        pkill -f "socat.*$AUTO_PORT" 2>/dev/null || true
        sleep 0.5
        rm -rf "$BASE"
        rm -f "$CMD"
        echo -e "  ${G}Old version removed.${N}"
        ;;
      *)
        echo -e "  ${Y}Install cancelled.${N}"
        exit 0
        ;;
    esac
    echo
  fi

  echo -e "  ${C}[1/6]${N} Updating package lists..."
  apt-get update -qq
  echo -e "  ${G}      done${N}"

  echo -e "  ${C}[2/6]${N} Installing dependencies (tor, curl, socat, netcat)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tor tor-geoipdb curl bc netcat-openbsd socat >/dev/null 2>&1 || true
  echo -e "  ${G}      done${N}"

  echo -e "  ${C}[3/6]${N} Creating debian-tor user if needed..."
  if ! id debian-tor &>/dev/null; then
    useradd --system --home-dir /var/lib/tor --shell /usr/sbin/nologin debian-tor 2>/dev/null || true
  fi
  systemctl stop tor 2>/dev/null || true
  systemctl disable tor 2>/dev/null || true
  echo -e "  ${G}      done${N}"

  echo -e "  ${C}[4/6]${N} Creating directories..."
  mkdir -p "$CFG" "$DAT" "$LOG" "$STA" "$BIN" "$PSI"
  chown -R debian-tor:debian-tor "$DAT" "$LOG" 2>/dev/null || true
  echo -e "  ${G}      done${N}"

  echo -e "  ${C}[5/6]${N} Installing tor-ml command..."
  # Copy ourselves with CR stripped
  if [[ -f "$0" ]]; then
    tr -d '\r' < "$0" > "$CMD"
  else
    cp "$0" "$CMD" 2>/dev/null || true
  fi
  chmod +x "$CMD"
  init_dirs
  migrate_settings
  echo "perf=normal" > "$GLOBAL"
  echo -e "  ${G}      done  →  ${W}$CMD${N}"

  echo -e "  ${C}[6/6]${N} Preparing Psiphon binary (x86_64 only)..."
  ensure_psiphon_binary || true

  echo
  echo -e "  ${G}════════════════════════════════════════${N}"
  echo -e "  ${G}✓ Installation complete!${N}"
  echo
  echo -e "  Run the manager with:  ${W}tor${N}"
  echo
}

main() {
  ulimit -n 65535 2>/dev/null || true
  init_dirs
  migrate_settings
  load_global

  if ! pgrep -f "tor-ml-watchdog" >/dev/null 2>&1; then
    (
      exec -a tor-ml-watchdog bash -c '
        while true; do
          sleep 90
          for f in /opt/tor-ml/status/*.pid; do
            [[ -f "$f" ]] || continue
            pid=$(cat "$f" 2>/dev/null)
            kill -0 "$pid" 2>/dev/null || rm -f "$f"
          done
        done
      ' &
    ) 2>/dev/null || true
  fi

  while true; do
    header
    echo -e "  ${LB}[1]${N}  Full Status"
    echo -e "  ${G}[2]${N}  Start Location(s)"
    echo -e "  ${Y}[3]${N}  Stop Location(s)"
    echo -e "  ${C}[4]${N}  Start All Tor          ${D}(careful on 1G)${N}"
    echo -e "  ${PK}[5]${N}  Start All Psiphon"
    echo -e "  ${OR}[6]${N}  Stop All"
    echo -e "  ${B}[7]${N}  Change Port"
    echo -e "  ${M}[8]${N}  Speed / Latency Test"
    echo -e "  ${C}[9]${N}  View Log"
    echo -e "  ${LG}[10]${N} Set Bandwidth (per node)"
    echo -e "  ${CY}[11]${N} Toggle Sticky Exit (Tor)"
    echo -e "  ${W}[12]${N} Performance Mode  ${D}(Weak / Normal / Max)${N}"
    echo -e "  ${G}[13]${N} Start Auto Balancer (best-ping)"
    echo -e "  ${Y}[14]${N} Stop Auto Balancer"
    echo -e "  ${R}[15]${N} Uninstall"
    echo -e "  ${D}[0]${N}  Exit"
    echo
    read -rp "$(echo -e "  ${M}Select: ${N}")" choice
    case $choice in
      1)  full_status ;;
      2)  do_start ;;
      3)  do_stop ;;
      4)  start_all_tor ;;
      5)  start_all_psi ;;
      6)  stop_all ;;
      7)  change_port ;;
      8)  speed_test ;;
      9)  view_log ;;
      10) set_bandwidth ;;
      11) toggle_sticky ;;
      12) set_perf_mode ;;
      13) auto_start; sleep 1.2 ;;
      14) auto_stop; sleep 1.2 ;;
      15) uninstall ;;
      0)  clear; exit 0 ;;
    esac
  done
}

# Entry
if [[ "${1:-}" == "--install" ]]; then
  install
  exit 0
fi

if [[ ! -d "$BASE" ]]; then
  echo -e "${Y}tor-ml is not installed.${N}"
  echo -e "Run: ${W}sudo bash $0 --install${N}"
  exit 1
fi

main
