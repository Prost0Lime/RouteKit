#!/system/bin/sh
. "$(dirname "$0")/common.sh"

APP_STATE="$CFG_DIR/app_state.json"
ACTIVE_PROFILE_FILE="$CFG_DIR/active_profile.txt"
ZAPRET_PIDFILE="$RUNTIME_DIR/zapret.pid"
PROXY_PIDFILE="$RUNTIME_DIR/pids/proxy.pid"
TRANSPROXY_FLAG="$RUNTIME_DIR/transproxy.enabled"
DNS_REDIRECT_FLAG="$RUNTIME_DIR/dns_redirect.enabled"
IPV6_BLOCK_FLAG="$RUNTIME_DIR/ipv6_block.enabled"

json_get() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0
    tr -d '\n' < "$file" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

json_get_raw() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0
    tr -d '\n' < "$file" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" | sed 's/[[:space:]]*$//' | tr -d ','
}

count_lines() {
    local file="$1"
    [ -f "$file" ] || { echo 0; return; }
    grep -v '^[[:space:]]*$' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | wc -l | tr -d ' '
}

pid_running() {
    local pidfile="$1"
    [ -f "$pidfile" ] || return 1
    local pid
    pid="$(cat "$pidfile" 2>/dev/null)"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

read_kv_from_profile() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0
    awk -F= -v k="$key" '
        $1 == k {
            v=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            sub(/^"/, "", v); sub(/"$/, "", v)
            sub(/^'\''/, "", v); sub(/'\''$/, "", v)
            print v
            exit
        }
    ' "$file"
}

get_selected_profile_file() {
    local profile_id
    profile_id="$(read_kv_from_profile "$ACTIVE_PROFILE_FILE" "PROFILE_ID")"
    [ -n "$profile_id" ] || profile_id="$(cat "$ACTIVE_PROFILE_FILE" 2>/dev/null | tr -d '\r\n')"
    [ -n "$profile_id" ] || profile_id="$(json_get "$APP_STATE" "selected_zapret_profile")"
    [ -n "$profile_id" ] || profile_id="default"
    echo "$CFG_DIR/zapret_profiles/$profile_id.conf"
}

internet_status() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "ok" || echo "fail"
}

SERVICE_ZAPRET_COUNT="$(service_mode_count zapret)"
SERVICE_VPN_COUNT="$(service_mode_count vpn)"
SERVICE_DIRECT_COUNT="$(service_mode_count direct)"
CUSTOM_SERVICE_COUNT=0
for f in $(service_mode_files); do
    [ -f "$f" ] || continue
    sid="$(basename "$f" .conf)"
    service_is_custom "$sid" && CUSTOM_SERVICE_COUNT=$((CUSTOM_SERVICE_COUNT + 1))
done

