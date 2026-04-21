#!/system/bin/sh

BASE_DIR="${0%/*/*/*}"
LOGFILE="$BASE_DIR/runtime/logs/zapret.log"

mkdir -p "$BASE_DIR/runtime/logs"

echo "[nfqws2-runner] started" >> "$LOGFILE"
echo "[nfqws2-runner] profile_id=$ZAPRET_PROFILE_ID" >> "$LOGFILE"
echo "[nfqws2-runner] profile_name=$ZAPRET_PROFILE_NAME" >> "$LOGFILE"
echo "[nfqws2-runner] engine=$ZAPRET_ENGINE" >> "$LOGFILE"
echo "[nfqws2-runner] tcp_ports=$ZAPRET_TCP_PORTS" >> "$LOGFILE"
echo "[nfqws2-runner] udp_ports=$ZAPRET_UDP_PORTS" >> "$LOGFILE"
echo "[nfqws2-runner] mode=$ZAPRET_MODE" >> "$LOGFILE"
echo "[nfqws2-runner] nfqws2_bin=$ZAPRET_NFQWS2_BIN" >> "$LOGFILE"
echo "[nfqws2-runner] nfqws2_args=$ZAPRET_NFQWS2_ARGS" >> "$LOGFILE"
echo "[nfqws2-runner] preset_file=$ZAPRET_PRESET_FILE" >> "$LOGFILE"
echo "[nfqws2-runner] tcp_strategy=$ZAPRET_TCP_STRATEGY" >> "$LOGFILE"
echo "[nfqws2-runner] udp_strategy=$ZAPRET_UDP_STRATEGY" >> "$LOGFILE"
echo "[nfqws2-runner] stun_strategy=$ZAPRET_STUN_STRATEGY" >> "$LOGFILE"
echo "[nfqws2-runner] tcp_hostlist=$ZAPRET_TCP_HOSTLIST" >> "$LOGFILE"
echo "[nfqws2-runner] tcp_ipset=$ZAPRET_TCP_IPSET" >> "$LOGFILE"
echo "[nfqws2-runner] udp_hostlist=$ZAPRET_UDP_HOSTLIST" >> "$LOGFILE"
echo "[nfqws2-runner] udp_ipset=$ZAPRET_UDP_IPSET" >> "$LOGFILE"
echo "[nfqws2-runner] args=$ZAPRET_ARGS" >> "$LOGFILE"

BIN_PATH="$BASE_DIR/bin/zapret/$ZAPRET_NFQWS2_BIN"
STRATEGY_DIR="$BASE_DIR/config/strategies"
TCP_INI="$STRATEGY_DIR/strategies-tcp.ini"
UDP_INI="$STRATEGY_DIR/strategies-udp.ini"
STUN_INI="$STRATEGY_DIR/strategies-stun.ini"
BLOBS_FILE="$BASE_DIR/bin/zapret/blobs.txt"
SERVICE_MODES_DIR="$BASE_DIR/config/service_modes"
CFG_DIR="$BASE_DIR/config"

get_ini_args() {
  ini_file="$1"
  section="$2"
  [ -n "$ini_file" ] || return 1
  [ -f "$ini_file" ] || return 1
  [ -n "$section" ] || return 1
  awk -v sec="$section" '
    BEGIN { in_sec=0 }
    $0 ~ "^[[:space:]]*\\[" sec "\\][[:space:]]*$" { in_sec=1; next }
    in_sec && $0 ~ "^[[:space:]]*\\[" { exit }
    in_sec && $0 ~ /^args=/ {
      sub(/^args=/, "", $0)
      print
      exit
    }
  ' "$ini_file"
}

append_filter_ports() {
  proto="$1"
  ports="$2"
  [ -n "$ports" ] || return 0
  oldifs="$IFS"
  IFS=','
  for p in $ports; do
    p="$(echo "$p" | tr -d '[:space:]\r')"
    [ -n "$p" ] || continue
    if [ "$proto" = "tcp" ]; then
      CMD="$CMD --filter-tcp=$p"
    else
      CMD="$CMD --filter-udp=$p"
    fi
  done
  IFS="$oldifs"
}

append_selector() {
  hostlist="$1"
  ipset="$2"
  if [ -n "$hostlist" ]; then
    CMD="$CMD --hostlist=$hostlist"
  elif [ -n "$ipset" ]; then
    CMD="$CMD --ipset=$ipset"
  fi
}

