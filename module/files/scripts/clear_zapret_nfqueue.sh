#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/zapret-nfqueue.log"
CHAIN="ZAPRET2_NFQ"

log_msg "$LOGFILE" "clear_zapret_nfqueue begin"

iptables -t mangle -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null

iptables -t mangle -F "$CHAIN" 2>/dev/null
iptables -t mangle -X "$CHAIN" 2>/dev/null

log_msg "$LOGFILE" "clear_zapret_nfqueue done"