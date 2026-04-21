#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/zapret-nfqueue.log"
CHAIN="ZAPRET2_NFQ"
STATE_FILE="$CFG_DIR/app_state.json"

log_msg "$LOGFILE" "apply_zapret_nfqueue begin"

if [ ! -f "$STATE_FILE" ]; then
  log_msg "$LOGFILE" "state file missing"
  exit 1
fi

PROFILE_ID="$(grep -o '"selected_zapret_profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/')"
[ -n "$PROFILE_ID" ] || PROFILE_ID="default"

PROFILE_FILE="$CFG_DIR/zapret_profiles/$PROFILE_ID.conf"
if [ ! -f "$PROFILE_FILE" ]; then
  log_msg "$LOGFILE" "zapret profile missing: $PROFILE_ID"
  exit 1
fi

ENGINE=""
ENABLED=""
NFQWS2_QNUM=""
TCP_PORTS=""
UDP_PORTS=""

. "$PROFILE_FILE"

if [ "$ENABLED" != "true" ]; then
  log_msg "$LOGFILE" "profile disabled"
  exit 0
fi

if [ "$ENGINE" != "nfqws2" ]; then
  log_msg "$LOGFILE" "engine is not nfqws2: $ENGINE"
  exit 0
fi

[ -n "$NFQWS2_QNUM" ] || NFQWS2_QNUM="200"

sh "$(dirname "$0")/clear_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1

iptables -t mangle -N "$CHAIN" 2>/dev/null

iptables -t mangle -A "$CHAIN" -o lo -j RETURN
iptables -t mangle -A "$CHAIN" -m owner --uid-owner 0 -j RETURN

HAS_TCP=0
HAS_UDP=0

OLDIFS="$IFS"
IFS=','

for p in $TCP_PORTS; do
  p="$(echo "$p" | tr -d '[:space:]\r')"
  [ -n "$p" ] || continue
  HAS_TCP=1
  iptables -t mangle -A "$CHAIN" -p tcp --dport "$p" -j NFQUEUE --queue-num "$NFQWS2_QNUM"
done

for p in $UDP_PORTS; do
  p="$(echo "$p" | tr -d '[:space:]\r')"
  [ -n "$p" ] || continue
  HAS_UDP=1
  iptables -t mangle -A "$CHAIN" -p udp --dport "$p" -j NFQUEUE --queue-num "$NFQWS2_QNUM"
done

IFS="$OLDIFS"

if [ "$HAS_TCP" = "1" ]; then
  iptables -t mangle -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null || \
  iptables -t mangle -A OUTPUT -p tcp -j "$CHAIN"
fi

if [ "$HAS_UDP" = "1" ]; then
  iptables -t mangle -C OUTPUT -p udp -j "$CHAIN" 2>/dev/null || \
  iptables -t mangle -A OUTPUT -p udp -j "$CHAIN"
fi

log_msg "$LOGFILE" "apply_zapret_nfqueue done qnum=$NFQWS2_QNUM tcp_ports=$TCP_PORTS udp_ports=$UDP_PORTS has_tcp=$HAS_TCP has_udp=$HAS_UDP"