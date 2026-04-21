#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/transproxy.log"
CHAIN="ZAPRET2_TRANS"
UDP_CHAIN="ZAPRET2_UDP_REJECT"

safe_iptables() { iptables "$@" 2>/dev/null; }

log() {
  log_msg "$LOGFILE" "$*"
}

SERVER_IP=""
if [ -f "$CFG_DIR/proxy.json" ]; then
  SERVER_IP="$(awk -F'"' '/"server"[[:space:]]*:/ {print $4; exit}' "$CFG_DIR/proxy.json" 2>/dev/null)"
fi

case "$SERVER_IP" in
  *.*.*.*) ;;
  *)
    log "refresh server exclusion skipped: non-ip server=$SERVER_IP"
    exit 1
    ;;
esac

safe_iptables -t nat -S "$CHAIN" >/dev/null || {
  log "refresh server exclusion skipped: nat chain missing"
  exit 1
}

safe_iptables -S "$UDP_CHAIN" >/dev/null || {
  log "refresh server exclusion skipped: udp chain missing"
  exit 1
}

safe_iptables -t nat -C OUTPUT -p tcp -j "$CHAIN" || {
  log "refresh server exclusion skipped: nat output jump missing"
  exit 1
}

safe_iptables -C OUTPUT -p udp -j "$UDP_CHAIN" || {
  log "refresh server exclusion skipped: udp output jump missing"
  exit 1
}

if safe_iptables -t nat -C "$CHAIN" -d "$SERVER_IP/32" -j RETURN; then
  nat_added=false
else
  safe_iptables -t nat -I "$CHAIN" 3 -d "$SERVER_IP/32" -j RETURN || {
    log "refresh server exclusion failed: add nat return server_ip=$SERVER_IP"
    exit 1
  }
  nat_added=true
fi

if safe_iptables -C "$UDP_CHAIN" -d "$SERVER_IP/32" -j RETURN; then
  udp_added=false
else
  safe_iptables -I "$UDP_CHAIN" 3 -d "$SERVER_IP/32" -j RETURN || {
    log "refresh server exclusion failed: add udp return server_ip=$SERVER_IP"
    exit 1
  }
  udp_added=true
fi

log "refresh server exclusion done server_ip=$SERVER_IP nat_added=$nat_added udp_added=$udp_added"
echo ok
