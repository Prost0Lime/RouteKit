#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/set_routing_mode.log"
STATE_FILE="$CFG_DIR/app_state.json"
MODE="$1"

case "$MODE" in
  proxy_list|direct_list)
    ;;
  *)
    echo "usage: set_routing_mode.sh proxy_list|direct_list"
    exit 1
    ;;
esac

if [ ! -f "$STATE_FILE" ]; then
  echo "state file missing"
  exit 1
fi

TMP_FILE="${STATE_FILE}.tmp"

sed \
  -e 's/"routing_enabled"[[:space:]]*:[[:space:]]*false/"routing_enabled": true/' \
  -e "s/\"routing_mode\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"routing_mode\": \"$MODE\"/" \
  "$STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"

log_msg "$LOGFILE" "routing mode set to $MODE"

sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1

echo "ok"