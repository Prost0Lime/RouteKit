#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/rename_profile.log"
PROFILE_ID="$1"
NEW_NAME="$2"

if [ -z "$PROFILE_ID" ] || [ -z "$NEW_NAME" ]; then
  echo "usage: rename_profile.sh profile_0001 'New name'"
  exit 1
fi

META_FILE="$CFG_DIR/profiles/$PROFILE_ID/meta.conf"

if [ ! -f "$META_FILE" ]; then
  echo "profile not found"
  exit 1
fi

TMP_FILE="${META_FILE}.tmp"
sed "s|^PROFILE_NAME='.*'$|PROFILE_NAME='$NEW_NAME'|" "$META_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$META_FILE"

log_msg "$LOGFILE" "profile renamed: $PROFILE_ID -> $NEW_NAME"
echo "renamed $PROFILE_ID"