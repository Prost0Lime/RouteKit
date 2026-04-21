#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/proxy-manager.log"
PIDFILE="$PID_DIR/proxy.pid"
LOCKFILE="$RUNTIME_DIR/start_proxy.lock"
BIN="$BASE_DIR/bin/proxy/sing-box"
CONF="$CFG_DIR/proxy.json"

if [ -f "$LOCKFILE" ]; then
  log_msg "$LOGFILE" "start_proxy skipped: lock exists pid=$(cat "$LOCKFILE" 2>/dev/null)"
  exit 0
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

log_msg "$LOGFILE" "start_proxy begin"

if pid_is_running "$PIDFILE"; then
  log_msg "$LOGFILE" "proxy already running"
  exit 0
fi

if [ ! -x "$BIN" ]; then
  log_msg "$LOGFILE" "binary missing or not executable: $BIN"
  exit 1
fi

if [ ! -f "$CONF" ]; then
  log_msg "$LOGFILE" "config missing: $CONF"
  exit 1
fi

nohup "$BIN" run -c "$CONF" >> "$LOG_DIR/proxy.log" 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"

sleep 1
if kill -0 "$PID" 2>/dev/null && wait_for_proxy_runtime_ready 10; then
  log_msg "$LOGFILE" "proxy started pid=$PID listeners=127.0.0.1:12345,127.0.0.1:1053"
  exit 0
fi

log_msg "$LOGFILE" "proxy failed to start or listeners not ready"
kill "$PID" 2>/dev/null
sleep 1
kill -9 "$PID" 2>/dev/null
rm -f "$PIDFILE"
exit 1
