#!/system/bin/sh
. "$(dirname "$0")/common.sh"

FILE="$CFG_DIR/direct_domains.txt"

if [ ! -f "$FILE" ]; then
  echo "direct domains file missing"
  exit 1
fi

grep -v '^[[:space:]]*$' "$FILE" | grep -v '^[[:space:]]*#'