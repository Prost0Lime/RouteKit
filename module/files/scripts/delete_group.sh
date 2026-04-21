#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/delete_group.log"
GROUP_ID="$1"

if [ -z "$GROUP_ID" ]; then
  echo "usage: delete_group.sh group_0001"
  exit 1
fi

GROUP_DIR="$CFG_DIR/groups/$GROUP_ID"
PROFILES_FILE="$GROUP_DIR/profiles.txt"

if [ ! -d "$GROUP_DIR" ]; then
  echo "group not found"
  exit 1
fi

if [ -f "$PROFILES_FILE" ]; then
  while IFS= read -r PROFILE_ID || [ -n "$PROFILE_ID" ]; do
    PROFILE_ID="$(echo "$PROFILE_ID" | tr -d '\r')"
    [ -n "$PROFILE_ID" ] || continue

    rm -rf "$CFG_DIR/profiles/$PROFILE_ID"
    log_msg "$LOGFILE" "deleted profile from group $GROUP_ID: $PROFILE_ID"
  done < "$PROFILES_FILE"
fi

rm -rf "$GROUP_DIR"
log_msg "$LOGFILE" "group deleted: $GROUP_ID"

sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1

echo "deleted $GROUP_ID"