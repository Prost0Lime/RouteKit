#!/system/bin/sh
. "$(dirname "$0")/common.sh"

SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }

MODE_FILE="$CFG_DIR/service_modes/$SERVICE_ID.conf"
[ -f "$MODE_FILE" ] || { echo "service not found: $SERVICE_ID"; exit 1; }

SERVICE_NAME="$SERVICE_ID"
CUSTOM_SERVICE="false"
[ -f "$CFG_DIR/services/$SERVICE_ID.conf" ] && . "$CFG_DIR/services/$SERVICE_ID.conf"

ENABLED="true"
MODE="direct"
VPN_PROFILE="active"
TCP_STRATEGY=""
UDP_STRATEGY=""
STUN_STRATEGY=""
. "$MODE_FILE"

AUTO_V4="$RUNTIME_DIR/ipsets_auto/$SERVICE_ID.txt"
AUTO_V6="$RUNTIME_DIR/ipsets_auto_v6/$SERVICE_ID.txt"
UNRESOLVED_FILE="$(service_unresolved_file_for "$SERVICE_ID")"
COVERAGE_TMP="$RUNTIME_DIR/tmp/diagnose_${SERVICE_ID}_$$.coverage"
mkdir -p "$RUNTIME_DIR/tmp"
sh "$(dirname "$0")/show_service_coverage.sh" "$SERVICE_ID" > "$COVERAGE_TMP" 2>/dev/null

DOMAIN_COUNT="0"
AUTO_IP_COUNT="0"
AUTO_IPV6_COUNT="0"
UNRESOLVED_COUNT="0"
CONFLICT_COUNT="0"
MODE_CONFLICT_COUNT="0"
TOTAL_IP_COUNT="0"
COVERAGE_STATUS="unknown"
IPV6_STATUS="unknown"
. "$COVERAGE_TMP" 2>/dev/null
rm -f "$COVERAGE_TMP"

private_dns_mode=""
private_dns_specifier=""
if command -v settings >/dev/null 2>&1; then
  private_dns_mode="$(settings get global private_dns_mode 2>/dev/null)"
  private_dns_specifier="$(settings get global private_dns_specifier 2>/dev/null)"
fi

dns_state="missing"
[ -f "$RUNTIME_DIR/dns_redirect.enabled" ] && dns_state="enabled"
dns_udp_rule_count="$(iptables -t nat -S 2>/dev/null | grep -c 'ZAPRET2_DNS_UDP')"
dns_tcp_rule_count="$(iptables -t nat -S 2>/dev/null | grep -c 'ZAPRET2_DNS_TCP')"

listener_text=""
if command -v ss >/dev/null 2>&1; then
  listener_text="$(ss -lntup 2>/dev/null)"
elif command -v netstat >/dev/null 2>&1; then
  listener_text="$(netstat -lntup 2>/dev/null)"
fi
proxy_12345="missing"
dns_1053_udp="missing"
dns_1053_tcp="missing"
printf '%s\n' "$listener_text" | grep -q ':12345' && proxy_12345="ok"
printf '%s\n' "$listener_text" | grep -q 'udp.*:1053' && dns_1053_udp="ok"
printf '%s\n' "$listener_text" | grep -q 'tcp.*:1053' && dns_1053_tcp="ok"

expected_rules=0
present_rules=0
missing_rules=0
service_hits=0
missing_rules_list=""
hit_lines=""

