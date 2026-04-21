#!/system/bin/sh
. "$(dirname "$0")/common.sh"

PROFILE_ID="$1"
[ -n "$PROFILE_ID" ] || { echo "usage: $0 <profile_id>"; exit 1; }

META_FILE="$CFG_DIR/profiles/$PROFILE_ID/meta.conf"
[ -f "$META_FILE" ] || { echo "profile not found: $PROFILE_ID"; exit 1; }

PROFILE_NAME=""
SERVER=""
PORT=""
UUID=""
SNI=""
FLOW=""
GROUP_ID=""
. "$META_FILE"

ACTIVE_ID="$(cat "$CFG_DIR/active_profile.txt" 2>/dev/null | tr -d '\r\n')"
IS_ACTIVE="false"
[ "$PROFILE_ID" = "$ACTIVE_ID" ] && IS_ACTIVE="true"

GROUP_NAME="$GROUP_ID"
if [ -n "$GROUP_ID" ] && [ -f "$CFG_DIR/groups/$GROUP_ID/name.txt" ]; then
  GROUP_NAME="$(cat "$CFG_DIR/groups/$GROUP_ID/name.txt" 2>/dev/null | tr -d '\r\n')"
fi
[ -n "$GROUP_NAME" ] || GROUP_NAME="-"
GROUP_ID_OUT="$GROUP_ID"
[ -n "$GROUP_ID_OUT" ] || GROUP_ID_OUT="-"

APP_STATE="$CFG_DIR/app_state.json"
PROXY_ENABLED="false"
TRANSPROXY_ENABLED="false"
DNS_REDIRECT_ENABLED="false"
IPV6_BLOCK_ENABLED="false"
if [ -f "$APP_STATE" ]; then
  PROXY_ENABLED="$(json_bool proxy_enabled "$APP_STATE")"
  TRANSPROXY_ENABLED="$(json_bool transproxy_enabled "$APP_STATE")"
  DNS_REDIRECT_ENABLED="$(json_bool dns_redirect_enabled "$APP_STATE")"
  IPV6_BLOCK_ENABLED="$(json_bool ipv6_block_enabled "$APP_STATE")"
fi

CONFIG_SERVER=""
CONFIG_PORT=""
if [ -f "$CFG_DIR/proxy.json" ]; then
  CONFIG_SERVER="$(awk -F'"' '/"server"[[:space:]]*:/ {print $4; exit}' "$CFG_DIR/proxy.json" 2>/dev/null)"
  CONFIG_PORT="$(awk -F'[:,]' '/"server_port"[[:space:]]*:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$CFG_DIR/proxy.json" 2>/dev/null)"
fi
CONFIG_SERVER_OUT="$CONFIG_SERVER"
CONFIG_PORT_OUT="$CONFIG_PORT"
[ -n "$CONFIG_SERVER_OUT" ] || CONFIG_SERVER_OUT="<empty>"
[ -n "$CONFIG_PORT_OUT" ] || CONFIG_PORT_OUT="<empty>"

CONFIG_MATCH="n/a"
if [ "$IS_ACTIVE" = "true" ]; then
  CONFIG_MATCH="false"
  [ "$CONFIG_SERVER" = "$SERVER" ] && [ "$CONFIG_PORT" = "$PORT" ] && CONFIG_MATCH="true"
fi

PING_MS="timeout"
if [ -n "$SERVER" ]; then
  ping_out="$(ping -c 1 -W 2 "$SERVER" 2>/dev/null)"
  ping_ms="$(printf '%s\n' "$ping_out" | awk -F'time=' '/time=/{ split($2,a," "); printf "%d", a[1] + 0; exit }')"
  [ -n "$ping_ms" ] && PING_MS="$ping_ms"
fi

listener_text=""
if command -v ss >/dev/null 2>&1; then
  listener_text="$(ss -lntup 2>/dev/null)"
elif command -v netstat >/dev/null 2>&1; then
  listener_text="$(netstat -lntup 2>/dev/null)"
fi
proxy_12345="missing"
dns_1053_udp="missing"
dns_1053_tcp="missing"
printf '%s\n' "$listener_text" | grep -q ':12345' && proxy_12345="ok"
printf '%s\n' "$listener_text" | grep -q 'udp.*:1053' && dns_1053_udp="ok"
printf '%s\n' "$listener_text" | grep -q 'tcp.*:1053' && dns_1053_tcp="ok"

proxy_process="stopped"
pid_is_running "$PID_DIR/proxy.pid" && proxy_process="running"

