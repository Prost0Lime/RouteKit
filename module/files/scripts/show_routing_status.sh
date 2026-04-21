#!/system/bin/sh
. "$(dirname "$0")/common.sh"

STATE_FILE="$CFG_DIR/app_state.json"
PROXY_DOMAINS_FILE="$CFG_DIR/proxy_domains.txt"
DIRECT_DOMAINS_FILE="$CFG_DIR/direct_domains.txt"

count_domains() {
  FILE="$1"
  if [ ! -f "$FILE" ]; then
    echo "0"
    return
  fi
  grep -v '^[[:space:]]*$' "$FILE" | grep -v '^[[:space:]]*#' | wc -l | tr -d ' '
}

ROUTING_ENABLED="false"
ROUTING_MODE="proxy_list"

PROXY_STATE="stopped"
TRANSPROXY_STATE="disabled"
IPV6_BLOCK_STATE="disabled"

ACTIVE_PROFILE_ID=""
ACTIVE_PROFILE_NAME=""
ACTIVE_PROFILE_SERVER=""

PROXY_DOMAINS_COUNT="0"
DIRECT_DOMAINS_COUNT="0"

if [ -f "$STATE_FILE" ]; then
  ROUTING_ENABLED="$(json_bool routing_enabled "$STATE_FILE")"
  [ -n "$ROUTING_ENABLED" ] || ROUTING_ENABLED="false"

  ROUTING_MODE="$(grep -o '"routing_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/')"
  [ -n "$ROUTING_MODE" ] || ROUTING_MODE="proxy_list"
fi

if pid_is_running "$PID_DIR/proxy.pid"; then
  PROXY_STATE="running"
fi

if iptables -t nat -S OUTPUT 2>/dev/null | grep -q -- "-A OUTPUT -p tcp -j ZAPRET2_TRANS"; then
  TRANSPROXY_STATE="enabled"
fi

if ip6tables -S OUTPUT 2>/dev/null | grep -q -- "-A OUTPUT -j ZAPRET2_V6_BLOCK"; then
  IPV6_BLOCK_STATE="enabled"
fi

ACTIVE_PROFILE_ID="$(get_active_profile_id 2>/dev/null)"
if [ -n "$ACTIVE_PROFILE_ID" ]; then
  META_FILE="$CFG_DIR/profiles/$ACTIVE_PROFILE_ID/meta.conf"
  if [ -f "$META_FILE" ]; then
    . "$META_FILE"
    ACTIVE_PROFILE_NAME="$PROFILE_NAME"
    ACTIVE_PROFILE_SERVER="$SERVER"
  fi
fi

PROXY_DOMAINS_COUNT="$(count_domains "$PROXY_DOMAINS_FILE")"
DIRECT_DOMAINS_COUNT="$(count_domains "$DIRECT_DOMAINS_FILE")"

echo "routing_enabled=$ROUTING_ENABLED"
echo "routing_mode=$ROUTING_MODE"
echo "proxy_domains_count=$PROXY_DOMAINS_COUNT"
echo "direct_domains_count=$DIRECT_DOMAINS_COUNT"
echo "active_profile_name=$ACTIVE_PROFILE_NAME"
echo "active_profile_server=$ACTIVE_PROFILE_SERVER"
echo "proxy=$PROXY_STATE"
echo "transproxy=$TRANSPROXY_STATE"
echo "ipv6_block=$IPV6_BLOCK_STATE"