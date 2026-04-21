#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }
MODE_FILE="$(service_mode_file_for "$SERVICE_ID")" || { echo "service not found: $SERVICE_ID"; exit 1; }
SERVICE_ID=""; TCP_HOSTLIST=""; . "$MODE_FILE"
TARGET="$(expand_cfg_path "$TCP_HOSTLIST")"
[ -n "$TARGET" ] || TARGET="$CFG_DIR/hostlists/$SERVICE_ID.txt"
[ -f "$TARGET" ] && cat "$TARGET"
