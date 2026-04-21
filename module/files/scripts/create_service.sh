#!/system/bin/sh
. "$(dirname "$0")/common.sh"
NAME="$1"
MODE="$2"
DOMAINS_FILE="$3"
[ -n "$NAME" ] || { echo "usage: $0 <name> <direct|zapret|vpn> [domains_file]"; exit 1; }
[ -n "$MODE" ] || MODE="direct"
case "$MODE" in direct|zapret|vpn) ;; *) echo "invalid mode"; exit 1 ;; esac
slug=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g; s/__*/_/g; s/^_//; s/_$//')
[ -n "$slug" ] || slug="custom_service"
SERVICE_ID="$slug"
idx=1
while [ -f "$CFG_DIR/service_modes/$SERVICE_ID.conf" ]; do
  idx=$((idx + 1))
  SERVICE_ID="${slug}_${idx}"
done
HOSTLIST="$CFG_DIR/hostlists/$SERVICE_ID.txt"
IPSET="$CFG_DIR/ipsets/$SERVICE_ID.txt"
: > "$HOSTLIST"
: > "$IPSET"

normalize_domains_file() {
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    {
      line=$0
      gsub(/\r/, "", line)
      raw=line
      line=trim(line)
      if (line == "" || line ~ /^#/) {
        print raw
        next
      }
      line=tolower(line)
      sub(/\.$/, "", line)
      if (line ~ /^\*\./) {
        line="suffix:" substr(line, 3)
      } else if (line ~ /^suffix:/) {
        sub(/^suffix:\*\./, "suffix:", line)
        sub(/\.$/, "", line)
      }
      print line
    }
  ' "$1"
}

if [ -n "$DOMAINS_FILE" ] && [ -f "$DOMAINS_FILE" ]; then
  normalize_domains_file "$DOMAINS_FILE" > "$HOSTLIST"
fi
cat > "$CFG_DIR/services/$SERVICE_ID.conf" <<EOT
SERVICE_ID="$SERVICE_ID"
SERVICE_NAME="$NAME"
CUSTOM_SERVICE="true"
EOT
cat > "$CFG_DIR/service_modes/$SERVICE_ID.conf" <<EOT
SERVICE_ID="$SERVICE_ID"
ENABLED="true"
MODE="$MODE"
VPN_PROFILE="active"
TCP_STRATEGY=""
UDP_STRATEGY=""
STUN_STRATEGY=""
TCP_HOSTLIST="\$CFG_DIR/hostlists/$SERVICE_ID.txt"
TCP_IPSET="\$CFG_DIR/ipsets/$SERVICE_ID.txt"
UDP_HOSTLIST=""
UDP_IPSET="\$CFG_DIR/ipsets/$SERVICE_ID.txt"
STUN_HOSTLIST=""
STUN_IPSET=""
EOT
echo "$SERVICE_ID"
