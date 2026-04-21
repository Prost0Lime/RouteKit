#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOG="$LOG_DIR/transproxy.log"
PROXY_PORT="12345"
CHAIN="ZAPRET2_TRANS"
UDP_CHAIN="ZAPRET2_UDP_REJECT"

SERVER_IP=""
if [ -f "$CFG_DIR/proxy.json" ]; then
    SERVER_IP="$(awk -F'"' '/"server"[[:space:]]*:/ {print $4; exit}' "$CFG_DIR/proxy.json" 2>/dev/null)"
fi

log() {
    mkdir -p "$(dirname "$LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

safe_iptables() { iptables "$@" 2>/dev/null; }

count_ipset_entries() {
    local file="$1"
    local family="${2:-any}"
    [ -f "$file" ] || { echo 0; return; }
    case "$family" in
        v4)
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$' "$file" 2>/dev/null | wc -l | tr -d ' '
            ;;
        v6)
            grep ':' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | grep -v '^[[:space:]]*$' 2>/dev/null | wc -l | tr -d ' '
            ;;
        *)
            grep -v '^[[:space:]]*$' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | wc -l | tr -d ' '
            ;;
    esac
}

merge_ipset_files() {
    local out="$1"
    shift
    mkdir -p "$(dirname "$out")"
    : > "$out"

    local f=""
    for f in "$@"; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        grep -v '^[[:space:]]*$' "$f" 2>/dev/null |
            grep -v '^[[:space:]]*#' 2>/dev/null |
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$' 2>/dev/null >> "$out"
    done

    if [ -s "$out" ]; then
        sort -u "$out" -o "$out" 2>/dev/null
    fi
}

add_redirect_cidr() {
    local net="$1"
    local service="$2"
    [ -n "$net" ] || return 0

    safe_iptables -t nat -C "$CHAIN" -d "$net" -p tcp --dport 80 -j REDIRECT --to-ports "$PROXY_PORT" ||
        safe_iptables -t nat -A "$CHAIN" -d "$net" -p tcp --dport 80 -j REDIRECT --to-ports "$PROXY_PORT"

    safe_iptables -t nat -C "$CHAIN" -d "$net" -p tcp --dport 443 -j REDIRECT --to-ports "$PROXY_PORT" ||
        safe_iptables -t nat -A "$CHAIN" -d "$net" -p tcp --dport 443 -j REDIRECT --to-ports "$PROXY_PORT"

    safe_iptables -C "$UDP_CHAIN" -d "$net" -p udp --dport 443 -j REJECT ||
        safe_iptables -A "$UDP_CHAIN" -d "$net" -p udp --dport 443 -j REJECT

    log "redirect tcp + reject udp service=$service cidr=$net"
}

add_redirect_ipset_file() {
    local file="$1"
    local service="$2"
    [ -f "$file" ] || return 0

    while IFS= read -r net || [ -n "$net" ]; do
        net="$(echo "$net" | tr -d '\r')"
        [ -n "$net" ] || continue
        case "$net" in
            \#*) continue ;;
        esac
        add_redirect_cidr "$net" "$service"
    done < "$file"

    log "processed ipset service=$service file=$file count=$(count_ipset_entries "$file")"
}

clear_transproxy() {
    log "clear_transproxy begin"
    safe_iptables -D OUTPUT -p udp -j "$UDP_CHAIN"
    safe_iptables -F "$UDP_CHAIN"
    safe_iptables -X "$UDP_CHAIN"
    safe_iptables -t nat -D OUTPUT -p tcp -j "$CHAIN"
    safe_iptables -t nat -F "$CHAIN"
    safe_iptables -t nat -X "$CHAIN"
    rm -f "$RUNTIME_DIR/transproxy.enabled"
    log "clear_transproxy done"
}

