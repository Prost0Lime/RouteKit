#!/system/bin/sh
. "$(dirname "$0")/common.sh"

TARGET_SERVICE="$1"
FOUND=0

print_value() {
  local key="$1"
  local value="$2"
  printf '%s=%s\n' "$key" "$(printf '%s' "$value" | tr '\n' ' ' | sed 's/\r//g')"
}

for mode_file in $(service_mode_files); do
  [ -f "$mode_file" ] || continue

  SERVICE_ID=""
  ENABLED="true"
  MODE="direct"
  TCP_STRATEGY=""
  UDP_STRATEGY=""
  STUN_STRATEGY=""
  TCP_HOSTLIST=""
  . "$mode_file"

  [ -n "$TARGET_SERVICE" ] && [ "$SERVICE_ID" != "$TARGET_SERVICE" ] && continue
  service_is_custom "$SERVICE_ID" || continue

  SERVICE_NAME="$SERVICE_ID"
  CUSTOM_SERVICE="false"
  . "$CFG_DIR/services/$SERVICE_ID.conf"

  FOUND=1
  echo "BEGIN_SERVICE"
  print_value "service_id" "$SERVICE_ID"
  print_value "service_name" "$SERVICE_NAME"
  print_value "mode" "$MODE"
  print_value "enabled" "$ENABLED"
  print_value "tcp_strategy" "$TCP_STRATEGY"
  print_value "udp_strategy" "$UDP_STRATEGY"
  print_value "stun_strategy" "$STUN_STRATEGY"

  hostlist_path="$(expand_cfg_path "$TCP_HOSTLIST")"
  if [ -f "$hostlist_path" ]; then
    grep -v '^[[:space:]]*$' "$hostlist_path" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | while IFS= read -r domain || [ -n "$domain" ]; do
      printf 'domain=%s\n' "$domain"
    done
  fi
  echo "END_SERVICE"
done

[ "$FOUND" = "1" ] || {
  echo "no custom services"
  exit 1
}

