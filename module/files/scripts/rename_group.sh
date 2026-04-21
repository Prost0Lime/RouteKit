#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/rename_group.log"
GROUP_ID="$1"
NEW_NAME="$2"

if [ -z "$GROUP_ID" ] || [ -z "$NEW_NAME" ]; then
  echo "usage: rename_group.sh group_0001 'New group name'"
  exit 1
fi

GROUP_DIR="$CFG_DIR/groups/$GROUP_ID"
NAME_FILE="$GROUP_DIR/name.txt"

if [ ! -d "$GROUP_DIR" ]; then
  echo "group not found"
  exit 1
fi

echo "$NEW_NAME" > "$NAME_FILE"

log_msg "$LOGFILE" "group renamed: $GROUP_ID -> $NEW_NAME"
echo "renamed $GROUP_ID"