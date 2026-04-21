#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
SRC_FILE="$2"
[ -n "$SERVICE_ID" ] && [ -n "$SRC_FILE" ] || { echo "usage: $0 <service_id> <domains_file>"; exit 1; }
MODE_FILE="$(service_mode_file_for "$SERVICE_ID")" || { echo "service not found: $SERVICE_ID"; exit 1; }
SERVICE_ID=""; TCP_HOSTLIST=""; . "$MODE_FILE"
TARGET="${TCP_HOSTLIST//\$CFG_DIR/$CFG_DIR}"
[ -n "$TARGET" ] || TARGET="$CFG_DIR/hostlists/$SERVICE_ID.txt"

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

normalize_domains_file "$SRC_FILE" > "$TARGET"
echo ok
