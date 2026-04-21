#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }
FILE="$(service_unresolved_file_for "$SERVICE_ID")"
[ -f "$FILE" ] && cat "$FILE"
