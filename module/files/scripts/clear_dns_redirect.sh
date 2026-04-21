#!/system/bin/sh
. "$(dirname "$0")/common.sh"
CHAIN="ZAPRET2_DNS"
CHAIN_UDP="ZAPRET2_DNS_UDP"
CHAIN_TCP="ZAPRET2_DNS_TCP"
safe_iptables() { iptables "$@" 2>/dev/null; }
safe_iptables -t nat -D OUTPUT -p udp --dport 53 -j "$CHAIN"
safe_iptables -t nat -D OUTPUT -p tcp --dport 53 -j "$CHAIN"
safe_iptables -t nat -D OUTPUT -p udp --dport 53 -j "$CHAIN_UDP"
safe_iptables -t nat -D OUTPUT -p tcp --dport 53 -j "$CHAIN_TCP"
safe_iptables -t nat -F "$CHAIN_UDP"
safe_iptables -t nat -X "$CHAIN_UDP"
safe_iptables -t nat -F "$CHAIN_TCP"
safe_iptables -t nat -X "$CHAIN_TCP"
safe_iptables -t nat -F "$CHAIN"
safe_iptables -t nat -X "$CHAIN"
rm -f "$RUNTIME_DIR/dns_redirect.enabled"
echo ok