dns_state="missing"
[ -f "$RUNTIME_DIR/dns_redirect.enabled" ] && dns_state="enabled"
transproxy_state="missing"
[ -f "$RUNTIME_DIR/transproxy.enabled" ] && transproxy_state="enabled"

server_exclusion_nat="n/a"
server_exclusion_udp="n/a"
case "$SERVER" in
  *.*.*.*)
    server_exclusion_nat="missing"
    server_exclusion_udp="missing"
    iptables -t nat -C ZAPRET2_TRANS -d "$SERVER/32" -j RETURN 2>/dev/null && server_exclusion_nat="ok"
    iptables -C ZAPRET2_UDP_REJECT -d "$SERVER/32" -j RETURN 2>/dev/null && server_exclusion_udp="ok"
    ;;
esac

status="OK"
recommendations=""

if [ -z "$SERVER" ] || [ -z "$PORT" ] || [ -z "$UUID" ]; then
  status="FAIL"
  recommendations="${recommendations}- Profile metadata is incomplete.\n"
fi

if [ "$IS_ACTIVE" = "true" ] && [ "$PROXY_ENABLED" = "true" ] && [ "$proxy_process" != "running" ]; then
  status="FAIL"
  recommendations="${recommendations}- Active profile is selected, but proxy process is not running.\n"
fi

if [ "$IS_ACTIVE" = "true" ] && [ "$PROXY_ENABLED" = "true" ] && [ "$CONFIG_MATCH" != "true" ]; then
  status="FAIL"
  recommendations="${recommendations}- proxy.json does not match this active profile.\n"
fi

if [ "$IS_ACTIVE" = "true" ] && [ "$PROXY_ENABLED" = "true" ] && [ "$proxy_12345" != "ok" ]; then
  status="FAIL"
  recommendations="${recommendations}- Proxy redirect listener 127.0.0.1:12345 is missing.\n"
fi

if [ "$IS_ACTIVE" = "true" ] && [ "$DNS_REDIRECT_ENABLED" = "true" ] && { [ "$dns_1053_udp" != "ok" ] || [ "$dns_1053_tcp" != "ok" ]; }; then
  [ "$status" = "OK" ] && status="WARN"
  recommendations="${recommendations}- DNS listener 127.0.0.1:1053 is incomplete.\n"
fi

if [ "$IS_ACTIVE" = "true" ] && [ "$TRANSPROXY_ENABLED" = "true" ] && [ "$server_exclusion_nat" = "missing" ]; then
  [ "$status" = "OK" ] && status="WARN"
  recommendations="${recommendations}- Transproxy server exclusion is missing for this server IP.\n"
fi

if [ "$PING_MS" = "timeout" ]; then
  recommendations="${recommendations}- ICMP ping timed out; this can be normal if the server blocks ping.\n"
fi

echo "SUMMARY"
echo "status=$status"
[ -n "$recommendations" ] && printf 'recommendations:\n%b' "$recommendations" || echo "recommendations=<empty>"
echo

echo "PROFILE"
echo "id=$PROFILE_ID"
echo "name=$PROFILE_NAME"
echo "active=$IS_ACTIVE"
echo "group_id=$GROUP_ID_OUT"
echo "group=$GROUP_NAME"
echo "server=$SERVER"
echo "port=$PORT"
echo "sni=$SNI"
echo "flow=$FLOW"
echo

echo "PING"
echo "icmp_ms=$PING_MS"
echo

echo "APP STATE"
echo "proxy_enabled=$PROXY_ENABLED"
echo "transproxy_enabled=$TRANSPROXY_ENABLED"
echo "dns_redirect_enabled=$DNS_REDIRECT_ENABLED"
echo "ipv6_block_enabled=$IPV6_BLOCK_ENABLED"
echo

echo "PROXY CONFIG"
echo "config_server=$CONFIG_SERVER_OUT"
echo "config_port=$CONFIG_PORT_OUT"
echo "active_config_match=$CONFIG_MATCH"
echo

echo "RUNTIME"
echo "proxy_process=$proxy_process"
echo "listener_12345=$proxy_12345"
echo "dns_listener_udp_1053=$dns_1053_udp"
echo "dns_listener_tcp_1053=$dns_1053_tcp"
echo "dns_redirect_state=$dns_state"
echo "transproxy_state=$transproxy_state"
echo

echo "TRANSPROXY SERVER EXCLUSION"
echo "nat_return=$server_exclusion_nat"
echo "udp_return=$server_exclusion_udp"
