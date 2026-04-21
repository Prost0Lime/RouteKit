#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/proxy-manager.log"
PIDFILE="$PID_DIR/proxy.pid"

log_msg "$LOGFILE" "stop_proxy begin"
stop_by_pidfile "proxy" "$PIDFILE" "$LOGFILE"