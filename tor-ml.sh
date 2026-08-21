#!/usr/bin/env bash
# tor-ml v3 – Lightweight Multi-Exit Tor Manager
# Optimized for low-end servers (1 vCPU / 1 GB RAM)
# Author: senior rewrite – clean, safe, low resource

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'
M='\033[1;35m'; C='\033[1;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'
OR='\033[1;38;5;208m'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE="/opt/tor-ml"
CFG="$BASE/config"
DAT="$BASE/data"
LOG="$BASE/logs"
STA="$BASE/status"
CMD="/usr/local/bin/tor"
SETTINGS="$CFG/settings.db"
AUTO_PORT=49000          # dedicated multi-location / best-ping port
AUTO_PID_FILE="$STA/auto.pid"
WATCHDOG_INTERVAL=90     # seconds

# ---------------------------------------------------------------------------
# Locations  (ISO country code : Name : default SOCKS port)
# Added more stable / useful exits.  All must work with ExitNodes {CC}
# ---------------------------------------------------------------------------
declare -A LOC=(
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
  # Extra useful locations
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

ORDER=({01..60})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
need_root() {
  [[ $EUID -eq 0 ]] || { echo -e "${R}[!] Run as root${N}"; exit 1; }
}

parse() {
  local id
  id=$(printf "%02d" "$((10#${1}))" 2>/dev/null || true)
  [[ -n ${LOC[$id]+x} ]] && echo "$id"
}

init_dirs() {
  mkdir -p "$CFG" "$DAT" "$LOG" "$STA"
  touch "$SETTINGS"
}

# ---------------------------------------------------------------------------
# Settings (simple key:port:bw:uptime:sticky)
# ---------------------------------------------------------------------------
get_setting() {
  local id=$1 field=$2
  local line
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)
  if [[ -n "$line" ]]; then
    IFS=':' read -r _ port bw uptime sticky <<< "$line"
    case "$field" in
      port)      echo "${port:-0}" ;;
      bandwidth) echo "${bw:-0}" ;;
      uptime)    echo "${uptime:-0}" ;;
      sticky)    echo "${sticky:-0}" ;;
    esac
  else
    echo "0"
  fi
}

set_setting() {
  local id=$1 field=$2 value=$3
  local line port bw uptime sticky
  line=$(grep "^${id}:" "$SETTINGS" 2>/dev/null | head -1 || true)

  if [[ -n "$line" ]]; then
    IFS=':' read -r _ port bw uptime sticky <<< "$line"
  else
    IFS=':' read -r _ _ port <<< "${LOC[$id]}"
    bw=0; uptime=0; sticky=0
  fi

  case "$field" in
    port)      port="$value" ;;
    bandwidth) bw="$value" ;;
    uptime)    uptime="$value" ;;
    sticky)    sticky="$value" ;;
  esac

  sed -i "/^${id}:/d" "$SETTINGS" 2>/dev/null || true
  echo "${id}:${port}:${bw}:${uptime}:${sticky}" >> "$SETTINGS"
}

migrate_settings() {
  [[ -f "$SETTINGS" ]] && return
  for id in "${ORDER[@]}"; do
    IFS=':' read -r _ _ port <<< "${LOC[$id]}"
    echo "${id}:${port}:0:0:0" >> "$SETTINGS"
  done
}

# ---------------------------------------------------------------------------
# Info helpers
# ---------------------------------------------------------------------------
info() {
  local id=$1
  local code name port
  IFS=':' read -r code name port <<< "${LOC[$id]}"
  local custom
  custom=$(get_setting "$id" "port")
  [[ "$custom" != "0" ]] && port="$custom"
  echo "${code}|${name}|${port}"
}

running() {
  local code=$1 port=$2
  pgrep -f "tor -f $CFG/node_${code}_${port}.conf" >/dev/null 2>&1
}

