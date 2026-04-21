#!/system/bin/sh
. "$(dirname "$0")/common.sh"

PROFILES_DIR="$CFG_DIR/profiles"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
ACTIVE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

FOUND=0

for dir in "$PROFILES_DIR"/profile_*; do
  [ -d "$dir" ] || continue
  META="$dir/meta.conf"
  [ -f "$META" ] || continue
  . "$META"

  MARK=" "
  [ "$PROFILE_ID" = "$ACTIVE_ID" ] && MARK="*"

  GROUP_LABEL="$GROUP_ID"
  if [ -n "$GROUP_ID" ] && [ -f "$CFG_DIR/groups/$GROUP_ID/name.txt" ]; then
    GROUP_LABEL="$(cat "$CFG_DIR/groups/$GROUP_ID/name.txt" 2>/dev/null | tr -d '\r\n')"
  fi
  [ -n "$GROUP_LABEL" ] || GROUP_LABEL="-"

  [ -n "$GROUP_ID" ] || GROUP_ID="-"
  echo "$MARK $PROFILE_ID | $PROFILE_NAME | $SERVER:$PORT | group_id=$GROUP_ID | group=$GROUP_LABEL | server=$SERVER | port=$PORT"
  FOUND=1
done

if [ "$FOUND" -eq 0 ]; then
  echo "no profiles"
fi
