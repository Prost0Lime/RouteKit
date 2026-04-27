#!/system/bin/sh
. "$(dirname "$0")/common.sh"

ensure_module_settings
STATE="$CFG_DIR/app_state.json"
COLLECT_IPV6="$(module_setting_bool COLLECT_IPV6 true)"
DNS_RESOLVE_REPEAT="$(module_setting_int DNS_RESOLVE_REPEAT 3 1 10)"
IPV6_BLOCK_ENABLED="false"
[ -f "$STATE" ] && IPV6_BLOCK_ENABLED="$(json_bool ipv6_block_enabled "$STATE")"
[ -n "$IPV6_BLOCK_ENABLED" ] || IPV6_BLOCK_ENABLED="false"

echo "COLLECT_IPV6=\"$COLLECT_IPV6\""
echo "DNS_RESOLVE_REPEAT=\"$DNS_RESOLVE_REPEAT\""
echo "IPV6_BLOCK_ENABLED=\"$IPV6_BLOCK_ENABLED\""
