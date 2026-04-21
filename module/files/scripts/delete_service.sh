#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }
service_is_custom "$SERVICE_ID" || { echo "only custom services can be deleted"; exit 1; }
rm -f "$CFG_DIR/service_modes/$SERVICE_ID.conf" "$CFG_DIR/services/$SERVICE_ID.conf" "$CFG_DIR/hostlists/$SERVICE_ID.txt" "$CFG_DIR/ipsets/$SERVICE_ID.txt"
echo ok
