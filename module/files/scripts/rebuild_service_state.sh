#!/system/bin/sh
. "$(dirname "$0")/common.sh"
PROXY_DOMAINS_FILE="$CFG_DIR/proxy_domains.txt"
DIRECT_DOMAINS_FILE="$CFG_DIR/direct_domains.txt"
mkdir -p "$CFG_DIR"
: > "$PROXY_DOMAINS_FILE"
: > "$DIRECT_DOMAINS_FILE"
append_domains() {
  SRC="$1"
  DST="$2"
  [ -f "$SRC" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in \#*) continue ;; esac
    grep -qxF "$line" "$DST" 2>/dev/null || echo "$line" >> "$DST"
  done < "$SRC"
}
for f in $(service_mode_files); do
  SERVICE_ID=""; ENABLED="true"; MODE="direct"; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; . "$f"
  [ "$ENABLED" = "true" ] || continue
  case "$MODE" in
    vpn)
      append_domains "$TCP_HOSTLIST" "$PROXY_DOMAINS_FILE"
      append_domains "$UDP_HOSTLIST" "$PROXY_DOMAINS_FILE"
      append_domains "$STUN_HOSTLIST" "$PROXY_DOMAINS_FILE"
      ;;
    direct)
      append_domains "$TCP_HOSTLIST" "$DIRECT_DOMAINS_FILE"
      append_domains "$UDP_HOSTLIST" "$DIRECT_DOMAINS_FILE"
      append_domains "$STUN_HOSTLIST" "$DIRECT_DOMAINS_FILE"
      ;;
  esac
done
echo ok
