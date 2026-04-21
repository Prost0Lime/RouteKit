#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/delete_profile.log"
PROFILE_ID="$1"

if [ -z "$PROFILE_ID" ]; then
  echo "usage: delete_profile.sh profile_0001"
  exit 1
fi

PROFILE_DIR="$CFG_DIR/profiles/$PROFILE_ID"
META_FILE="$PROFILE_DIR/meta.conf"

if [ ! -d "$PROFILE_DIR" ]; then
  echo "profile not found"
  exit 1
fi

GROUP_ID=""
if [ -f "$META_FILE" ]; then
  . "$META_FILE"
fi

if [ -n "$GROUP_ID" ]; then
  GROUP_FILE="$CFG_DIR/groups/$GROUP_ID/profiles.txt"
  if [ -f "$GROUP_FILE" ]; then
    grep -v "^${PROFILE_ID}$" "$GROUP_FILE" > "${GROUP_FILE}.tmp" 2>/dev/null
    mv "${GROUP_FILE}.tmp" "$GROUP_FILE"
    log_msg "$LOGFILE" "removed $PROFILE_ID from group $GROUP_ID"
  fi
fi

rm -rf "$PROFILE_DIR"
log_msg "$LOGFILE" "profile deleted: $PROFILE_ID"

sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1

echo "deleted $PROFILE_ID"