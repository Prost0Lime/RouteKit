#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/set_zapret_profile.log"
STATE_FILE="$CFG_DIR/app_state.json"
PROFILE_ID="$1"

if [ -z "$PROFILE_ID" ]; then
  echo "usage: set_zapret_profile.sh profile_id"
  exit 1
fi

PROFILE_FILE="$CFG_DIR/zapret_profiles/$PROFILE_ID.conf"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "zapret profile not found"
  exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "state file missing"
  exit 1
fi

TMP_FILE="${STATE_FILE}.tmp"

sed "s/\"selected_zapret_profile\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"selected_zapret_profile\": \"$PROFILE_ID\"/" \
  "$STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"

log_msg "$LOGFILE" "selected zapret profile set to $PROFILE_ID"

echo "ok"