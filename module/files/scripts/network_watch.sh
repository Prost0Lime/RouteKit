#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/network-watch.log"
PIDFILE="$PID_DIR/network_watch.pid"
STATEFILE="$RUNTIME_DIR/network/observed_key.txt"
REFRESH_SCRIPT="$(dirname "$0")/refresh_on_network_change.sh"
LAST_REFRESH_FILE="$RUNTIME_DIR/network/last_refresh_at.txt"
REFRESH_COOLDOWN_SEC="${REFRESH_COOLDOWN_SEC:-20}"

mkdir -p "$RUNTIME_DIR/network"

clear_stale_lock "$PIDFILE"
if pid_is_running "$PIDFILE"; then
  log_msg "$LOGFILE" "watcher already running pid=$(cat "$PIDFILE" 2>/dev/null)"
  exit 0
fi

echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

last_key="$(current_network_cache_key)"
printf '%s\n' "$last_key" > "$STATEFILE"
log_msg "$LOGFILE" "watcher start key=$last_key fp=$(network_fingerprint)"

while true; do
  sleep 8
  current_key="$(current_network_cache_key)"
  [ -n "$current_key" ] || continue
  previous_key="$(cat "$STATEFILE" 2>/dev/null)"
  [ -n "$previous_key" ] || previous_key="$last_key"

  if [ "$current_key" != "$previous_key" ]; then
    log_msg "$LOGFILE" "network change detected old=$previous_key new=$current_key fp=$(network_fingerprint)"
    sleep 3
    if ! wait_for_network_ready 5; then
      log_msg "$LOGFILE" "network change wait timeout current_key=$current_key fp=$(network_fingerprint)"
    fi
    stable_key="$(current_network_cache_key)"
    [ -n "$stable_key" ] || continue
    if [ "$stable_key" != "$current_key" ]; then
      log_msg "$LOGFILE" "network change not stable pending=$current_key actual=$stable_key fp=$(network_fingerprint)"
      printf '%s\n' "$stable_key" > "$STATEFILE"
      last_key="$stable_key"
      continue
    fi
    printf '%s\n' "$stable_key" > "$STATEFILE"
    last_key="$stable_key"
    log_msg "$LOGFILE" "network change stable key=$stable_key fp=$(network_fingerprint)"
    now_ts="$(date +%s 2>/dev/null)"
    last_refresh_ts=""
    [ -f "$LAST_REFRESH_FILE" ] && last_refresh_ts="$(cat "$LAST_REFRESH_FILE" 2>/dev/null | tr -d '\r\n')"
    case "$last_refresh_ts" in
      ''|*[!0-9]*) last_refresh_ts=0 ;;
    esac
    case "$now_ts" in
      ''|*[!0-9]*) now_ts=0 ;;
    esac
    if [ "$now_ts" -gt 0 ] && [ "$last_refresh_ts" -gt 0 ] && [ $((now_ts - last_refresh_ts)) -lt "$REFRESH_COOLDOWN_SEC" ]; then
      log_msg "$LOGFILE" "network change cooldown skip key=$stable_key seconds_since_last=$((now_ts - last_refresh_ts)) cooldown=$REFRESH_COOLDOWN_SEC"
      continue
    fi
    sh "$REFRESH_SCRIPT"
  fi

done