get_pid() {
  local code=$1 port=$2
  pgrep -f "node_${code}_${port}.conf" 2>/dev/null | head -1 || true
}

list_running() {
  local out=()
  for id in "${ORDER[@]}"; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    running "$code" "$port" && out+=("$id")
  done
  echo "${out[*]}"
}

# ---------------------------------------------------------------------------
# Ultra-light stats (single pgrep + ps)
# ---------------------------------------------------------------------------
get_stats() {
  local cpu=0 mem=0 cnt=0
  local pids
  pids=$(pgrep -f "node_.*\.conf" 2>/dev/null || true)
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

# ---------------------------------------------------------------------------
# Bootstrap / IP (cached)
# ---------------------------------------------------------------------------
check_bootstrap() {
  local logfile=$1 port=$2
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "Active"
    return
  fi
  if grep -q "Bootstrapped 100%" "$logfile" 2>/dev/null; then
    echo "Active"
  elif grep -q "Bootstrapped" "$logfile" 2>/dev/null; then
    echo "Connecting"
  else
    echo "Inactive"
  fi
}

get_ip() {
  local port=$1 code=$2
  local ip_file="$STA/${code}_${port}.ip"
  if [[ -f "$ip_file" ]] && [[ $(find "$ip_file" -mmin -30 2>/dev/null) ]]; then
    cat "$ip_file"
    return
  fi
  local ip
  ip=$(curl --socks5-hostname "127.0.0.1:$port" -s --max-time 4 \
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

line() { echo -e "${D}--------------------------------------------------------------${N}"; }

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
header() {
  clear
  local cpu mem cnt
  read -r cpu mem cnt <<< "$(get_stats)"
  echo
  echo -e "  ${C}${W}tor-ml${N}  ${D}v3${N}  ${D}– low-resource multi-exit${N}"
  line
  echo -e "  Status   ${G}${cnt}${N} running   ${D}|${N}  CPU ${OR}${cpu}%${N}   ${D}|${N}  MEM ${OR}${mem}%${N}"
  echo -e "  Config   ${W}$CFG${N}"
  echo -e "  Auto     ${W}port ${AUTO_PORT}${N} (best-ping multi-location)"
  line
  echo -e "  ${D}Optimized for 1 vCPU / 1 GB RAM servers${N}"
  line
  echo
}

# ---------------------------------------------------------------------------
# Tor config – heavily optimised for low memory
# ---------------------------------------------------------------------------
write_tor_conf() {
  local code=$1 port=$2 dir=$3 logfile=$4 bw=$5 sticky=$6
  cat > "$CFG/node_${code}_${port}.conf" <<EOF
# tor-ml v3 – low-memory client
SocksPort 127.0.0.1:$port IsolateDestAddr IsolateDestPort
DataDirectory $dir
ExitNodes {$code}
StrictNodes 1
ClientOnly 1
RunAsDaemon 1
Log notice file $logfile

# Memory & performance (critical for 1G servers)
AvoidDiskWrites 1
MaxMemInQueues 32 MB
NumEntryGuards 2
CircuitBuildTimeout 15
MaxClientCircuitsPending 4
KeepalivePeriod 45
NewCircuitPeriod 60
MaxCircuitDirtiness 600
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

# Sticky exit (same exit relay as long as it stays available)
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

# ---------------------------------------------------------------------------
# Start / Stop single node
# ---------------------------------------------------------------------------
start_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"

  local conf="$CFG/node_${code}_${port}.conf"
  local dir="$DAT/${code}_${port}"
  local logfile="$LOG/${code}_${port}.log"
  local bw sticky

  bw=$(get_setting "$id" "bandwidth")
  sticky=$(get_setting "$id" "sticky")

  mkdir -p "$dir" "$LOG"
  chown -R debian-tor:debian-tor "$dir" 2>/dev/null || true
  chmod 700 "$dir" 2>/dev/null || true

  write_tor_conf "$code" "$port" "$dir" "$logfile" "$bw" "$sticky"

  if running "$code" "$port"; then
    echo -e "  ${Y}•${N} $name [${code}] already running on $port"
    return 0
  fi

  pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
  sleep 0.15
  : > "$logfile"
  chown debian-tor:debian-tor "$logfile" 2>/dev/null || true

  if ! sudo -u debian-tor /usr/bin/tor -f "$conf" >/dev/null 2>&1; then
    echo -e "  ${R}✗${N} $name [${code}] failed to start"
    [[ -s "$logfile" ]] && tail -n 4 "$logfile" | sed 's/^/    /'
    return 1
  fi

  local i=0
  while ! running "$code" "$port" && (( i < 12 )); do
    sleep 0.25
    i=$((i+1))
  done

  if running "$code" "$port"; then
    set_setting "$id" "uptime" "$(date +%s)"
    echo -e "  ${G}✓${N} $name [${code}] started on ${W}$port${N}"
    return 0
  fi

  echo -e "  ${R}✗${N} $name [${code}] failed"
  [[ -s "$logfile" ]] && tail -n 5 "$logfile" | sed 's/^/    /'
  return 1
}

stop_one() {
  local id=$1
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"

  if ! running "$code" "$port"; then
    echo -e "  ${Y}•${N} $name [${code}] not running"
    return 0
  fi

  pkill -f "node_${code}_${port}.conf" 2>/dev/null || true
  sleep 0.2
  if running "$code" "$port"; then
    pkill -9 -f "node_${code}_${port}.conf" 2>/dev/null || true
  fi
  set_setting "$id" "uptime" "0"
  rm -f "$STA/${code}_${port}.ip" 2>/dev/null || true
  echo -e "  ${G}✓${N} $name [${code}] stopped"
}

# ---------------------------------------------------------------------------
# Auto multi-location (best-ping selector) – very light
# ---------------------------------------------------------------------------
auto_start() {
  if [[ -f "$AUTO_PID_FILE" ]] && kill -0 "$(cat "$AUTO_PID_FILE")" 2>/dev/null; then
    echo -e "  ${Y}•${N} Auto multi-location already running"
    return
  fi

  # Lightweight background selector
  (
    while true; do
      local best_port="" best_lat=9999
      local ids
      ids=$(list_running)
      for id in $ids; do
        local code name port
        IFS='|' read -r code name port <<< "$(info "$id")"
        local lat
        lat=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{time_total}" \
              --max-time 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || echo "9")
        lat=$(printf "%.0f" "$(echo "$lat * 1000" | bc 2>/dev/null || echo 9000)")
        if (( lat < best_lat )); then
          best_lat=$lat
          best_port=$port
        fi
      done

      if [[ -n "$best_port" ]]; then
        # Write current best port for external tools / Sanaei
        echo "$best_port" > "$STA/best.port"
        # Simple TCP forwarder (socat is tiny)
        pkill -f "socat.*$AUTO_PORT" 2>/dev/null || true
        socat TCP-LISTEN:$AUTO_PORT,fork,reuseaddr TCP:127.0.0.1:$best_port &
        echo $! > "$AUTO_PID_FILE"
      fi
      sleep 45
    done
  ) &
  echo $! > "$AUTO_PID_FILE"
  echo -e "  ${G}✓${N} Auto multi-location started on port ${W}$AUTO_PORT${N}"
}

auto_stop() {
  if [[ -f "$AUTO_PID_FILE" ]]; then
    kill "$(cat "$AUTO_PID_FILE")" 2>/dev/null || true
    pkill -f "socat.*$AUTO_PORT" 2>/dev/null || true
    rm -f "$AUTO_PID_FILE" "$STA/best.port"
    echo -e "  ${G}✓${N} Auto multi-location stopped"
  else
    echo -e "  ${Y}•${N} Auto not running"
  fi
}

# ---------------------------------------------------------------------------
# Watchdog – auto-restart dead nodes (very light)
# ---------------------------------------------------------------------------
watchdog() {
  while true; do
    sleep "$WATCHDOG_INTERVAL"
    for id in $(list_running); do
      local code name port
      IFS='|' read -r code name port <<< "$(info "$id")"
      if ! running "$code" "$port"; then
        echo "$(date) watchdog: restarting $name" >> "$LOG/watchdog.log"
        start_one "$id" >/dev/null 2>&1 || true
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# UI functions
# ---------------------------------------------------------------------------
show_running_table() {
  local ids
  ids=$(list_running)
  if [[ -z "$ids" ]]; then
    echo -e "  ${Y}No running locations.${N}"
    return 1
  fi
  echo -e "  ${C}ID   CC   Location                 Port${N}"
  line
  for id in $ids; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    printf "  ${G}%-4s${N} %-4s %-24s ${W}%s${N}\n" "$id" "$code" "$name" "$port"
  done
  line
  return 0
}

full_status() {
  header
  echo -e "  ${C}ID   CC   Location                 Port      CPU   MEM   Status     Uptime       IP${N}"
  line
  for id in "${ORDER[@]}"; do
    local code name port
    IFS='|' read -r code name port <<< "$(info "$id")"
    local pid
    pid=$(get_pid "$code" "$port")

    if running "$code" "$port"; then
      local cpu mem boot_status ip uptime_display
      read -r cpu mem <<< "$(get_node_stats "$pid")"
      boot_status=$(check_bootstrap "$LOG/${code}_${port}.log" "$port")
      ip=$(get_ip "$port" "$code")
      uptime_display=$(format_uptime "$(get_setting "$id" "uptime")")

      local col
      case "$boot_status" in
        Active)     col="$G" ;;
        Connecting) col="$Y" ;;
        *)          col="$R" ;;
      esac

      printf "  ${G}%-4s${N} %-4s %-24s %-8s ${G}%-5s${N} ${G}%-5s${N}  ${col}%-10s${N}  ${W}%-12s${N}  ${W}%s${N}\n" \
        "$id" "$code" "$name" "$port" "$cpu%" "$mem%" "$boot_status" "$uptime_display" "$ip"
    else
      printf "  ${D}%-4s %-4s %-24s %-8s${N} ${R}OFFLINE${N}\n" "$id" "$code" "$name" "$port"
    fi
  done
  line
  if [[ -f "$STA/best.port" ]]; then
    echo -e "  Auto best-ping port: ${W}$(cat "$STA/best.port")${N}  →  public ${W}$AUTO_PORT${N}"
  fi
  echo
  read -rp "  Press Enter..."
}

do_start() {
  header
  echo -e "  ${C}Start Location(s)${N}"
  echo
  for i in {1..30}; do
    local a b na nb
    a=$(printf "%02d" "$i")
    b=$(printf "%02d" "$((i+30))")
    IFS='|' read -r _ na _ <<< "$(info "$a")"
    IFS='|' read -r _ nb _ <<< "$(info "$b")"
    printf "  ${C}[%s]${N} %-18s  ${C}[%s]${N} %-18s\n" "$a" "$na" "$b" "$nb"
  done
  echo
  echo -e "  ${D}Format: 1   or   1.4.12   or   1 4 12${N}"
  echo
  read -rp "$(echo -e "  ${C}Location(s): ${N}")" raw
  [[ -z "$raw" ]] && return
  raw=${raw//./ }; raw=${raw//,/ }
  echo
  for x in $raw; do
    local id
    id=$(parse "$x") || { echo -e "  ${R}Invalid: $x${N}"; continue; }
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
  echo -e "  ${D}Format: 3   or   3.7.15${N}"
  echo
  read -rp "$(echo -e "  ${C}Location(s): ${N}")" raw
  [[ -z "$raw" ]] && return
  raw=${raw//./ }; raw=${raw//,/ }
  echo
  for x in $raw; do
    local id
    id=$(parse "$x") || continue
    stop_one "$id"
  done
  echo
  read -rp "  Press Enter..."
}

start_all() {
  header
  echo -e "  ${Y}Starting all locations (this will use significant RAM)...${N}"
  echo -e "  ${D}On 1 GB servers prefer starting only 3-8 locations${N}"
  echo
  ulimit -n 65535
  for id in "${ORDER[@]}"; do
    start_one "$id" || true
    sleep 0.08
  done
  echo
  echo -e "  ${G}Done.${N}"
  read -rp "  Press Enter..."
}

stop_all() {
  header
  echo -e "  ${Y}Stopping all...${N}"
  echo
  for id in "${ORDER[@]}"; do
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
  id=$(parse "$raw") || { echo -e "  ${R}Invalid ID${N}"; sleep 1; return; }
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
  echo -e "  ${C}Toggle Sticky Exit (same exit IP as long as possible)${N}"
  echo
  for id in "${ORDER[@]}"; do
    local code name port sticky
    IFS='|' read -r code name port <<< "$(info "$id")"
    sticky=$(get_setting "$id" "sticky")
    local st="${D}off${N}"
    [[ "$sticky" == "1" ]] && st="${G}ON${N}"
    printf "  ${C}[%s]${N} %-20s %b\n" "$id" "$name" "$st"
  done
  line
  echo
  read -rp "$(echo -e "  ${C}Location ID: ${N}")" raw
  local id
  id=$(parse "$raw") || { echo -e "  ${R}Invalid${N}"; sleep 1; return; }
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
  echo -e "  ${C}Set Bandwidth Limit (MB)${N}"
  echo
  for id in "${ORDER[@]}"; do
    local code name port bw
    IFS='|' read -r code name port <<< "$(info "$id")"
    bw=$(get_setting "$id" "bandwidth")
    local disp="${D}unlimited${N}"
    [[ "$bw" != "0" ]] && disp="${G}${bw} MB${N}"
    printf "  ${C}[%s]${N} %-20s %b\n" "$id" "$name" "$disp"
  done
  line
  echo
  read -rp "$(echo -e "  ${C}Location ID: ${N}")" raw
  local id
  id=$(parse "$raw") || { echo -e "  ${R}Invalid${N}"; sleep 1; return; }
  read -rp "$(echo -e "  ${M}Bandwidth MB (0=unlimited): ${N}")" bw
  if ! [[ "$bw" =~ ^[0-9]+$ ]]; then
    echo -e "  ${R}Invalid${N}"; sleep 1; return
  fi
  set_setting "$id" "bandwidth" "$bw"
  echo -e "  ${G}Set to ${bw} MB (restart to apply)${N}"
  sleep 1.3
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
    printf "  %-18s " "$name"
    local lat
    lat=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{time_total}" \
          --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || echo "fail")
    if [[ "$lat" == "fail" ]]; then
      echo -e "${R}unreachable${N}"; continue
    fi
    local speed_raw
    speed_raw=$(curl --socks5-hostname "127.0.0.1:$port" -o /dev/null -s -w "%{speed_download}" \
                --max-time 12 "https://speed.cloudflare.com/__down?bytes=2000000" 2>/dev/null || echo "0")
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
  echo -e "  ${C}View Log (last 25 lines)${N}"
  echo
  show_running_table || true
  echo
  read -rp "$(echo -e "  ${C}Location ID: ${N}")" raw
  local id
  id=$(parse "$raw") || { echo -e "  ${R}Invalid${N}"; sleep 1; return; }
  local code name port
  IFS='|' read -r code name port <<< "$(info "$id")"
  local logfile="$LOG/${code}_${port}.log"
  if [[ ! -f "$logfile" ]]; then
    echo -e "  ${Y}No log${N}"; sleep 1; return
  fi
  echo
  line
  tail -n 25 "$logfile" | sed 's/^/  /'
  line
  echo
  read -rp "  Press Enter..."
}

uninstall() {
  header
  echo -e "  ${R}WARNING: Complete removal of tor-ml${N}"
  echo
  echo -e "  • All nodes will be killed"
  echo -e "  • $BASE will be deleted"
  echo -e "  • Command 'tor' removed"
  echo
  echo -ne "  Type ${R}YES${N} to confirm: "
  read -r conf
  if [[ "$conf" != "YES" ]]; then
    echo -e "  ${Y}Cancelled${N}"; sleep 1; return
  fi
  pkill -f "node_.*\.conf" 2>/dev/null || true
  auto_stop
  sleep 0.5
  rm -rf "$BASE"
  rm -f "$CMD"
  echo -e "  ${G}tor-ml completely removed.${N}"
  exit 0
}

install() {
  need_root
  header
  echo -e "  ${C}Installing tor-ml v3 ...${N}"
  echo

  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tor tor-geoipdb curl bc netcat-openbsd socat >/dev/null

  if ! id debian-tor &>/dev/null; then
    useradd --system --home-dir /var/lib/tor --shell /usr/sbin/nologin debian-tor 2>/dev/null || true
  fi

  systemctl stop tor 2>/dev/null || true
  systemctl disable tor 2>/dev/null || true

  mkdir -p "$CFG" "$DAT" "$LOG" "$STA"
  chown -R debian-tor:debian-tor "$DAT" "$LOG" 2>/dev/null || true

  cp "$0" "$CMD"
  chmod +x "$CMD"

  init_dirs
  migrate_settings

  echo -e "  ${G}Installation complete!${N}"
  echo -e "  Run:  ${W}tor${N}"
  echo
  sleep 2
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
main() {
  ulimit -n 65535
  init_dirs
  migrate_settings

  # Start light watchdog in background (only once)
  if ! pgrep -f "tor-ml-watchdog" >/dev/null 2>&1; then
    ( exec -a tor-ml-watchdog bash -c 'source /dev/null; while true; do sleep 90; for id in $(list_running 2>/dev/null); do code=$(info $id | cut -d\| -f1); port=$(info $id | cut -d\| -f3); running $code $port || start_one $id >/dev/null 2>&1; done; done' ) &
  fi

  while true; do
    header
    echo -e "  ${C}[1]${N}  Full Status"
    echo -e "  ${C}[2]${N}  Start Location"
    echo -e "  ${C}[3]${N}  Stop Location"
    echo -e "  ${C}[4]${N}  Start All          ${D}(use carefully on 1G)${N}"
    echo -e "  ${C}[5]${N}  Stop All"
    echo -e "  ${C}[6]${N}  Change Port"
    echo -e "  ${C}[7]${N}  Speed / Latency Test"
    echo -e "  ${C}[8]${N}  View Log"
    echo -e "  ${C}[9]${N}  Set Bandwidth"
    echo -e "  ${C}[10]${N} Toggle Sticky Exit"
    echo -e "  ${C}[11]${N} Start Auto Multi-Location (best-ping)"
    echo -e "  ${C}[12]${N} Stop Auto Multi-Location"
    echo -e "  ${R}[13]${N} Uninstall"
    echo -e "  ${Y}[0]${N}  Exit"
    echo
    read -rp "$(echo -e "  ${M}Select: ${N}")" choice
    case $choice in
      1)  full_status ;;
      2)  do_start ;;
      3)  do_stop ;;
      4)  start_all ;;
      5)  stop_all ;;
      6)  change_port ;;
      7)  speed_test ;;
      8)  view_log ;;
      9)  set_bandwidth ;;
      10) toggle_sticky ;;
      11) auto_start; sleep 1.2 ;;
      12) auto_stop; sleep 1.2 ;;
      13) uninstall ;;
      0)  clear; exit 0 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
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
