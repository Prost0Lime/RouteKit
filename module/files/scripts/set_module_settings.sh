#!/system/bin/sh
. "$(dirname "$0")/common.sh"

COLLECT_IPV6=""
DNS_RESOLVE_REPEAT=""
IPV6_BLOCK_ENABLED=""

while [ $# -gt 0 ]; do
  case "$1" in
    collect_ipv6=*) COLLECT_IPV6="${1#collect_ipv6=}" ;;
    dns_repeat=*) DNS_RESOLVE_REPEAT="${1#dns_repeat=}" ;;
    ipv6_block=*) IPV6_BLOCK_ENABLED="${1#ipv6_block=}" ;;
  esac
  shift
done

case "$COLLECT_IPV6" in true|false) ;; *) COLLECT_IPV6="$(module_setting_bool COLLECT_IPV6 true)" ;; esac
case "$IPV6_BLOCK_ENABLED" in true|false) ;; *) IPV6_BLOCK_ENABLED="";; esac
case "$DNS_RESOLVE_REPEAT" in
  ''|*[!0-9]*) DNS_RESOLVE_REPEAT="$(module_setting_int DNS_RESOLVE_REPEAT 3 1 10)" ;;
esac
[ "$DNS_RESOLVE_REPEAT" -lt 1 ] 2>/dev/null && DNS_RESOLVE_REPEAT=1
[ "$DNS_RESOLVE_REPEAT" -gt 10 ] 2>/dev/null && DNS_RESOLVE_REPEAT=10

mkdir -p "$CFG_DIR"
cat > "$SETTINGS_FILE" <<EOT
COLLECT_IPV6="$COLLECT_IPV6"
DNS_RESOLVE_REPEAT="$DNS_RESOLVE_REPEAT"
EOT

STATE="$CFG_DIR/app_state.json"
if [ -n "$IPV6_BLOCK_ENABLED" ]; then
  sh "$(dirname "$0")/recompute_app_state.sh" >/dev/null 2>&1
  TMP="$STATE.tmp"
  if grep -q '"ipv6_block_enabled"' "$STATE" 2>/dev/null; then
    sed 's/"ipv6_block_enabled"[[:space:]]*:[[:space:]]*[^,]*/"ipv6_block_enabled": '"$IPV6_BLOCK_ENABLED"'/' "$STATE" > "$TMP" && mv "$TMP" "$STATE"
  else
    sed 's/}$/,\n  "ipv6_block_enabled": '"$IPV6_BLOCK_ENABLED"'\n}/' "$STATE" > "$TMP" && mv "$TMP" "$STATE"
  fi
  if [ "$IPV6_BLOCK_ENABLED" = "true" ]; then
    sh "$(dirname "$0")/apply_ipv6_block.sh" >/dev/null 2>&1
  else
    sh "$(dirname "$0")/clear_ipv6_block.sh" >/dev/null 2>&1
  fi
fi

mark_service_apply_dirty full
echo ok
