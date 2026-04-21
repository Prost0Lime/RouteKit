#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE="$1"
LAYER="$2"
STRAT="$3"
[ -n "$SERVICE" ] && [ -n "$LAYER" ] || { echo "usage: $0 <service_id> <tcp|udp|stun> <strategy|empty>"; exit 1; }
case "$LAYER" in tcp) KEY="TCP_STRATEGY" ;; udp) KEY="UDP_STRATEGY" ;; stun) KEY="STUN_STRATEGY" ;; *) echo "invalid layer"; exit 1 ;; esac
FILE="$(service_mode_file_for "$SERVICE")" || { echo "service not found: $SERVICE"; exit 1; }
TMP="$FILE.tmp"
awk -v key="$KEY" -v val="$STRAT" '
$0 ~ "^" key "=" { print key "=\"" val "\""; done=1; next }
{ print }
END { if (!done) print key "=\"" val "\"" }
' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
echo ok
