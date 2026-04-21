#!/system/bin/sh
. "$(dirname "$0")/common.sh"
for f in $(service_mode_files); do
  SERVICE_ID=""; ENABLED="true"; MODE="direct"; VPN_PROFILE="active"; TCP_STRATEGY=""; UDP_STRATEGY=""; STUN_STRATEGY=""; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; TCP_IPSET=""; UDP_IPSET=""; STUN_IPSET=""; . "$f"
  NAME="$SERVICE_ID"
  CUSTOM="false"
  DEF="$CFG_DIR/services/$SERVICE_ID.conf"
  if [ -f "$DEF" ]; then
    SERVICE_NAME=""; CUSTOM_SERVICE="false"; . "$DEF"
    [ -n "$SERVICE_NAME" ] && NAME="$SERVICE_NAME"
    [ "$CUSTOM_SERVICE" = "true" ] && CUSTOM="true"
  fi
  DOMAIN_COUNT=0
  for path in "$TCP_HOSTLIST" "$UDP_HOSTLIST" "$STUN_HOSTLIST"; do
    [ -n "$path" ] || continue
    DOMAIN_COUNT=$((DOMAIN_COUNT + $(count_non_comment_lines "$(expand_cfg_path "$path")")))
  done
  AUTO_IP_COUNT="$(count_non_comment_lines "$(service_auto_ipset_v4_file_for "$SERVICE_ID")")"
  AUTO_IPV6_COUNT="$(count_non_comment_lines "$(service_auto_ipset_v6_file_for "$SERVICE_ID")")"
  STATIC_COUNT=0
  for ipset in "$TCP_IPSET" "$UDP_IPSET" "$STUN_IPSET"; do
    [ -n "$ipset" ] || continue
    STATIC_COUNT=$((STATIC_COUNT + $(count_non_comment_lines "$(expand_cfg_path "$ipset")")))
  done
  COVERAGE="n/a"
  IPV6_STATUS="n/a"
  if [ "$MODE" = "vpn" ]; then
    if [ "$AUTO_IP_COUNT" -eq 0 ] && [ "$STATIC_COUNT" -eq 0 ]; then
      COVERAGE="empty"
    elif [ "$AUTO_IP_COUNT" -gt 0 ] && [ "$STATIC_COUNT" -eq 0 ]; then
      COVERAGE="auto_only"
    elif [ "$AUTO_IP_COUNT" -eq 0 ] && [ "$STATIC_COUNT" -gt 0 ]; then
      COVERAGE="static_only"
    else
      COVERAGE="mixed"
    fi
    if [ "$AUTO_IPV6_COUNT" -eq 0 ]; then IPV6_STATUS="empty"; else IPV6_STATUS="present"; fi
  fi
  echo "$SERVICE_ID | $NAME | enabled=$ENABLED | mode=$MODE | vpn_profile=$VPN_PROFILE | tcp=$TCP_STRATEGY | udp=$UDP_STRATEGY | stun=$STUN_STRATEGY | custom=$CUSTOM | domains=$DOMAIN_COUNT | auto_ip=$AUTO_IP_COUNT | auto_ipv6=$AUTO_IPV6_COUNT | coverage=$COVERAGE | ipv6=$IPV6_STATUS"
done
