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

if [ ! -f "$STATE_FILE" ]; then
  echo "state file missing"
  exit 1
fi

ROUTING_ENABLED="$(json_bool routing_enabled "$STATE_FILE")"
[ -n "$ROUTING_ENABLED" ] || ROUTING_ENABLED="false"

ROUTING_MODE="$(grep -o '"routing_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/')"
[ -n "$ROUTING_MODE" ] || ROUTING_MODE="proxy_list"

PROXY_DOMAINS_COUNT="$(count_domains "$PROXY_DOMAINS_FILE")"
DIRECT_DOMAINS_COUNT="$(count_domains "$DIRECT_DOMAINS_FILE")"

echo "routing_enabled=$ROUTING_ENABLED"
echo "routing_mode=$ROUTING_MODE"
echo "proxy_domains_count=$PROXY_DOMAINS_COUNT"
echo "direct_domains_count=$DIRECT_DOMAINS_COUNT"