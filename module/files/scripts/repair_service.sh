#!/system/bin/sh
. "$(dirname "$0")/common.sh"

SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }

MODE_FILE="$CFG_DIR/service_modes/$SERVICE_ID.conf"
[ -f "$MODE_FILE" ] || { echo "service not found: $SERVICE_ID"; exit 1; }

LOGFILE="$LOG_DIR/repair-service.log"
LOCKFILE="$RUNTIME_DIR/repair_service.lock"

clear_stale_lock "$LOCKFILE"
if [ -f "$LOCKFILE" ]; then
  echo "repair already running"
  log_msg "$LOGFILE" "repair skipped service=$SERVICE_ID lock_pid=$(cat "$LOCKFILE" 2>/dev/null)"
  exit 1
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

SERVICE_NAME="$SERVICE_ID"
[ -f "$CFG_DIR/services/$SERVICE_ID.conf" ] && . "$CFG_DIR/services/$SERVICE_ID.conf"

ENABLED="true"
MODE="direct"
. "$MODE_FILE"

log_msg "$LOGFILE" "repair begin service=$SERVICE_ID name=$SERVICE_NAME mode=$MODE enabled=$ENABLED"

sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/rebuild_service_state.sh" >> "$LOGFILE" 2>&1

case "$MODE" in
  vpn)
    sh "$(dirname "$0")/ensure_active_profile.sh" >> "$LOGFILE" 2>&1
    sh "$(dirname "$0")/rebuild_service_ipsets.sh" "$SERVICE_ID" --force >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: rebuild_service_ipsets"
      echo "failed: rebuild ipsets"
      exit 1
    }
    sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: build_proxy_from_active"
      echo "failed: build proxy config"
      exit 1
    }
    sh "$(dirname "$0")/start_proxy.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: start_proxy"
      echo "failed: start proxy"
      exit 1
    }
    sh "$(dirname "$0")/apply_transproxy.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: apply_transproxy"
      echo "failed: apply transproxy"
      exit 1
    }
    sh "$(dirname "$0")/apply_dns_redirect.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: apply_dns_redirect"
      echo "failed: apply dns redirect"
      exit 1
    }
    sh "$(dirname "$0")/apply_ipv6_block.sh" >> "$LOGFILE" 2>&1
    ;;
  zapret)
    sh "$(dirname "$0")/apply_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: apply_zapret_nfqueue"
      echo "failed: apply zapret nfqueue"
      exit 1
    }
    sh "$(dirname "$0")/start_zapret.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "repair failed: start_zapret"
      echo "failed: start zapret"
      exit 1
    }
    ;;
  direct)
    sh "$(dirname "$0")/apply_transproxy.sh" >> "$LOGFILE" 2>&1
    ;;
  *)
    echo "unsupported mode: $MODE"
    exit 1
    ;;
esac

log_msg "$LOGFILE" "repair done service=$SERVICE_ID mode=$MODE"
echo ok
