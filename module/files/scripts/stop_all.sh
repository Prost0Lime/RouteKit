#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/stop_all.log"

log_msg "$LOGFILE" "stop_all begin"

sh "$(dirname "$0")/clear_transproxy.sh"
sh "$(dirname "$0")/clear_dns_redirect.sh"
sh "$(dirname "$0")/clear_ipv6_block.sh"
sh "$(dirname "$0")/stop_proxy.sh"
sh "$(dirname "$0")/stop_zapret.sh"

WATCH_PIDFILE="$PID_DIR/network_watch.pid"

if [ -f "$WATCH_PIDFILE" ]; then
  WATCH_PID="$(cat "$WATCH_PIDFILE" 2>/dev/null)"
  if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
    kill "$WATCH_PID" 2>/dev/null
    sleep 1
    kill -9 "$WATCH_PID" 2>/dev/null
    log_msg "$LOGFILE" "network watcher stopped pid=$WATCH_PID"
  fi
  rm -f "$WATCH_PIDFILE"
fi

log_msg "$LOGFILE" "stop_all done"