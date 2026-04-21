#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }
MODE_FILE="$(service_mode_file_for "$SERVICE_ID")" || { echo "service not found: $SERVICE_ID"; exit 1; }
SERVICE_ID=""; ENABLED="true"; MODE="direct"; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; TCP_IPSET=""; UDP_IPSET=""; STUN_IPSET=""; . "$MODE_FILE"
count_path() {
  local path="$1"
  [ -n "$path" ] || { echo 0; return; }
  count_non_comment_lines "$(expand_cfg_path "$path")"
}
AUTO_V4_FILE="$(service_auto_ipset_v4_file_for "$SERVICE_ID")"
AUTO_V6_FILE="$(service_auto_ipset_v6_file_for "$SERVICE_ID")"
UNRESOLVED_FILE="$(service_unresolved_file_for "$SERVICE_ID")"
CONFLICTS_FILE="$RUNTIME_DIR/conflicts/.coverage_${SERVICE_ID}_$$.txt"
mkdir -p "$RUNTIME_DIR/conflicts"
trap 'rm -f "$CONFLICTS_FILE"' EXIT
sh "$(dirname "$0")/show_service_conflicts.sh" "$SERVICE_ID" > "$CONFLICTS_FILE" 2>/dev/null || true
DOMAIN_COUNT=0
for p in "$TCP_HOSTLIST" "$UDP_HOSTLIST" "$STUN_HOSTLIST"; do
  [ -n "$p" ] || continue
  DOMAIN_COUNT=$((DOMAIN_COUNT + $(count_non_comment_lines "$(expand_cfg_path "$p")")))
done
AUTO_IP_COUNT="$(count_non_comment_lines "$AUTO_V4_FILE")"
AUTO_IPV6_COUNT="$(count_non_comment_lines "$AUTO_V6_FILE")"
UNRESOLVED_COUNT="$(count_non_comment_lines "$UNRESOLVED_FILE")"
CONFLICT_COUNT="$(count_non_comment_lines "$CONFLICTS_FILE")"
MODE_CONFLICT_COUNT="$(grep -c 'mode_conflict$' "$CONFLICTS_FILE" 2>/dev/null || true)"
TCP_STATIC_COUNT="$(count_path "$TCP_IPSET")"
UDP_STATIC_COUNT="$(count_path "$UDP_IPSET")"
STUN_STATIC_COUNT="$(count_path "$STUN_IPSET")"
TOTAL_STATIC=$((TCP_STATIC_COUNT + UDP_STATIC_COUNT + STUN_STATIC_COUNT))
TOTAL_IP=$((AUTO_IP_COUNT + TOTAL_STATIC))
IPV6_STATUS="n/a"
if [ "$MODE" = "vpn" ]; then
  if [ "$AUTO_IPV6_COUNT" -eq 0 ]; then IPV6_STATUS="empty"; else IPV6_STATUS="present"; fi
fi
COVERAGE_STATUS="n/a"
if [ "$MODE" = "vpn" ]; then
  if [ "$TOTAL_IP" -eq 0 ]; then
    COVERAGE_STATUS="empty"
  elif [ "$AUTO_IP_COUNT" -eq 0 ] && [ "$TOTAL_STATIC" -gt 0 ]; then
    COVERAGE_STATUS="static_only"
  elif [ "$AUTO_IP_COUNT" -gt 0 ] && [ "$TOTAL_STATIC" -eq 0 ]; then
    COVERAGE_STATUS="auto_only"
  else
    COVERAGE_STATUS="mixed"
  fi
fi
cat <<EOF
SERVICE_ID="$SERVICE_ID"
ENABLED="$ENABLED"
MODE="$MODE"
DOMAIN_COUNT="$DOMAIN_COUNT"
AUTO_IPSET_FILE="$AUTO_V4_FILE"
AUTO_IP_COUNT="$AUTO_IP_COUNT"
AUTO_IPV6_IPSET_FILE="$AUTO_V6_FILE"
AUTO_IPV6_COUNT="$AUTO_IPV6_COUNT"
IPV6_STATUS="$IPV6_STATUS"
UNRESOLVED_COUNT="$UNRESOLVED_COUNT"
CONFLICT_COUNT="$CONFLICT_COUNT"
MODE_CONFLICT_COUNT="$MODE_CONFLICT_COUNT"
TCP_STATIC_COUNT="$TCP_STATIC_COUNT"
UDP_STATIC_COUNT="$UDP_STATIC_COUNT"
STUN_STATIC_COUNT="$STUN_STATIC_COUNT"
TOTAL_IP_COUNT="$TOTAL_IP"
COVERAGE_STATUS="$COVERAGE_STATUS"
EOF