AUTO_IPSET_TOTAL=0
for f in "$RUNTIME_DIR"/ipsets_auto/*.txt; do
    [ -f "$f" ] || continue
    c="$(count_lines "$f")"
    AUTO_IPSET_TOTAL=$((AUTO_IPSET_TOTAL + c))
done

AUTO_IPV6_IPSET_TOTAL=0
for f in "$RUNTIME_DIR"/ipsets_auto_v6/*.txt; do
    [ -f "$f" ] || continue
    c="$(count_lines "$f")"
    AUTO_IPV6_IPSET_TOTAL=$((AUTO_IPV6_IPSET_TOTAL + c))
done

PROFILE_FILE="$(get_selected_profile_file)"
PROFILE_ID="$(read_kv_from_profile "$PROFILE_FILE" "PROFILE_ID")"
PROFILE_NAME="$(read_kv_from_profile "$PROFILE_FILE" "PROFILE_NAME")"
ENGINE="$(read_kv_from_profile "$PROFILE_FILE" "ENGINE")"
TCP_STRATEGY="$(read_kv_from_profile "$PROFILE_FILE" "TCP_STRATEGY")"
UDP_STRATEGY="$(read_kv_from_profile "$PROFILE_FILE" "UDP_STRATEGY")"
STUN_STRATEGY="$(read_kv_from_profile "$PROFILE_FILE" "STUN_STRATEGY")"
TCP_HOSTLIST="$(read_kv_from_profile "$PROFILE_FILE" "TCP_HOSTLIST")"
TCP_IPSET="$(read_kv_from_profile "$PROFILE_FILE" "TCP_IPSET")"
UDP_HOSTLIST="$(read_kv_from_profile "$PROFILE_FILE" "UDP_HOSTLIST")"
UDP_IPSET="$(read_kv_from_profile "$PROFILE_FILE" "UDP_IPSET")"

[ -n "$PROFILE_ID" ] || PROFILE_ID="default"
[ -n "$PROFILE_NAME" ] || PROFILE_NAME="Default zapret profile"
[ -n "$ENGINE" ] || ENGINE="nfqws2"

if pid_running "$ZAPRET_PIDFILE" || ps -A 2>/dev/null | grep -q "[n]fqws2"; then
    ZAPRET_STATUS="running"
else
    ZAPRET_STATUS="stopped"
fi

if pid_running "$PROXY_PIDFILE" || ps -A 2>/dev/null | grep -q "[s]ing-box"; then
    PROXY_STATUS="running"
else
    PROXY_STATUS="stopped"
fi

if [ -f "$TRANSPROXY_FLAG" ] || iptables -t nat -C OUTPUT -p tcp -j ZAPRET2_TRANS >/dev/null 2>&1; then
    TRANSPROXY_STATUS="enabled"
else
    TRANSPROXY_STATUS="disabled"
fi

if [ -f "$DNS_REDIRECT_FLAG" ] \
  || iptables -t nat -C OUTPUT -p udp --dport 53 -j ZAPRET2_DNS_UDP >/dev/null 2>&1 \
  || iptables -t nat -C OUTPUT -p tcp --dport 53 -j ZAPRET2_DNS_TCP >/dev/null 2>&1 \
  || iptables -t nat -C OUTPUT -p udp --dport 53 -j ZAPRET2_DNS >/dev/null 2>&1; then
    DNS_REDIRECT_STATUS="enabled"
else
    DNS_REDIRECT_STATUS="disabled"
fi
if [ -f "$IPV6_BLOCK_FLAG" ] || ip6tables -C OUTPUT -j ZAPRET2_V6_BLOCK >/dev/null 2>&1; then
    IPV6_BLOCK_STATUS="enabled"
else
    IPV6_BLOCK_STATUS="disabled"
fi

ROUTING_ENABLED="$(json_get_raw "$APP_STATE" "routing_enabled")"
ROUTING_MODE="$(json_get "$APP_STATE" "routing_mode")"
PROXY_DOMAINS_COUNT="$(count_lines "$CFG_DIR/proxy_domains.txt")"
DIRECT_DOMAINS_COUNT="$(count_lines "$CFG_DIR/direct_domains.txt")"

ACTIVE_PROFILE_ID="$(cat "$ACTIVE_PROFILE_FILE" 2>/dev/null | tr -d '\r\n')"
ACTIVE_PROFILE_NAME=""
ACTIVE_PROFILE_SERVER=""
ACTIVE_PROFILE_GROUP=""
if [ -n "$ACTIVE_PROFILE_ID" ] && [ -f "$CFG_DIR/profiles/$ACTIVE_PROFILE_ID/meta.conf" ]; then
    META_FILE="$CFG_DIR/profiles/$ACTIVE_PROFILE_ID/meta.conf"
    ACTIVE_PROFILE_NAME="$(read_kv_from_profile "$META_FILE" "PROFILE_NAME")"
    ACTIVE_PROFILE_SERVER="$(read_kv_from_profile "$META_FILE" "SERVER")"
    ACTIVE_PROFILE_GROUP="$(read_kv_from_profile "$META_FILE" "GROUP_ID")"
    if [ -n "$ACTIVE_PROFILE_GROUP" ] && [ -f "$CFG_DIR/groups/$ACTIVE_PROFILE_GROUP/name.txt" ]; then
        ACTIVE_PROFILE_GROUP="$(cat "$CFG_DIR/groups/$ACTIVE_PROFILE_GROUP/name.txt" 2>/dev/null | tr -d '')"
    fi
fi

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
INTERNET_STATUS="$(internet_status)"

cat <<EOF2
{
  "zapret": "$ZAPRET_STATUS",
  "zapret_profile": "$PROFILE_ID",
  "zapret_profile_name": "$PROFILE_NAME",
  "zapret_engine": "$ENGINE",
  "zapret_nfqueue": "enabled",
  "tcp_strategy": "$TCP_STRATEGY",
  "udp_strategy": "$UDP_STRATEGY",
  "stun_strategy": "$STUN_STRATEGY",
  "tcp_hostlist": "$TCP_HOSTLIST",
  "tcp_ipset": "$TCP_IPSET",
  "udp_hostlist": "$UDP_HOSTLIST",
  "udp_ipset": "$UDP_IPSET",
  "proxy": "$PROXY_STATUS",
  "transproxy": "$TRANSPROXY_STATUS",
  "dns_redirect": "$DNS_REDIRECT_STATUS",
  "ipv6_block": "$IPV6_BLOCK_STATUS",
  "routing_enabled": "${ROUTING_ENABLED:-false}",
  "routing_mode": "${ROUTING_MODE:-proxy_list}",
  "proxy_domains_count": "$PROXY_DOMAINS_COUNT",
  "direct_domains_count": "$DIRECT_DOMAINS_COUNT",
  "active_profile_id": "$ACTIVE_PROFILE_ID",
  "active_profile_name": "$ACTIVE_PROFILE_NAME",
  "active_profile_server": "$ACTIVE_PROFILE_SERVER",
  "active_profile_group": "$ACTIVE_PROFILE_GROUP",
  "service_zapret_count": "$SERVICE_ZAPRET_COUNT",
  "service_vpn_count": "$SERVICE_VPN_COUNT",
  "service_direct_count": "$SERVICE_DIRECT_COUNT",
  "custom_service_count": "$CUSTOM_SERVICE_COUNT",
  "auto_ipset_total": "$AUTO_IPSET_TOTAL",
  "auto_ipv6_ipset_total": "$AUTO_IPV6_IPSET_TOTAL",
  "internet": "$INTERNET_STATUS",
  "timestamp": "$TIMESTAMP"
}
EOF2