if [ -s "$AUTO_V4" ]; then
  while IFS= read -r cidr || [ -n "$cidr" ]; do
    [ -n "$cidr" ] || continue
    ip="${cidr%/*}"
    expected_rules=$((expected_rules + 2))

    for port in 80 443; do
      if iptables -t nat -S ZAPRET2_TRANS 2>/dev/null | grep -F -- "-d $cidr" | grep -q -- "--dport $port"; then
        present_rules=$((present_rules + 1))
      else
        missing_rules=$((missing_rules + 1))
        missing_rules_list="${missing_rules_list}${cidr}:tcp/${port}\n"
      fi
    done

    ip_hits="$(iptables -t nat -vnL ZAPRET2_TRANS 2>/dev/null | awk -v ip="$ip" 'index($0, ip) && $0 ~ /REDIRECT/ { sum += $1 } END { print sum + 0 }')"
    service_hits=$((service_hits + ip_hits))
    [ "$ip_hits" -gt 0 ] && hit_lines="${hit_lines}${ip} hits=${ip_hits}\n"
  done < "$AUTO_V4"
fi

status="OK"
recommendations=""
repair_action="none"
repair_reason="no_issue_detected"
repair_command="sh scripts/repair_service.sh $SERVICE_ID"

if [ "$ENABLED" != "true" ]; then
  status="WARN"
  recommendations="${recommendations}- Service is disabled: enable it or change mode.\n"
  repair_action="manual"
  repair_reason="service_disabled"
fi

if [ "$MODE" != "vpn" ]; then
  recommendations="${recommendations}- Service is in $MODE mode; VPN transproxy checks are skipped.\n"
  if [ "$repair_action" != "manual" ] && [ "$MODE" = "zapret" ]; then
    repair_action="zapret_reapply"
    repair_reason="reapply_zapret_nfqueue_if_needed"
  elif [ "$repair_action" != "manual" ] && [ "$MODE" = "direct" ]; then
    repair_action="routing_reconcile"
    repair_reason="reconcile_transproxy_rules_if_needed"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && [ "$AUTO_IP_COUNT" -eq 0 ]; then
  status="FAIL"
  recommendations="${recommendations}- No IPv4 addresses for VPN transproxy: run force rebuild.\n"
  if [ "$repair_action" != "manual" ]; then
    repair_action="vpn_rebuild_apply"
    repair_reason="missing_ipv4"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && [ "$missing_rules" -gt 0 ]; then
  status="FAIL"
  recommendations="${recommendations}- Some IPv4 rules are missing: press Start or apply service modes.\n"
  if [ "$repair_action" != "manual" ]; then
    repair_action="vpn_rebuild_apply"
    repair_reason="missing_transproxy_rules"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && { [ "$dns_state" != "enabled" ] || [ "$dns_udp_rule_count" -eq 0 ] || [ "$dns_tcp_rule_count" -eq 0 ]; }; then
  [ "$status" = "OK" ] && status="WARN"
  recommendations="${recommendations}- DNS redirect looks incomplete: reapply DNS redirect or start_all.\n"
  if [ "$repair_action" = "none" ]; then
    repair_action="vpn_rebuild_apply"
    repair_reason="dns_redirect_incomplete"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && [ "$private_dns_mode" != "" ] && [ "$private_dns_mode" != "off" ]; then
  [ "$status" = "OK" ] && status="WARN"
  recommendations="${recommendations}- Private DNS is not off ($private_dns_mode): Android may bypass DNS redirect.\n"
  repair_action="manual"
  repair_reason="private_dns_not_off"
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && [ "$proxy_12345" != "ok" ]; then
  status="FAIL"
  recommendations="${recommendations}- Proxy listener 127.0.0.1:12345 is missing.\n"
  if [ "$repair_action" != "manual" ]; then
    repair_action="vpn_rebuild_apply"
    repair_reason="proxy_listener_missing"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && { [ "$dns_1053_udp" != "ok" ] || [ "$dns_1053_tcp" != "ok" ]; }; then
  [ "$status" = "OK" ] && status="WARN"
  recommendations="${recommendations}- DNS listener 127.0.0.1:1053 is incomplete.\n"
  if [ "$repair_action" = "none" ]; then
    repair_action="vpn_rebuild_apply"
    repair_reason="dns_listener_incomplete"
  fi
fi

