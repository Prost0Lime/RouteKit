#!/system/bin/sh
. "$(dirname "$0")/common.sh"
LOGFILE="$LOG_DIR/service-modes.log"
log_msg "$LOGFILE" "apply_service_modes begin"

sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_ipsets.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/stop_all.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/start_all.sh" >> "$LOGFILE" 2>&1

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

log_msg "$LOGFILE" "apply_service_modes done vpn_count=$VPN_COUNT zapret_count=$ZAPRET_COUNT has_active=$HAS_ACTIVE"
