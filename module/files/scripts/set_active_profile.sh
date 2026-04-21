#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/set_active_profile.log"
ACTIVE_FILE="$CFG_DIR/active_profile.txt"

PROFILE_ID="$1"
[ -n "$PROFILE_ID" ] || { echo "usage: set_active_profile.sh profile_0001"; exit 1; }

PROFILE_DIR="$CFG_DIR/profiles/$PROFILE_ID"
META_FILE="$PROFILE_DIR/meta.conf"
if [ ! -f "$META_FILE" ]; then
  echo "profile not found"
  log_msg "$LOGFILE" "profile not found: $PROFILE_ID"
  exit 1
fi

echo "$PROFILE_ID" > "$ACTIVE_FILE"
log_msg "$LOGFILE" "active profile set to $PROFILE_ID"
sh "$(dirname "$0")/recompute_app_state.sh" >> "$LOGFILE" 2>&1
sh "$(dirname "$0")/build_proxy_from_active.sh" >> "$LOGFILE" 2>&1 || {
  log_msg "$LOGFILE" "failed: build_proxy_from_active"
  echo "failed: build proxy config"
  exit 1
}

STATE="$CFG_DIR/app_state.json"
PROXY_ENABLED="false"
TRANSPROXY_ENABLED="false"
DNS_REDIRECT_ENABLED="false"
IPV6_BLOCK_ENABLED="false"

if [ -f "$STATE" ]; then
  PROXY_ENABLED="$(json_bool proxy_enabled "$STATE")"
  TRANSPROXY_ENABLED="$(json_bool transproxy_enabled "$STATE")"
  DNS_REDIRECT_ENABLED="$(json_bool dns_redirect_enabled "$STATE")"
  IPV6_BLOCK_ENABLED="$(json_bool ipv6_block_enabled "$STATE")"
fi

if [ "$PROXY_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/stop_proxy.sh" >> "$LOGFILE" 2>&1
  sh "$(dirname "$0")/start_proxy.sh" >> "$LOGFILE" 2>&1 || {
    log_msg "$LOGFILE" "failed: start_proxy"
    echo "failed: start proxy"
    exit 1
  }

  if [ "$TRANSPROXY_ENABLED" = "true" ]; then
    if sh "$(dirname "$0")/refresh_transproxy_server_exclusion.sh" >> "$LOGFILE" 2>&1; then
      log_msg "$LOGFILE" "transproxy server exclusion refreshed"
    else
      log_msg "$LOGFILE" "refresh_transproxy_server_exclusion failed, falling back to apply_transproxy"
      sh "$(dirname "$0")/apply_transproxy.sh" >> "$LOGFILE" 2>&1 || {
        log_msg "$LOGFILE" "failed: apply_transproxy"
        echo "failed: apply transproxy"
        exit 1
      }
    fi
  fi

  if [ "$DNS_REDIRECT_ENABLED" = "true" ]; then
    sh "$(dirname "$0")/apply_dns_redirect.sh" >> "$LOGFILE" 2>&1 || {
      log_msg "$LOGFILE" "failed: apply_dns_redirect"
      echo "failed: apply dns redirect"
      exit 1
    }
  fi
fi

if [ "$IPV6_BLOCK_ENABLED" = "true" ]; then
  sh "$(dirname "$0")/apply_ipv6_block.sh" >> "$LOGFILE" 2>&1
fi

log_msg "$LOGFILE" "active profile applied profile=$PROFILE_ID proxy_enabled=$PROXY_ENABLED transproxy_enabled=$TRANSPROXY_ENABLED dns_redirect_enabled=$DNS_REDIRECT_ENABLED"
echo ok
