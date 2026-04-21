#!/system/bin/sh
. "$(dirname "$0")/common.sh"
CHAIN="ZAPRET2_V6_BLOCK"
LOGFILE="$LOG_DIR/ipv6-block.log"
safe_ip6tables() { ip6tables "$@" 2>/dev/null; }
safe_ip6tables -D OUTPUT -j "$CHAIN"
safe_ip6tables -F "$CHAIN"
safe_ip6tables -X "$CHAIN"
safe_ip6tables -N "$CHAIN" || exit 1
safe_ip6tables -A "$CHAIN" -o lo -j RETURN
safe_ip6tables -A "$CHAIN" -j REJECT
safe_ip6tables -A OUTPUT -j "$CHAIN" || exit 1
: > "$RUNTIME_DIR/ipv6_block.enabled"
log_msg "$LOGFILE" "global ipv6 block enabled"
echo ok
