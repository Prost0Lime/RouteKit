#!/system/bin/sh
. "$(dirname "$0")/common.sh"

GROUP_ID="$1"
if [ -z "$GROUP_ID" ]; then
  echo "usage: show_group_profiles.sh group_0001"
  exit 1
fi

GROUP_DIR="$CFG_DIR/groups/$GROUP_ID"
PROFILES_FILE="$GROUP_DIR/profiles.txt"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
ACTIVE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

if [ ! -d "$GROUP_DIR" ]; then
  echo "group not found"
  exit 1
fi

if [ ! -f "$PROFILES_FILE" ]; then
  echo "group has no profiles"
  exit 0
fi

FOUND=0

while IFS= read -r PROFILE_ID || [ -n "$PROFILE_ID" ]; do
  PROFILE_ID="$(echo "$PROFILE_ID" | tr -d '\r')"
  [ -n "$PROFILE_ID" ] || continue

  META_FILE="$CFG_DIR/profiles/$PROFILE_ID/meta.conf"
  MARK=" "
  [ "$PROFILE_ID" = "$ACTIVE_ID" ] && MARK="*"

  if [ -f "$META_FILE" ]; then
    . "$META_FILE"
    echo "$MARK $PROFILE_ID | $PROFILE_NAME | $SERVER:$PORT"
  else
    echo "$MARK $PROFILE_ID | missing metadata"
  fi
  FOUND=1
done < "$PROFILES_FILE"

if [ "$FOUND" -eq 0 ]; then
  echo "group has no profiles"
fi