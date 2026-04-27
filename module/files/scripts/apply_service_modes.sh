#!/system/bin/sh
. "$(dirname "$0")/common.sh"
LOGFILE="$LOG_DIR/service-modes.log"
log_msg "$LOGFILE" "apply_service_modes begin"

DIRTY_FULL=false
DIRTY_ZAPRET=false
[ -f "$RUNTIME_DIR/dirty/full" ] && DIRTY_FULL=true
[ -f "$RUNTIME_DIR/dirty/zapret" ] && DIRTY_ZAPRET=true

sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_state.sh" >> "$LOGFILE" 2>&1

STATE="$CFG_DIR/app_state.json"
ZAPRET_ENABLED="false"
[ -f "$STATE" ] && ZAPRET_ENABLED="$(json_bool zapret_enabled "$STATE")"

if [ "$DIRTY_ZAPRET" = "true" ] && [ "$DIRTY_FULL" != "true" ]; then
  log_msg "$LOGFILE" "apply_service_modes quick zapret-only"
  if [ "$ZAPRET_ENABLED" = "true" ]; then
    sh "$(dirname "$0")/apply_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1
    sh "$(dirname "$0")/start_zapret.sh" >> "$LOGFILE" 2>&1
  else
    sh "$(dirname "$0")/clear_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1
    sh "$(dirname "$0")/stop_zapret.sh" >> "$LOGFILE" 2>&1
  fi
else
  log_msg "$LOGFILE" "apply_service_modes full dirty_full=$DIRTY_FULL dirty_zapret=$DIRTY_ZAPRET"
  sh "$(dirname "$0")/rebuild_service_ipsets.sh" --vpn-only >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/stop_all.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/start_all.sh" >> "$LOGFILE" 2>&1
fi

VPN_COUNT="$(service_mode_count vpn)"
ZAPRET_COUNT="$(service_mode_count zapret)"
ACTIVE_PROFILE="$(cat "$CFG_DIR/active_profile.txt" 2>/dev/null | tr -d '
')"
HAS_ACTIVE=false
if [ -n "$ACTIVE_PROFILE" ] && [ -f "$CFG_DIR/profiles/$ACTIVE_PROFILE/meta.conf" ]; then
  HAS_ACTIVE=true
fi

if [ "$VPN_COUNT" -gt 0 ] && [ "$HAS_ACTIVE" != "true" ]; then
  echo "warning: vpn services configured but no active profile"
  log_msg "$LOGFILE" "warning no active profile for vpn services"
else
  echo ok
fi

clear_service_apply_dirty
log_msg "$LOGFILE" "apply_service_modes done vpn_count=$VPN_COUNT zapret_count=$ZAPRET_COUNT has_active=$HAS_ACTIVE"
