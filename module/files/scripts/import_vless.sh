#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/import_vless.log"
URI="$1"
PROFILE_NAME="$2"

log_msg "$LOGFILE" "import_vless begin"

PROFILE_ID="$(sh "$(dirname "$0")/add_profile.sh" "$URI" "" "$PROFILE_NAME")"
if [ -z "$PROFILE_ID" ]; then
  log_msg "$LOGFILE" "failed to create profile"
  exit 1
fi

sh "$(dirname "$0")/set_active_profile.sh" "$PROFILE_ID" >> "$LOGFILE" 2>&1

log_msg "$LOGFILE" "import_vless done profile_id=$PROFILE_ID"
echo "$PROFILE_ID"