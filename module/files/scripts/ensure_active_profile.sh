#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/ensure_active_profile.log"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
PROFILES_DIR="$CFG_DIR/profiles"

log_msg "$LOGFILE" "ensure_active_profile begin"
CURRENT_ACTIVE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '
')"
if [ -n "$CURRENT_ACTIVE" ] && [ -f "$PROFILES_DIR/$CURRENT_ACTIVE/meta.conf" ]; then
  log_msg "$LOGFILE" "active profile is valid: $CURRENT_ACTIVE"
  exit 0
fi

NEXT_PROFILE=""
for dir in "$PROFILES_DIR"/profile_*; do
  [ -d "$dir" ] || continue
  PROFILE_ID="$(basename "$dir")"
  if [ -f "$dir/meta.conf" ]; then
    NEXT_PROFILE="$PROFILE_ID"
    break
  fi
done

if [ -n "$NEXT_PROFILE" ]; then
  echo "$NEXT_PROFILE" > "$ACTIVE_FILE"
  log_msg "$LOGFILE" "fallback active profile selected: $NEXT_PROFILE"
  sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
  exit 0
fi

echo "" > "$ACTIVE_FILE"
log_msg "$LOGFILE" "no profiles left, active profile cleared"
sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/clear_transproxy.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/stop_proxy.sh" >> "$LOGFILE" 2>&1
log_msg "$LOGFILE" "ensure_active_profile done: proxy stopped"
