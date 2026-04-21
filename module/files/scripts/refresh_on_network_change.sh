#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/network-refresh.log"
STATE="$CFG_DIR/app_state.json"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
LOCKFILE="$RUNTIME_DIR/network_refresh.lock"
PIDFILE="$PID_DIR/proxy.pid"
LAST_REFRESH_FILE="$RUNTIME_DIR/network/last_refresh_at.txt"

clear_stale_lock "$LOCKFILE"
if [ -f "$LOCKFILE" ]; then
  log_msg "$LOGFILE" "refresh skipped: lock exists pid=$(cat "$LOCKFILE" 2>/dev/null)"
  exit 0
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

if ! wait_for_network_ready 5; then
  log_msg "$LOGFILE" "refresh proceed: network did not fully stabilize before timeout"
fi

NET_KEY="$(current_network_cache_key)"
NET_FP="$(network_fingerprint)"
log_msg "$LOGFILE" "refresh begin net=$NET_KEY fp=$NET_FP"
date +%s > "$LAST_REFRESH_FILE" 2>/dev/null

[ -f "$STATE" ] || {
  log_msg "$LOGFILE" "refresh skipped: state missing"
  exit 0
}

PROXY_ENABLED="$(json_bool proxy_enabled "$STATE")"
TRANSPROXY_ENABLED="$(json_bool transproxy_enabled "$STATE")"
DNS_REDIRECT_ENABLED="$(json_bool dns_redirect_enabled "$STATE")"
ROUTING_ENABLED="$(json_bool routing_enabled "$STATE")"

ACTIVE_PROFILE=""
[ -f "$ACTIVE_FILE" ] && ACTIVE_PROFILE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"
HAS_ACTIVE_PROFILE=false
if [ -n "$ACTIVE_PROFILE" ] && [ -f "$CFG_DIR/profiles/$ACTIVE_PROFILE/meta.conf" ]; then
  HAS_ACTIVE_PROFILE=true
fi

log_msg "$LOGFILE" "state proxy_enabled=$PROXY_ENABLED transproxy_enabled=$TRANSPROXY_ENABLED routing_enabled=$ROUTING_ENABLED has_active_profile=$HAS_ACTIVE_PROFILE active_profile=${ACTIVE_PROFILE:-none}"

if [ "$PROXY_ENABLED" != "true" ] || [ "$HAS_ACTIVE_PROFILE" != "true" ]; then
  log_msg "$LOGFILE" "refresh skipped: proxy disabled or no active profile"
  exit 0
fi

sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1
PING_TIMEOUT_SEC=1 sh "$(dirname "$0")/rebuild_service_ipsets.sh" --vpn-only --force --fast --ipv4-only >> "$LOGFILE" 2>&1 || {
  log_msg "$LOGFILE" "refresh failed: rebuild_service_ipsets"
  exit 1
}

if ! pid_is_running "$PIDFILE"; then
  if ! sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1; then
    log_msg "$LOGFILE" "refresh failed: build_proxy_from_active"
    exit 1
  fi
  if ! sh "$(dirname "$0")/start_proxy.sh" >> "$LOGFILE" 2>&1; then
    log_msg "$LOGFILE" "refresh failed: start_proxy"
    exit 1
  fi
fi

if [ "$TRANSPROXY_ENABLED" = "true" ] && [ "$ROUTING_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/apply_transproxy.sh" >> "$LOGFILE" 2>&1 || {
    log_msg "$LOGFILE" "refresh failed: apply_transproxy"
    exit 1
  }
else
  log_msg "$LOGFILE" "refresh note: transproxy not enabled, rules not reapplied"
fi

if [ "$DNS_REDIRECT_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/apply_dns_redirect.sh" >> "$LOGFILE" 2>&1
fi

log_msg "$LOGFILE" "refresh done net=$NET_KEY fp=$NET_FP"
