#!/system/bin/sh
. "$(dirname "$0")/common.sh"

STATE="$CFG_DIR/app_state.json"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"
LOGFILE="$LOG_DIR/start_all.log"
LOCKFILE="$RUNTIME_DIR/start_all.lock"

clear_stale_lock "$LOCKFILE"
if [ -f "$LOCKFILE" ]; then
  log_msg "$LOGFILE" "start_all skipped: lock exists pid=$(cat "$LOCKFILE" 2>/dev/null)"
  exit 0
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

log_msg "$LOGFILE" "start_all begin"

if ! wait_for_network_ready 5; then
  log_msg "$LOGFILE" "start_all proceed: network did not fully stabilize before timeout"
fi

sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_ipsets.sh" --vpn-only >> "$LOGFILE" 2>&1

[ -f "$STATE" ] || { log_msg "$LOGFILE" "state file missing"; exit 1; }

ZAPRET_ENABLED="$(json_bool zapret_enabled "$STATE")"
PROXY_ENABLED="$(json_bool proxy_enabled "$STATE")"
TRANSPROXY_ENABLED="$(json_bool transproxy_enabled "$STATE")"
IPV6_BLOCK_ENABLED="$(json_bool ipv6_block_enabled "$STATE")"
DNS_REDIRECT_ENABLED="$(json_bool dns_redirect_enabled "$STATE")"

ACTIVE_PROFILE=""
[ -f "$ACTIVE_FILE" ] && ACTIVE_PROFILE="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"
HAS_ACTIVE_PROFILE=false
if [ -n "$ACTIVE_PROFILE" ] && [ -f "$CFG_DIR/profiles/$ACTIVE_PROFILE/meta.conf" ]; then
  HAS_ACTIVE_PROFILE=true
fi

log_msg "$LOGFILE" "zapret_enabled=$ZAPRET_ENABLED proxy_enabled=$PROXY_ENABLED transproxy_enabled=$TRANSPROXY_ENABLED ipv6_block_enabled=$IPV6_BLOCK_ENABLED dns_redirect_enabled=$DNS_REDIRECT_ENABLED has_active_profile=$HAS_ACTIVE_PROFILE active_profile=${ACTIVE_PROFILE:-none}"

if [ "$ZAPRET_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/apply_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/start_zapret.sh" >> "$LOGFILE" 2>&1
else
  sh "$(dirname "$0")/clear_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/stop_zapret.sh" >> "$LOGFILE" 2>&1
  log_msg "$LOGFILE" "zapret disabled"
fi

if [ "$PROXY_ENABLED" = "true" ] && [ "$HAS_ACTIVE_PROFILE" = "true" ]; then
  if sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1; then
    if sh "$(dirname "$0")/start_proxy.sh" >> "$LOGFILE" 2>&1; then
      if [ "$TRANSPROXY_ENABLED" = "true" ]; then
        sh "$(dirname "$0")/apply_transproxy.sh" >> "$LOGFILE" 2>&1
      else
        sh "$(dirname "$0")/clear_transproxy.sh" >> "$LOGFILE" 2>&1
        log_msg "$LOGFILE" "transproxy disabled"
      fi

      if [ "$DNS_REDIRECT_ENABLED" = "true" ]; then
        sh "$(dirname "$0")/apply_dns_redirect.sh" >> "$LOGFILE" 2>&1
      else
        sh "$(dirname "$0")/clear_dns_redirect.sh" >> "$LOGFILE" 2>&1
        log_msg "$LOGFILE" "dns redirect disabled"
      fi

      # После первого старта прокси/CDN-домены могут быстро дообогатиться
      # дополнительными IPv4. Сразу выполняем быстрый reconcile-проход,
      # чтобы не ждать network watcher и чтобы кнопка "Включить" доводила
      # систему до того же состояния, что раньше достигалось чуть позже.
      if [ "$TRANSPROXY_ENABLED" = "true" ] || [ "$DNS_REDIRECT_ENABLED" = "true" ]; then
        if PING_TIMEOUT_SEC=1 sh "$(dirname "$0")/refresh_on_network_change.sh" >> "$LOGFILE" 2>&1; then
          log_msg "$LOGFILE" "startup refresh reconcile done"
        else
          log_msg "$LOGFILE" "startup refresh reconcile failed"
        fi
      fi
    else
      sh "$(dirname "$0")/clear_transproxy.sh" >> "$LOGFILE" 2>&1
      sh "$(dirname "$0")/clear_dns_redirect.sh" >> "$LOGFILE" 2>&1
      log_msg "$LOGFILE" "proxy start failed"
    fi
  else
    sh "$(dirname "$0")/stop_proxy.sh" >> "$LOGFILE" 2>&1
    sh "$(dirname "$0")/clear_transproxy.sh" >> "$LOGFILE" 2>&1
    sh "$(dirname "$0")/clear_dns_redirect.sh" >> "$LOGFILE" 2>&1
    log_msg "$LOGFILE" "build_proxy_from_active failed"
  fi
else
  sh "$(dirname "$0")/stop_proxy.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/clear_transproxy.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/clear_dns_redirect.sh" >> "$LOGFILE" 2>&1
  [ "$PROXY_ENABLED" = "true" ] && log_msg "$LOGFILE" "proxy requested but no active profile" || log_msg "$LOGFILE" "proxy disabled"
fi

if [ "$IPV6_BLOCK_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/apply_ipv6_block.sh" >> "$LOGFILE" 2>&1
else
  sh "$(dirname "$0")/clear_ipv6_block.sh" >> "$LOGFILE" 2>&1
  log_msg "$LOGFILE" "ipv6 block disabled"
fi

WATCH_SCRIPT="$(dirname "$0")/network_watch.sh"
WATCH_PIDFILE="$PID_DIR/network_watch.pid"
if [ -f "$WATCH_PIDFILE" ]; then
  OLD_WATCH_PID="$(cat "$WATCH_PIDFILE" 2>/dev/null)"
  if [ -n "$OLD_WATCH_PID" ] && kill -0 "$OLD_WATCH_PID" 2>/dev/null; then
    kill "$OLD_WATCH_PID" 2>/dev/null
    sleep 1
    kill -9 "$OLD_WATCH_PID" 2>/dev/null
    log_msg "$LOGFILE" "network watcher restarted old_pid=$OLD_WATCH_PID"
  fi
  rm -f "$WATCH_PIDFILE"
fi
if [ -f "$WATCH_SCRIPT" ]; then
	nohup sh "$WATCH_SCRIPT" >> "$LOGFILE" 2>&1 &
	NEW_WATCH_PID=$!
	log_msg "$LOGFILE" "network watcher spawn requested pid=$NEW_WATCH_PID"
fi

log_msg "$LOGFILE" "start_all done"
