#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/remove_proxy_domain.log"
FILE="$CFG_DIR/proxy_domains.txt"
DOMAIN="$1"

normalize_domain() {
  echo "$1" \
    | tr -d '\r' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

if [ -z "$DOMAIN" ]; then
  echo "usage: remove_proxy_domain.sh domain.com"
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "proxy domains file missing"
  exit 1
fi

DOMAIN="$(normalize_domain "$DOMAIN")"

TMP_FILE="${FILE}.tmp"

while IFS= read -r line || [ -n "$line" ]; do
  CLEAN="$(normalize_domain "$line")"
  if [ "$CLEAN" = "$DOMAIN" ]; then
    continue
  fi
  echo "$line"
done < "$FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$FILE"

log_msg "$LOGFILE" "removed $DOMAIN"

sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1

echo "ok"