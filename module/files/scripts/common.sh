#!/system/bin/sh

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CFG_DIR="$BASE_DIR/config"
RUNTIME_DIR="$BASE_DIR/runtime"
LOG_DIR="$RUNTIME_DIR/logs"
PID_DIR="$RUNTIME_DIR/pids"
SOCK_DIR="$RUNTIME_DIR/sockets"
DNS_BIN_DIR="$BASE_DIR/bin/dns"

mkdir -p "$CFG_DIR" "$LOG_DIR" "$PID_DIR" "$SOCK_DIR"
mkdir -p "$CFG_DIR/service_modes" "$CFG_DIR/services" "$CFG_DIR/hostlists" "$CFG_DIR/ipsets"

log_msg() {
  LOG_FILE="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

pid_is_running() {
  PIDFILE="$1"
  [ -f "$PIDFILE" ] || return 1
  PID="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "$PID" ] || return 1
  kill -0 "$PID" 2>/dev/null
}

tcp_listener_ready() {
  local host="$1"
  local port="$2"

  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk -v host="$host" -v port="$port" '
      index($4, host ":" port) > 0 { found=1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk -v host="$host" -v port="$port" '
      index($4, host ":" port) > 0 { found=1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi

  return 1
}

wait_for_tcp_listener() {
  local host="$1"
  local port="$2"
  local timeout="${3:-10}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if tcp_listener_ready "$host" "$port"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

wait_for_proxy_runtime_ready() {
  local timeout="${1:-10}"
  wait_for_tcp_listener 127.0.0.1 12345 "$timeout" || return 1
  wait_for_tcp_listener 127.0.0.1 1053 "$timeout" || return 1
  return 0
}

lock_is_active() {
  local lockfile="$1"
  [ -f "$lockfile" ] || return 1
  local pid
  pid="$(cat "$lockfile" 2>/dev/null | tr -d '\r\n')"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

clear_stale_lock() {
  local lockfile="$1"
  [ -f "$lockfile" ] || return 0
  if ! lock_is_active "$lockfile"; then
    rm -f "$lockfile"
  fi
}

stop_by_pidfile() {
  NAME="$1"
  PIDFILE="$2"
  LOGFILE="$3"

  if [ ! -f "$PIDFILE" ]; then
    log_msg "$LOGFILE" "$NAME pidfile missing"
    return 0
  fi

  PID="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null
    fi
    log_msg "$LOGFILE" "$NAME stopped pid=$PID"
  else
    log_msg "$LOGFILE" "$NAME already stopped"
  fi

  rm -f "$PIDFILE"
}

json_bool() {
  KEY="$1"
  FILE="$2"
  grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*[a-z]*" "$FILE" 2>/dev/null | head -n1 | sed 's/.*:[[:space:]]*//'
}

json_string() {
  KEY="$1"
  FILE="$2"
  grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$FILE" 2>/dev/null | head -n1 | sed 's/.*:[[:space:]]*"\([^\"]*\)"/\1/'
}

get_active_profile_id() {
  ACTIVE_FILE="$CFG_DIR/active_profile.txt"
  [ -f "$ACTIVE_FILE" ] || return 1
  ACTIVE_PROFILE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"
  [ -n "$ACTIVE_PROFILE_ID" ] || return 1
  echo "$ACTIVE_PROFILE_ID"
}

get_active_profile_meta_file() {
  ACTIVE_PROFILE_ID="$(get_active_profile_id)" || return 1
  META_FILE="$CFG_DIR/profiles/$ACTIVE_PROFILE_ID/meta.conf"
  [ -f "$META_FILE" ] || return 1
  echo "$META_FILE"
}

get_active_profile_server() {
  META_FILE="$(get_active_profile_meta_file)" || return 1
  . "$META_FILE"
  [ -n "$SERVER" ] || return 1
  echo "$SERVER"
}

service_mode_files() {
  find "$CFG_DIR/service_modes" -maxdepth 1 -type f -name "*.conf" 2>/dev/null | sort
}

service_mode_file_for() {
  local service_id="$1"
  local file="$CFG_DIR/service_modes/$service_id.conf"
  [ -f "$file" ] || return 1
  echo "$file"
}

service_def_file_for() {
  local service_id="$1"
  local file="$CFG_DIR/services/$service_id.conf"
  [ -f "$file" ] || return 1
  echo "$file"
}

service_is_custom() {
  local service_id="$1"
  local def="$CFG_DIR/services/$service_id.conf"
  [ -f "$def" ] || return 1
  SERVICE_NAME=""
  CUSTOM_SERVICE="false"
  . "$def"
  [ "$CUSTOM_SERVICE" = "true" ]
}

service_mode_count() {
  MODE_FILTER="$1"
  COUNT=0
  for _f in $(service_mode_files); do
    SERVICE_ID=""; ENABLED="true"; MODE="direct"; . "$_f"
    [ "$ENABLED" = "true" ] || continue
    if [ -z "$MODE_FILTER" ] || [ "$MODE" = "$MODE_FILTER" ]; then
      COUNT=$((COUNT + 1))
    fi
  done
  echo "$COUNT"
}

expand_cfg_path() {
  local p="$1"
  p="$(printf '%s' "$p" | sed "s#\$CFG_DIR#$CFG_DIR#g; s#\$RUNTIME_DIR#$RUNTIME_DIR#g")"
  echo "$p"
}

count_non_comment_lines() {
  local file="$1"
  [ -f "$file" ] || { echo 0; return; }
  grep -v '^[[:space:]]*$' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | wc -l | tr -d ' '
}

service_auto_ipset_v4_file_for() {
  local service_id="$1"
  mkdir -p "$RUNTIME_DIR/ipsets_auto"
  echo "$RUNTIME_DIR/ipsets_auto/${service_id}.txt"
}

service_auto_ipset_v6_file_for() {
  local service_id="$1"
  mkdir -p "$RUNTIME_DIR/ipsets_auto_v6"
  echo "$RUNTIME_DIR/ipsets_auto_v6/${service_id}.txt"
}

service_auto_ipset_file_for() {
  service_auto_ipset_v4_file_for "$1"
}

service_unresolved_file_for() {
  local service_id="$1"
  mkdir -p "$RUNTIME_DIR/unresolved"
  echo "$RUNTIME_DIR/unresolved/${service_id}.txt"
}

service_conflicts_file_for() {
  local service_id="$1"
  mkdir -p "$RUNTIME_DIR/conflicts"
  echo "$RUNTIME_DIR/conflicts/${service_id}.txt"
}


network_default_route() {
  ip -4 route show default 2>/dev/null | head -n1
}

network_default_route6() {
  ip -6 route show default 2>/dev/null | head -n1
}

android_prop() {
  getprop "$1" 2>/dev/null | tr -d ''
}

network_all_global_addrs() {
  ip -o addr show 2>/dev/null | awk '$3=="inet" || $3=="inet6" {print $2"="$4}' | sort | tr '
' ',' | sed 's/,$//'
}

iface_has_nonlocal_addr() {
  local iface="$1"
  [ -n "$iface" ] || return 1
  ip -o addr show dev "$iface" 2>/dev/null | awk '
    ($3=="inet" && $4 !~ /^127\./) { found=1 }
    ($3=="inet6" && $4 !~ /^fe80:/ && $4 !~ /^::1/) { found=1 }
    END { exit found ? 0 : 1 }
  '
}

network_has_nonlocal_addrs() {
  ip -o addr show 2>/dev/null | awk '
    $2 ~ /^(lo|dummy)/ { next }
    ($3=="inet" && $4 !~ /^127\./) { found=1 }
    ($3=="inet6" && $4 !~ /^fe80:/ && $4 !~ /^::1/) { found=1 }
    END { exit found ? 0 : 1 }
  '
}

network_fingerprint() {
  local route4 route6 iface iface6 transport wifi_iface wifi_gw wifi_dns1 wifi_dns2 operator simtype all_addrs

  route4="$(network_default_route)"
  route6="$(network_default_route6)"
  iface="$(printf '%s\n' "$route4" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  iface6="$(printf '%s\n' "$route6" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [ -n "$iface" ] || iface="$iface6"

  case "$iface" in
    wlan*|wifi*) transport="wifi" ;;
    rmnet*|ccmni*|pdp*|wwan*|usb*|rndis*) transport="mobile" ;;
    eth*) transport="ethernet" ;;
    *)
      if [ -n "$iface" ] && [ "$iface" = "$(android_prop wifi.interface)" ]; then
        transport="wifi"
      elif iface_has_nonlocal_addr "$(android_prop wifi.interface)"; then
        transport="wifi"
      elif [ -n "$iface" ] && [ -n "$(android_prop gsm.operator.alpha)$(android_prop gsm.network.type)" ]; then
        transport="mobile"
      elif ip -o addr show 2>/dev/null | awk '
        $2 ~ /^(rmnet|ccmni|pdp|wwan|usb|rndis)/ &&
        (($3=="inet" && $4 !~ /^127\./) || ($3=="inet6" && $4 !~ /^fe80:/ && $4 !~ /^::1/)) { found=1 }
        END { exit found ? 0 : 1 }
      '; then
        transport="mobile"
      else
        transport="unknown"
      fi
      ;;
  esac

  wifi_iface="$(android_prop wifi.interface)"
  wifi_gw=""
  wifi_dns1=""
  wifi_dns2=""
  if [ -n "$wifi_iface" ]; then
    wifi_gw="$(android_prop dhcp.${wifi_iface}.gateway)"
    wifi_dns1="$(android_prop dhcp.${wifi_iface}.dns1)"
    wifi_dns2="$(android_prop dhcp.${wifi_iface}.dns2)"
  fi

  operator="$(android_prop gsm.operator.alpha)"
  simtype="$(android_prop gsm.network.type)"
  all_addrs="$(network_all_global_addrs)"

  case "$transport" in
    wifi)
      printf 'wifi|iface=%s|route4=%s|route6=%s|gw=%s|dns1=%s|dns2=%s|addrs=%s\n' \
        "$iface" "$route4" "$route6" "$wifi_gw" "$wifi_dns1" "$wifi_dns2" "$all_addrs"
      ;;
    mobile)
      printf 'mobile|iface=%s|route4=%s|route6=%s|operator=%s|type=%s|addrs=%s\n' \
        "$iface" "$route4" "$route6" "$operator" "$simtype" "$all_addrs"
      ;;
    ethernet)
      printf 'ethernet|iface=%s|route4=%s|route6=%s|addrs=%s\n' "$iface" "$route4" "$route6" "$all_addrs"
      ;;
    *)
      printf 'unknown|iface=%s|route4=%s|route6=%s|wifi_iface=%s|operator=%s|type=%s|addrs=%s\n' \
        "$iface" "$route4" "$route6" "$wifi_iface" "$operator" "$simtype" "$all_addrs"
      ;;
  esac
}

