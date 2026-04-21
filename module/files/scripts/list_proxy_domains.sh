#!/system/bin/sh
. "$(dirname "$0")/common.sh"

FILE="$CFG_DIR/proxy_domains.txt"

if [ ! -f "$FILE" ]; then
  echo "proxy domains file missing"
  exit 1
fi

grep -v '^[[:space:]]*$' "$FILE" | grep -v '^[[:space:]]*#'