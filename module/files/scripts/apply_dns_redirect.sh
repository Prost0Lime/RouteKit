#!/system/bin/sh
. "$(dirname "$0")/common.sh"
CHAIN="ZAPRET2_DNS"
CHAIN_UDP="ZAPRET2_DNS_UDP"
CHAIN_TCP="ZAPRET2_DNS_TCP"
LOGFILE="$LOG_DIR/dns-redirect.log"

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

safe_iptables -t nat -N "$CHAIN" || exit 1
safe_iptables -t nat -N "$CHAIN_UDP" || exit 1
safe_iptables -t nat -N "$CHAIN_TCP" || exit 1

safe_iptables -t nat -A "$CHAIN" -o lo -j RETURN
safe_iptables -t nat -A "$CHAIN" -m owner --uid-owner 0 -j RETURN

safe_iptables -t nat -A "$CHAIN_UDP" -j "$CHAIN" || exit 1
safe_iptables -t nat -A "$CHAIN_UDP" -p udp -j REDIRECT --to-ports 1053 || exit 1

safe_iptables -t nat -A "$CHAIN_TCP" -j "$CHAIN" || exit 1
safe_iptables -t nat -A "$CHAIN_TCP" -p tcp -j REDIRECT --to-ports 1053 || exit 1

safe_iptables -t nat -A OUTPUT -p udp --dport 53 -j "$CHAIN_UDP" || exit 1
safe_iptables -t nat -A OUTPUT -p tcp --dport 53 -j "$CHAIN_TCP" || exit 1
: > "$RUNTIME_DIR/dns_redirect.enabled"
log_msg "$LOGFILE" "dns redirect enabled to 127.0.0.1:1053 for udp/tcp 53"
echo ok