network_cache_key() {
  network_fingerprint | cksum | awk '{print $1}'
}

current_network_cache_key() {
  mkdir -p "$RUNTIME_DIR/network"
  local key fpfile rawfile
  key="$(network_cache_key)"
  fpfile="$RUNTIME_DIR/network/current_key.txt"
  rawfile="$RUNTIME_DIR/network/current_fingerprint.txt"
  printf '%s
' "$key" > "$fpfile"
  network_fingerprint > "$rawfile"
  printf '%s
' "$key"
}

wait_for_network_ready() {
  local timeout="${1:-5}"
  local elapsed=0
  local route4 route6 fp

  while [ "$elapsed" -lt "$timeout" ]; do
    route4="$(network_default_route)"
    route6="$(network_default_route6)"
    fp="$(network_fingerprint)"

    if [ -n "$fp" ] && { [ -n "$route4" ] || [ -n "$route6" ] || network_has_nonlocal_addrs; }; then
      return 0
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

service_network_cache_dir_for() {
  local service_id="$1"
  mkdir -p "$RUNTIME_DIR/network_cache/$service_id"
  echo "$RUNTIME_DIR/network_cache/$service_id"
}

service_hostlists_signature() {
  local service_id="$1"
  local mode_file hostlist sig target
  mode_file="$(service_mode_file_for "$service_id" 2>/dev/null)" || { echo none; return; }
  SERVICE_ID=""; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; . "$mode_file"
  for target in "$TCP_HOSTLIST" "$UDP_HOSTLIST" "$STUN_HOSTLIST"; do
    target="$(expand_cfg_path "$target")"
    [ -n "$target" ] || continue
    if [ -f "$target" ]; then
      cksum "$target" 2>/dev/null
    else
      printf 'missing %s
' "$target"
    fi
  done | cksum | awk '{print $1}'
}
dns_helper_bin() {
  echo "$DNS_BIN_DIR/dnsresolve"
}
