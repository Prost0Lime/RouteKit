#!/system/bin/sh
. "$(dirname "$0")/common.sh"
CHAIN="ZAPRET2_V6_BLOCK"
safe_ip6tables() { ip6tables "$@" 2>/dev/null; }
safe_ip6tables -D OUTPUT -j "$CHAIN"
safe_ip6tables -F "$CHAIN"
safe_ip6tables -X "$CHAIN"
rm -f "$RUNTIME_DIR/ipv6_block.enabled"
echo ok
