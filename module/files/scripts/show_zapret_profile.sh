#!/system/bin/sh
. "$(dirname "$0")/common.sh"

STATE_FILE="$CFG_DIR/app_state.json"

PROFILE_ID=""
if [ -f "$STATE_FILE" ]; then
  PROFILE_ID="$(grep -o '"selected_zapret_profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/')"
fi

[ -n "$PROFILE_ID" ] || PROFILE_ID="default"

PROFILE_FILE="$CFG_DIR/zapret_profiles/$PROFILE_ID.conf"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "error=zapret_profile_not_found"
  echo "profile_id=$PROFILE_ID"
  exit 1
fi

PROFILE_NAME=""
ENGINE=""
ENABLED=""
TCP_PORTS=""
UDP_PORTS=""
MODE=""

PRESET_FILE=""
TCP_STRATEGY=""
UDP_STRATEGY=""
STUN_STRATEGY=""
TCP_HOSTLIST=""
TCP_IPSET=""
UDP_HOSTLIST=""
UDP_IPSET=""

NFQWS2_BIN=""
NFQWS2_DEBUG=""
NFQWS2_QNUM=""
NFQWS2_INTERCEPT=""
NFQWS2_DRY_RUN=""
NFQWS2_FILTER_TCP=""
NFQWS2_FILTER_UDP=""
NFQWS2_ARGS=""
ARGS=""

. "$PROFILE_FILE"

echo "profile_id=$PROFILE_ID"
echo "profile_name=$PROFILE_NAME"
echo "engine=$ENGINE"
echo "enabled=$ENABLED"
echo "tcp_ports=$TCP_PORTS"
echo "udp_ports=$UDP_PORTS"
echo "mode=$MODE"

echo "preset_file=$PRESET_FILE"
echo "tcp_strategy=$TCP_STRATEGY"
echo "udp_strategy=$UDP_STRATEGY"
echo "stun_strategy=$STUN_STRATEGY"
echo "tcp_hostlist=$TCP_HOSTLIST"
echo "tcp_ipset=$TCP_IPSET"
echo "udp_hostlist=$UDP_HOSTLIST"
echo "udp_ipset=$UDP_IPSET"

echo "nfqws2_bin=$NFQWS2_BIN"
echo "nfqws2_debug=$NFQWS2_DEBUG"
echo "nfqws2_qnum=$NFQWS2_QNUM"
echo "nfqws2_intercept=$NFQWS2_INTERCEPT"
echo "nfqws2_dry_run=$NFQWS2_DRY_RUN"
echo "nfqws2_filter_tcp=$NFQWS2_FILTER_TCP"
echo "nfqws2_filter_udp=$NFQWS2_FILTER_UDP"
echo "nfqws2_args=$NFQWS2_ARGS"
echo "args=$ARGS"