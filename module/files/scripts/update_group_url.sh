#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/update_group_url.log"
TMP_DIR="$RUNTIME_DIR/tmp"
GROUP_ID="$1"

[ -n "$GROUP_ID" ] || { echo "usage: update_group_url.sh group_0001"; exit 1; }

GROUP_DIR="$CFG_DIR/groups/$GROUP_ID"
PROFILES_FILE="$GROUP_DIR/profiles.txt"
SOURCE_FILE="$GROUP_DIR/source_url.txt"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"

[ -d "$GROUP_DIR" ] || { echo "group not found"; exit 1; }
[ -f "$SOURCE_FILE" ] || { echo "group has no saved source url"; exit 1; }

URL="$(cat "$SOURCE_FILE" 2>/dev/null | tr -d '\r\n')"
[ -n "$URL" ] || { echo "group has empty source url"; exit 1; }

mkdir -p "$TMP_DIR"
TMP_FILE="$TMP_DIR/group_update_${GROUP_ID}_$(date +%s).txt"
NEW_PROFILES_FILE="$TMP_DIR/group_update_${GROUP_ID}_profiles_$$.txt"
: > "$NEW_PROFILES_FILE"

log_msg "$LOGFILE" "update begin group_id=$GROUP_ID url=$URL"

cleanup_failed_profiles() {
  while IFS= read -r profile_id || [ -n "$profile_id" ]; do
    profile_id="$(printf '%s' "$profile_id" | tr -d '\r')"
    [ -n "$profile_id" ] || continue
    rm -rf "$CFG_DIR/profiles/$profile_id"
  done < "$NEW_PROFILES_FILE"
}

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --silent --show-error "$URL" -o "$TMP_FILE"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_msg "$LOGFILE" "curl download failed rc=$RC"
    rm -f "$TMP_FILE" "$NEW_PROFILES_FILE"
    echo "download failed"
    exit 1
  fi
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMP_FILE" "$URL"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_msg "$LOGFILE" "wget download failed rc=$RC"
    rm -f "$TMP_FILE" "$NEW_PROFILES_FILE"
    echo "download failed"
    exit 1
  fi
else
  log_msg "$LOGFILE" "no curl or wget found"
  rm -f "$TMP_FILE" "$NEW_PROFILES_FILE"
  echo "no curl or wget found"
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | tr -d '\r')"
  [ -n "$line" ] || continue
  case "$line" in
    vless://*)
      PROFILE_ID="$(sh "$(dirname "$0")/add_profile.sh" "$line" "$GROUP_ID")"
      if [ -n "$PROFILE_ID" ]; then
        printf '%s\n' "$PROFILE_ID" >> "$NEW_PROFILES_FILE"
        log_msg "$LOGFILE" "added new profile $PROFILE_ID to $GROUP_ID"
      else
        log_msg "$LOGFILE" "failed to add profile from line"
      fi
      ;;
  esac
done < "$TMP_FILE"

NEW_COUNT="$(grep -c . "$NEW_PROFILES_FILE" 2>/dev/null)"
if [ "${NEW_COUNT:-0}" -le 0 ]; then
  cleanup_failed_profiles
  rm -f "$TMP_FILE" "$NEW_PROFILES_FILE"
  log_msg "$LOGFILE" "update failed: no profiles parsed"
  echo "no profiles parsed"
  exit 1
fi

OLD_ACTIVE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"
ACTIVE_WAS_IN_GROUP=false
if [ -n "$OLD_ACTIVE" ] && [ -f "$PROFILES_FILE" ] && grep -q "^${OLD_ACTIVE}$" "$PROFILES_FILE" 2>/dev/null; then
  ACTIVE_WAS_IN_GROUP=true
fi

if [ -f "$PROFILES_FILE" ]; then
  while IFS= read -r old_profile_id || [ -n "$old_profile_id" ]; do
    old_profile_id="$(printf '%s' "$old_profile_id" | tr -d '\r')"
    [ -n "$old_profile_id" ] || continue
    rm -rf "$CFG_DIR/profiles/$old_profile_id"
    log_msg "$LOGFILE" "deleted old profile $old_profile_id from $GROUP_ID"
  done < "$PROFILES_FILE"
fi

mv "$NEW_PROFILES_FILE" "$PROFILES_FILE"
rm -f "$TMP_FILE"

FIRST_NEW="$(head -n1 "$PROFILES_FILE" 2>/dev/null | tr -d '\r\n')"
if [ "$ACTIVE_WAS_IN_GROUP" = "true" ] && [ -n "$FIRST_NEW" ]; then
  sh "$(dirname "$0")/set_active_profile.sh" "$FIRST_NEW" >> "$LOGFILE" 2>&1
else
  sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1
fi

log_msg "$LOGFILE" "update done group_id=$GROUP_ID count=$NEW_COUNT active_was_in_group=$ACTIVE_WAS_IN_GROUP"
echo "updated $GROUP_ID profiles=$NEW_COUNT"