normalize_selector_path() {
  path="$1"
  case "$path" in
    "") echo "" ;;&
    /hostlists/*|/ipsets/*) echo "$CFG_DIR$path" ;;&
    *) echo "$path" ;;&
  esac
}

append_blobs() {
  [ -f "$BLOBS_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if echo "$line" | grep -q '@bin/'; then
      line="$(echo "$line" | sed "s#@bin/#@$BASE_DIR/bin/zapret/bin/#g")"
    fi
    if echo "$line" | grep -q '@lua/'; then
      line="$(echo "$line" | sed "s#@lua/#@$BASE_DIR/bin/zapret/lua/#g")"
    fi
    CMD="$CMD $line"
  done < "$BLOBS_FILE"
}

service_mode_files() {
  find "$SERVICE_MODES_DIR" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort
}

add_section() {
  proto="$1"
  ports="$2"
  hostlist="$3"
  ipset="$4"
  strat="$5"
  layer="$6"
  service_id="$7"
  [ -n "$strat" ] || return 0

  case "$layer" in
    tcp) strat_args="$(get_ini_args "$TCP_INI" "$strat" | tr -d '\r')" ;;
    udp) strat_args="$(get_ini_args "$UDP_INI" "$strat" | tr -d '\r')" ;;
    stun) strat_args="$(get_ini_args "$STUN_INI" "$strat" | tr -d '\r')" ;;
    *) strat_args="" ;;
  esac
  [ -n "$strat_args" ] || return 0

  [ "$SECTION_COUNT" -gt 0 ] && CMD="$CMD --new"

  case "$proto" in
    tcp)
      if [ -n "$ports" ]; then append_filter_ports tcp "$ports"; else CMD="$CMD --filter-tcp=443"; fi
      ;;
    udp)
      if [ -n "$ports" ]; then append_filter_ports udp "$ports"; else CMD="$CMD --filter-udp=443"; fi
      ;;
  esac

  hostlist="$(normalize_selector_path "$hostlist")"
  ipset="$(normalize_selector_path "$ipset")"
  append_selector "$hostlist" "$ipset"
  CMD="$CMD $strat_args"
  SECTION_COUNT=$((SECTION_COUNT + 1))
  echo "[nfqws2-runner] service_section=$service_id/$layer strategy=$strat hostlist=$hostlist ipset=$ipset" >> "$LOGFILE"
}

if [ ! -f "$BIN_PATH" ]; then
  echo "[nfqws2-runner] nfqws2 binary missing: $BIN_PATH" >> "$LOGFILE"
  exit 1
fi

chmod 0755 "$BIN_PATH" 2>/dev/null
echo "[nfqws2-runner] nfqws2 binary found: $BIN_PATH" >> "$LOGFILE"

PRESET_ARGS=""
if [ -n "$ZAPRET_PRESET_FILE" ] && [ -f "$ZAPRET_PRESET_FILE" ]; then
  PRESET_ARGS="$(cat "$ZAPRET_PRESET_FILE" | tr -d '\r')"
fi

TCP_STRATEGY_ARGS=""
UDP_STRATEGY_ARGS=""
STUN_STRATEGY_ARGS=""
[ -n "$ZAPRET_TCP_STRATEGY" ] && TCP_STRATEGY_ARGS="$(get_ini_args "$TCP_INI" "$ZAPRET_TCP_STRATEGY" | tr -d '\r')"
[ -n "$ZAPRET_UDP_STRATEGY" ] && UDP_STRATEGY_ARGS="$(get_ini_args "$UDP_INI" "$ZAPRET_UDP_STRATEGY" | tr -d '\r')"
[ -n "$ZAPRET_STUN_STRATEGY" ] && STUN_STRATEGY_ARGS="$(get_ini_args "$STUN_INI" "$ZAPRET_STUN_STRATEGY" | tr -d '\r')"

echo "[nfqws2-runner] tcp_strategy_args=$TCP_STRATEGY_ARGS" >> "$LOGFILE"
echo "[nfqws2-runner] udp_strategy_args=$UDP_STRATEGY_ARGS" >> "$LOGFILE"
echo "[nfqws2-runner] stun_strategy_args=$STUN_STRATEGY_ARGS" >> "$LOGFILE"

CMD="$BIN_PATH"
[ -n "$ZAPRET_NFQWS2_DEBUG" ] && CMD="$CMD --debug=$ZAPRET_NFQWS2_DEBUG"
[ -n "$ZAPRET_NFQWS2_QNUM" ] && CMD="$CMD --qnum=$ZAPRET_NFQWS2_QNUM"
CMD="$CMD --fwmark=0x40000000"
CMD="$CMD --uid=0:0"
CMD="$CMD --ipcache-lifetime=84600 --ipcache-hostname=1"

LUA_LIB="$BASE_DIR/bin/zapret/lua/zapret-lib.lua"
LUA_ANTIDPI="$BASE_DIR/bin/zapret/lua/zapret-antidpi.lua"
LUA_AUTO="$BASE_DIR/bin/zapret/lua/zapret-auto.lua"
LUA_CUSTOM="$BASE_DIR/bin/zapret/lua/custom_funcs.lua"
LUA_MULTI="$BASE_DIR/bin/zapret/lua/zapret-multishake.lua"
CMD="$CMD --lua-init=@$LUA_LIB --lua-init=@$LUA_ANTIDPI"
[ -f "$LUA_AUTO" ] && CMD="$CMD --lua-init=@$LUA_AUTO"
[ -f "$LUA_CUSTOM" ] && CMD="$CMD --lua-init=@$LUA_CUSTOM"
[ -f "$LUA_MULTI" ] && CMD="$CMD --lua-init=@$LUA_MULTI"
append_blobs

MODE_SOURCE=""
SECTION_COUNT=0
SERVICE_MODE_COUNT=0

for _f in $(service_mode_files); do
  SERVICE_ID=""
  ENABLED="true"
  MODE="direct"
  TCP_STRATEGY=""
  UDP_STRATEGY=""
  STUN_STRATEGY=""
  TCP_HOSTLIST=""
  TCP_IPSET=""
  UDP_HOSTLIST=""
  UDP_IPSET=""
  STUN_HOSTLIST=""
  STUN_IPSET=""
  . "$_f"
  [ "$ENABLED" = "true" ] || continue
  [ "$MODE" = "zapret" ] || continue
  SERVICE_MODE_COUNT=$((SERVICE_MODE_COUNT + 1))
  add_section tcp "$ZAPRET_TCP_PORTS" "$TCP_HOSTLIST" "$TCP_IPSET" "$TCP_STRATEGY" tcp "$SERVICE_ID"
  add_section udp "$ZAPRET_UDP_PORTS" "$UDP_HOSTLIST" "$UDP_IPSET" "$UDP_STRATEGY" udp "$SERVICE_ID"
  add_section udp "$ZAPRET_UDP_PORTS" "$STUN_HOSTLIST" "$STUN_IPSET" "$STUN_STRATEGY" stun "$SERVICE_ID"
done

if [ "$SECTION_COUNT" -gt 0 ]; then
  MODE_SOURCE="service_modes"
  echo "[nfqws2-runner] service_mode_count=$SERVICE_MODE_COUNT" >> "$LOGFILE"
elif [ -n "$ZAPRET_NFQWS2_ARGS" ]; then
  MODE_SOURCE="nfqws2_args"
  CMD="$CMD $ZAPRET_NFQWS2_ARGS"
elif [ -n "$PRESET_ARGS" ]; then
  MODE_SOURCE="preset_file"
  CMD="$CMD $PRESET_ARGS"
else
  MODE_SOURCE="strategy_registry"
  if [ -n "$TCP_STRATEGY_ARGS" ]; then
    append_filter_ports tcp "$ZAPRET_TCP_PORTS"
    [ -z "$ZAPRET_TCP_PORTS" ] && CMD="$CMD --filter-tcp=443"
    append_selector "$(normalize_selector_path "$ZAPRET_TCP_HOSTLIST")" "$(normalize_selector_path "$ZAPRET_TCP_IPSET")"
    CMD="$CMD $TCP_STRATEGY_ARGS"
    SECTION_COUNT=$((SECTION_COUNT + 1))
  fi
  if [ -n "$UDP_STRATEGY_ARGS" ]; then
    [ "$SECTION_COUNT" -gt 0 ] && CMD="$CMD --new"
    append_filter_ports udp "$ZAPRET_UDP_PORTS"
    [ -z "$ZAPRET_UDP_PORTS" ] && CMD="$CMD --filter-udp=443"
    append_selector "$(normalize_selector_path "$ZAPRET_UDP_HOSTLIST")" "$(normalize_selector_path "$ZAPRET_UDP_IPSET")"
    CMD="$CMD $UDP_STRATEGY_ARGS"
    SECTION_COUNT=$((SECTION_COUNT + 1))
  fi
  if [ -n "$STUN_STRATEGY_ARGS" ]; then
    [ "$SECTION_COUNT" -gt 0 ] && CMD="$CMD --new"
    CMD="$CMD $STUN_STRATEGY_ARGS"
    SECTION_COUNT=$((SECTION_COUNT + 1))
  fi
fi

[ -n "$ZAPRET_ARGS" ] && CMD="$CMD $ZAPRET_ARGS"

echo "[nfqws2-runner] mode_source=$MODE_SOURCE" >> "$LOGFILE"
echo "[nfqws2-runner] command=$CMD" >> "$LOGFILE"
echo "[nfqws2-runner] starting real backend..." >> "$LOGFILE"
exec sh -c "exec $CMD" >> "$LOGFILE" 2>&1
