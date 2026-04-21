#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/import_group.log"
GROUP_COUNTER_FILE="$CFG_DIR/group_counter.txt"
GROUPS_DIR="$CFG_DIR/groups"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"

FILE_PATH="$1"
GROUP_NAME="$2"

if [ -z "$FILE_PATH" ]; then
  echo "usage: import_group_file.sh /path/to/file.txt [group_name]"
  exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
  echo "file not found"
  exit 1
fi

mkdir -p "$GROUPS_DIR"

COUNTER="$(cat "$GROUP_COUNTER_FILE" 2>/dev/null)"
[ -n "$COUNTER" ] || COUNTER=0
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$GROUP_COUNTER_FILE"

GROUP_ID="$(printf "group_%04d" "$COUNTER")"
[ -n "$GROUP_NAME" ] || GROUP_NAME="$GROUP_ID"

GROUP_DIR="$GROUPS_DIR/$GROUP_ID"
mkdir -p "$GROUP_DIR"

echo "$GROUP_NAME" > "$GROUP_DIR/name.txt"
: > "$GROUP_DIR/profiles.txt"

log_msg "$LOGFILE" "group import begin group_id=$GROUP_ID name=$GROUP_NAME file=$FILE_PATH"

FIRST_PROFILE_ID=""

while IFS= read -r line || [ -n "$line" ]; do
  line="$(echo "$line" | tr -d '\r')"
  [ -n "$line" ] || continue

  case "$line" in
    vless://*)
      PROFILE_ID="$(sh "$(dirname "$0")/add_profile.sh" "$line" "$GROUP_ID")"
      if [ -n "$PROFILE_ID" ]; then
        echo "$PROFILE_ID" >> "$GROUP_DIR/profiles.txt"
        log_msg "$LOGFILE" "added $PROFILE_ID to $GROUP_ID"

        if [ -z "$FIRST_PROFILE_ID" ]; then
          FIRST_PROFILE_ID="$PROFILE_ID"
        fi
      else
        log_msg "$LOGFILE" "failed to add profile from line"
      fi
      ;;
    *)
      log_msg "$LOGFILE" "skipped non-vless line"
      ;;
  esac
done < "$FILE_PATH"

CURRENT_ACTIVE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

if [ -z "$CURRENT_ACTIVE" ] && [ -n "$FIRST_PROFILE_ID" ]; then
  log_msg "$LOGFILE" "no active profile, auto-selecting $FIRST_PROFILE_ID"
  sh "$(dirname "$0")/set_active_profile.sh" "$FIRST_PROFILE_ID" >> "$LOGFILE" 2>&1
fi

echo "$GROUP_ID"
log_msg "$LOGFILE" "group import done group_id=$GROUP_ID first_profile=$FIRST_PROFILE_ID"