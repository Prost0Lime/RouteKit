#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/toggle_routing.log"
STATE_FILE="$CFG_DIR/app_state.json"
ACTION="$1"

case "$ACTION" in
  on|off)
    ;;
  *)
    echo "usage: toggle_routing.sh on|off"
    exit 1
    ;;
esac

if [ ! -f "$STATE_FILE" ]; then
  echo "state file missing"
  exit 1
fi

TMP_FILE="${STATE_FILE}.tmp"

if [ "$ACTION" = "on" ]; then
  sed -e 's/"routing_enabled"[[:space:]]*:[[:space:]]*false/"routing_enabled": true/' \
    "$STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"
else
  sed -e 's/"routing_enabled"[[:space:]]*:[[:space:]]*true/"routing_enabled": false/' \
    "$STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"
fi

log_msg "$LOGFILE" "routing toggled $ACTION"

sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1

echo "ok"