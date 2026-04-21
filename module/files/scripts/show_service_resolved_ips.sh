#!/system/bin/sh
. "$(dirname "$0")/common.sh"

SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || exit 1

MODE_FILE="$(service_mode_file_for "$SERVICE_ID" 2>/dev/null)" || exit 0
SERVICE_ID=""
TCP_IPSET=""
UDP_IPSET=""
STUN_IPSET=""
. "$MODE_FILE"

print_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -v '^[[:space:]]*$' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | sed 's#/32$##; s#/128$##'
}

TMP="$RUNTIME_DIR/tmp/${SERVICE_ID}.resolved_ips.txt"
mkdir -p "$RUNTIME_DIR/tmp"
: > "$TMP"

AUTO_V4="$(service_auto_ipset_v4_file_for "$SERVICE_ID")"
AUTO_V6="$(service_auto_ipset_v6_file_for "$SERVICE_ID")"

[ -n "$TCP_IPSET" ] && print_file "$(expand_cfg_path "$TCP_IPSET")" >> "$TMP"
[ -n "$UDP_IPSET" ] && print_file "$(expand_cfg_path "$UDP_IPSET")" >> "$TMP"
[ -n "$STUN_IPSET" ] && print_file "$(expand_cfg_path "$STUN_IPSET")" >> "$TMP"
print_file "$AUTO_V4" >> "$TMP"
print_file "$AUTO_V6" >> "$TMP"

if [ -s "$TMP" ]; then
  sort -u "$TMP"
fi