if [ "$ENABLED" = "true" ] && [ "$MODE" = "vpn" ] && [ "$AUTO_IPV6_COUNT" -gt 0 ]; then
  recommendations="${recommendations}- IPv6 entries exist (${AUTO_IPV6_COUNT}), but current transproxy is IPv4-only; this is OK when IPv6 block is enabled.\n"
fi

echo "SUMMARY"
echo "status=$status"
[ -n "$recommendations" ] && printf 'recommendations:\n%b' "$recommendations" || echo "recommendations=<empty>"
echo

echo "REPAIR SUGGESTION"
echo "action=$repair_action"
echo "reason=$repair_reason"
if [ "$repair_action" = "manual" ]; then
  echo "can_auto_repair=false"
else
  echo "can_auto_repair=true"
fi
echo "command=$repair_command"
case "$repair_action" in
  vpn_rebuild_apply)
    echo "will_do=rebuild_ips, rebuild_proxy_config, start_proxy, apply_transproxy, apply_dns_redirect, apply_ipv6_block"
    ;;
  zapret_reapply)
    echo "will_do=rebuild_state, apply_zapret_nfqueue, start_zapret"
    ;;
  routing_reconcile)
    echo "will_do=rebuild_state, apply_transproxy"
    ;;
  manual)
    echo "will_do=manual_change_required"
    ;;
  *)
    echo "will_do=no_action_required"
    ;;
esac
echo

echo "SERVICE"
echo "id=$SERVICE_ID"
echo "name=$SERVICE_NAME"
echo "enabled=$ENABLED"
echo "mode=$MODE"
echo "custom=$CUSTOM_SERVICE"
echo "domains=$DOMAIN_COUNT"
echo "coverage=$COVERAGE_STATUS"
echo

echo "IP COVERAGE"
echo "ipv4=$AUTO_IP_COUNT"
echo "ipv6=$AUTO_IPV6_COUNT ($IPV6_STATUS)"
echo "unresolved=$UNRESOLVED_COUNT"
echo "conflicts=$CONFLICT_COUNT"
echo "mode_conflicts=$MODE_CONFLICT_COUNT"
echo

echo "DNS"
echo "redirect_state=$dns_state"
echo "iptables_udp_rules=$dns_udp_rule_count"
echo "iptables_tcp_rules=$dns_tcp_rule_count"
[ -n "$private_dns_mode" ] && echo "private_dns_mode=$private_dns_mode"
[ -n "$private_dns_specifier" ] && echo "private_dns_specifier=$private_dns_specifier"
echo

echo "PROXY"
echo "listener_12345=$proxy_12345"
echo "dns_listener_udp_1053=$dns_1053_udp"
echo "dns_listener_tcp_1053=$dns_1053_tcp"
echo

echo "TRANSPROXY FOR THIS SERVICE"
if [ "$MODE" = "vpn" ]; then
  echo "skipped=false"
  echo "expected_rules=$expected_rules"
  echo "present_rules=$present_rules"
  echo "missing_rules=$missing_rules"
  echo "service_redirect_hits=$service_hits"
  [ -n "$missing_rules_list" ] && printf 'missing:\n%b' "$missing_rules_list"
  [ -n "$hit_lines" ] && printf 'hits:\n%b' "$hit_lines"
else
  echo "skipped=true"
  echo "reason=service_mode_$MODE"
fi
echo

echo "IPV4"
if [ -s "$AUTO_V4" ]; then
  sed 's#/32##' "$AUTO_V4"
else
  echo "<empty>"
fi
echo

echo "IPV6"
if [ -s "$AUTO_V6" ]; then
  sed 's#/128##' "$AUTO_V6"
else
  echo "<empty>"
fi
echo

echo "UNRESOLVED"
if [ -s "$UNRESOLVED_FILE" ]; then
  sh "$(dirname "$0")/show_service_unresolved.sh" "$SERVICE_ID"
else
  echo "<empty>"
fi
