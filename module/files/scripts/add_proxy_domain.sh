#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/add_proxy_domain.log"
FILE="$CFG_DIR/proxy_domains.txt"
DOMAIN="$1"

normalize_domain() {
  echo "$1" \
    | tr -d '\r' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_trailing_newline() {
  TARGET_FILE="$1"
  [ -s "$TARGET_FILE" ] || return 0

  LAST_HEX="$(tail -c 1 "$TARGET_FILE" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [ "$LAST_HEX" = "0a" ] && return 0

  echo >> "$TARGET_FILE"
}

if [ -z "$DOMAIN" ]; then
  echo "usage: add_proxy_domain.sh domain.com"
  exit 1
fi

touch "$FILE"

DOMAIN="$(normalize_domain "$DOMAIN")"

case "$DOMAIN" in
  \#*|"")
    echo "invalid domain"
    exit 1
    ;;
esac

if grep -Fxiq "$DOMAIN" "$FILE" 2>/dev/null; then
  echo "already exists"
  exit 0
fi

ensure_trailing_newline "$FILE"
echo "$DOMAIN" >> "$FILE"

log_msg "$LOGFILE" "added $DOMAIN"

sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1

echo "ok"