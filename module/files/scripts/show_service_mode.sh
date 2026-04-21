#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE="$1"
[ -n "$SERVICE" ] || { echo "usage: $0 <service_id>"; exit 1; }
FILE="$(service_mode_file_for "$SERVICE")" || { echo "service not found: $SERVICE"; exit 1; }
cat "$FILE"
