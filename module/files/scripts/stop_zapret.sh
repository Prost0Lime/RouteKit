#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/zapret-manager.log"
PIDFILE="$PID_DIR/zapret.pid"

log_msg "$LOGFILE" "stop_zapret begin"

sh "$(dirname "$0")/clear_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1

if [ -f "$PIDFILE" ]; then
  PID="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null
    sleep 1
    kill -9 "$PID" 2>/dev/null
  fi
  rm -f "$PIDFILE"
fi

pkill -f /data/adb/modules/zapret2_manager/files/bin/zapret/nfqws2 2>/dev/null
pkill -f nfqws2 2>/dev/null

sleep 1

for PID in $(ps -A | grep nfqws2 | awk '{print $2}'); do
  kill -9 "$PID" 2>/dev/null
done

log_msg "$LOGFILE" "stop_zapret done"