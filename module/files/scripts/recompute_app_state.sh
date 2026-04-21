#!/system/bin/sh
. "$(dirname "$0")/common.sh"

STATE_FILE="$CFG_DIR/app_state.json"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
LOGFILE="$LOG_DIR/service-modes.log"

mkdir -p "$CFG_DIR"
[ -f "$STATE_FILE" ] || cat > "$STATE_FILE" <<EOT
{
  "zapret_enabled": false,
  "proxy_enabled": false,
  "routing_enabled": false,
  "routing_mode": "proxy_list",
  "transproxy_enabled": false,
  "ipv6_block_enabled": false,
  "dns_redirect_enabled": false,
  "selected_zapret_profile": "default",
  "selected_proxy_group": "default"
}
EOT

VPN_COUNT="$(service_mode_count vpn)"
ZAPRET_COUNT="$(service_mode_count zapret)"
ACTIVE_PROFILE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"
HAS_ACTIVE=false
if [ -n "$ACTIVE_PROFILE" ] && [ -f "$CFG_DIR/profiles/$ACTIVE_PROFILE/meta.conf" ]; then
  HAS_ACTIVE=true
fi

CURRENT_ROUTING_MODE="$(json_string routing_mode "$STATE_FILE")"
[ -n "$CURRENT_ROUTING_MODE" ] || CURRENT_ROUTING_MODE="proxy_list"

[ "$ZAPRET_COUNT" -gt 0 ] && ZAPRET_BOOL=true || ZAPRET_BOOL=false
if [ "$VPN_COUNT" -gt 0 ] && [ "$HAS_ACTIVE" = "true" ]; then
  PROXY_BOOL=true
  ROUTING_BOOL=true
  TRANSPROXY_BOOL=true
  DNS_REDIRECT_BOOL=true
else
  PROXY_BOOL=false
  ROUTING_BOOL=false
  TRANSPROXY_BOOL=false
  DNS_REDIRECT_BOOL=false
fi

TMP_FILE="${STATE_FILE}.tmp"
sed \
  -e 's/"zapret_enabled"[[:space:]]*:[[:space:]]*[^,]*/"zapret_enabled": '__ZAPRET__'/' \
  -e 's/"proxy_enabled"[[:space:]]*:[[:space:]]*[^,]*/"proxy_enabled": '__PROXY__'/' \
  -e 's/"routing_enabled"[[:space:]]*:[[:space:]]*[^,]*/"routing_enabled": '__ROUTING__'/' \
  -e 's/"transproxy_enabled"[[:space:]]*:[[:space:]]*[^,]*/"transproxy_enabled": '__TRANSPROXY__'/' \
  -e 's/"dns_redirect_enabled"[[:space:]]*:[[:space:]]*[^,]*/"dns_redirect_enabled": '__DNS_REDIRECT__'/' \
  -e 's/"routing_mode"[[:space:]]*:[[:space:]]*"[^"]*"/"routing_mode": "__ROUTING_MODE__"/' \
  "$STATE_FILE" \
  | sed \
      -e "s/__ZAPRET__/$ZAPRET_BOOL/" \
      -e "s/__PROXY__/$PROXY_BOOL/" \
      -e "s/__ROUTING__/$ROUTING_BOOL/" \
      -e "s/__TRANSPROXY__/$TRANSPROXY_BOOL/" \
      -e "s/__DNS_REDIRECT__/$DNS_REDIRECT_BOOL/" \
      -e "s/__ROUTING_MODE__/$CURRENT_ROUTING_MODE/" \
  > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"

log_msg "$LOGFILE" "recompute_app_state vpn_count=$VPN_COUNT zapret_count=$ZAPRET_COUNT has_active=$HAS_ACTIVE proxy=$PROXY_BOOL routing=$ROUTING_BOOL transproxy=$TRANSPROXY_BOOL dns_redirect=$DNS_REDIRECT_BOOL routing_mode=$CURRENT_ROUTING_MODE"