apply_transproxy() {
    log "apply_transproxy begin server_ip=$SERVER_IP"

    clear_transproxy

    safe_iptables -t nat -N "$CHAIN" || return 1
    safe_iptables -N "$UDP_CHAIN" || return 1
    safe_iptables -t nat -A OUTPUT -p tcp -j "$CHAIN" || return 1
    safe_iptables -A OUTPUT -p udp -j "$UDP_CHAIN" || return 1

    safe_iptables -t nat -A "$CHAIN" -o lo -j RETURN
    safe_iptables -t nat -A "$CHAIN" -m owner --uid-owner 0 -j RETURN
    safe_iptables -A "$UDP_CHAIN" -o lo -j RETURN
    safe_iptables -A "$UDP_CHAIN" -m owner --uid-owner 0 -j RETURN

    [ -n "$SERVER_IP" ] && {
        safe_iptables -t nat -A "$CHAIN" -d "$SERVER_IP"/32 -j RETURN
        safe_iptables -A "$UDP_CHAIN" -d "$SERVER_IP"/32 -j RETURN
    }

    for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16; do
        safe_iptables -t nat -A "$CHAIN" -d "$net" -j RETURN
        safe_iptables -A "$UDP_CHAIN" -d "$net" -j RETURN
    done

    mkdir -p "$RUNTIME_DIR/tmp"

    total_services=0
    warned_empty=0

    for f in $(service_mode_files); do
        [ -f "$f" ] || continue

        SERVICE_ID=""
        ENABLED="true"
        MODE="direct"
        TCP_IPSET=""
        UDP_IPSET=""
        . "$f"
        [ "$ENABLED" = "true" ] || continue
        [ "$MODE" = "vpn" ] || continue

        total_services=$((total_services + 1))

        tcp_ipset="$(expand_cfg_path "$TCP_IPSET")"
        udp_ipset="$(expand_cfg_path "$UDP_IPSET")"
        auto_ipset_v4="$RUNTIME_DIR/ipsets_auto/${SERVICE_ID}.txt"

        merged_tcp="$RUNTIME_DIR/tmp/${SERVICE_ID}.tcp.merged.txt"
        merged_udp="$RUNTIME_DIR/tmp/${SERVICE_ID}.udp.merged.txt"

        merge_ipset_files "$merged_tcp" "$tcp_ipset" "$auto_ipset_v4"
        merge_ipset_files "$merged_udp" "$udp_ipset" "$auto_ipset_v4"

        tcp_count="$(count_ipset_entries "$merged_tcp" v4)"
        udp_count="$(count_ipset_entries "$merged_udp" v4)"
        auto_count="$(count_ipset_entries "$auto_ipset_v4" v4)"
        static_tcp_v6_count="$(count_ipset_entries "$tcp_ipset" v6)"
        static_udp_v6_count="$(count_ipset_entries "$udp_ipset" v6)"
        auto_v6_count="$(count_ipset_entries "$RUNTIME_DIR/ipsets_auto_v6/${SERVICE_ID}.txt" v6)"

        if [ "$tcp_count" -eq 0 ] && [ "$udp_count" -eq 0 ]; then
            warned_empty=$((warned_empty + 1))
            log "warning service=$SERVICE_ID mode=vpn has empty ipv4 ipset tcp=$tcp_ipset udp=$udp_ipset auto=$auto_ipset_v4"
            continue
        fi

        if [ "$tcp_count" -gt 0 ] && cmp -s "$merged_tcp" "$merged_udp" 2>/dev/null; then
            add_redirect_ipset_file "$merged_tcp" "$SERVICE_ID"
        else
            [ "$tcp_count" -gt 0 ] && add_redirect_ipset_file "$merged_tcp" "$SERVICE_ID"
            [ "$udp_count" -gt 0 ] && add_redirect_ipset_file "$merged_udp" "$SERVICE_ID"
        fi

        if [ "$static_tcp_v6_count" -gt 0 ] || [ "$static_udp_v6_count" -gt 0 ] || [ "$auto_v6_count" -gt 0 ]; then
            log "warning service=$SERVICE_ID has ipv6 entries static_tcp_v6=$static_tcp_v6_count static_udp_v6=$static_udp_v6_count auto_v6=$auto_v6_count but current transproxy uses IPv4 iptables REDIRECT only"
        fi

        log "service=$SERVICE_ID mode=vpn static_tcp_v4=$(count_ipset_entries "$tcp_ipset" v4) static_udp_v4=$(count_ipset_entries "$udp_ipset" v4) auto_v4=$auto_count merged_tcp_v4=$tcp_count merged_udp_v4=$udp_count"
    done

    safe_iptables -t nat -A "$CHAIN" -j RETURN
    safe_iptables -A "$UDP_CHAIN" -j RETURN
    : > "$RUNTIME_DIR/transproxy.enabled"

    log "apply_transproxy done vpn_services=$total_services warned_empty=$warned_empty"
}

case "$1" in
    clear)
        clear_transproxy
        ;;
    *)
        apply_transproxy
        ;;
esac
