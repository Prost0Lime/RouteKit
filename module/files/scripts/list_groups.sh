#!/system/bin/sh
. "$(dirname "$0")/common.sh"

GROUPS_DIR="$CFG_DIR/groups"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
ACTIVE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

FOUND=0

for dir in "$GROUPS_DIR"/group_*; do
  [ -d "$dir" ] || continue

  GROUP_ID="$(basename "$dir")"
  NAME_FILE="$dir/name.txt"
  PROFILES_FILE="$dir/profiles.txt"

  GROUP_NAME=""
  [ -f "$NAME_FILE" ] && GROUP_NAME="$(cat "$NAME_FILE" 2>/dev/null | tr -d '\r')"
  [ -n "$GROUP_NAME" ] || GROUP_NAME="$GROUP_ID"

  COUNT=0
  HAS_ACTIVE="no"

  if [ -f "$PROFILES_FILE" ]; then
    COUNT="$(grep -c . "$PROFILES_FILE" 2>/dev/null)"
    if [ -n "$ACTIVE_ID" ] && grep -q "^${ACTIVE_ID}$" "$PROFILES_FILE" 2>/dev/null; then
      HAS_ACTIVE="yes"
    fi
  fi

  echo "$GROUP_ID | $GROUP_NAME | profiles=$COUNT | active=$HAS_ACTIVE"
  FOUND=1
done

if [ "$FOUND" -eq 0 ]; then
  echo "no groups"
fi