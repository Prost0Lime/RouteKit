#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/transproxy.log"
CHAIN="ZAPRET2_TRANS"
UDP_CHAIN="ZAPRET2_UDP_REJECT"

log_msg "$LOGFILE" "clear_transproxy begin"

iptables -D OUTPUT -p udp -j "$UDP_CHAIN" 2>/dev/null
iptables -F "$UDP_CHAIN" 2>/dev/null
iptables -X "$UDP_CHAIN" 2>/dev/null

iptables -t nat -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null
iptables -t nat -F "$CHAIN" 2>/dev/null
iptables -t nat -X "$CHAIN" 2>/dev/null

rm -f /data/adb/modules/zapret2_manager/files/runtime/transproxy.enabled

log_msg "$LOGFILE" "clear_transproxy done"