#!/system/bin/sh

MODDIR=${0%/*}
LOGDIR="$MODDIR/files/runtime/logs"
SCRIPT="$MODDIR/files/scripts/start_all.sh"
WATCHER="$MODDIR/files/scripts/network_watch.sh"
WATCH_PIDFILE="$MODDIR/files/runtime/pids/network_watch.pid"

mkdir -p "$LOGDIR" "$MODDIR/files/runtime/pids"

echo "[service] start $(date)" >> "$LOGDIR/service.log"

sh "$SCRIPT" >> "$LOGDIR/service.log" 2>&1

if [ -f "$WATCH_PIDFILE" ]; then
  OLD_PID="$(cat "$WATCH_PIDFILE" 2>/dev/null)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[service] watcher already running pid=$OLD_PID" >> "$LOGDIR/service.log"
    exit 0
  fi
fi

nohup sh "$WATCHER" >> "$LOGDIR/service.log" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$WATCH_PIDFILE"
echo "[service] watcher started pid=$NEW_PID" >> "$LOGDIR/service.log"
