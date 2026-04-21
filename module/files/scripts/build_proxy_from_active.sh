#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/build_proxy.log"
ACTIVE_PROFILE_FILE="$CFG_DIR/active_profile.txt"
PROFILES_DIR="$CFG_DIR/profiles"
APP_STATE_FILE="$CFG_DIR/app_state.json"
PROXY_DOMAINS_FILE="$CFG_DIR/proxy_domains.txt"
DIRECT_DOMAINS_FILE="$CFG_DIR/direct_domains.txt"
OUT_CONF="$CFG_DIR/proxy.json"
DNS_REMOTE_IP="${DNS_REMOTE_IP:-1.1.1.1}"
DNS_REMOTE_PORT="${DNS_REMOTE_PORT:-53}"

log_msg "$LOGFILE" "build_proxy_from_active begin"

escape_json() {
  # Экранирование для JSON-строк
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/\r//g' \
    -e ':a;N;$!ba;s/\n/\\n/g'
}

json_bool_from_state() {
  # Достаёт true/false из app_state.json
  # Используем только true/false без запятых
  key="$1"
  if [ -f "$APP_STATE_FILE" ]; then
    val="$(grep -m1 "\"$key\"" "$APP_STATE_FILE" | sed -E 's/.*: *([^, ]+).*/\1/' | tr -d '\r')"
    case "$val" in
      true|false) printf '%s' "$val"; return 0 ;;
    esac
  fi
  printf 'false'
}

read_first_line_trim() {
  file="$1"
  [ -f "$file" ] || return 1
  head -n 1 "$file" | tr -d '\r'
}

build_domain_json_array() {
  file="$1"
  if [ ! -f "$file" ]; then
    printf '[]'
    return 0
  fi

  tmp_norm="$OUT_CONF.route_domains.tmp"
  : > "$tmp_norm"

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in
      \#*) continue ;;
      suffix:*)
        line="${line#suffix:}"
        ;;
    esac
    [ -n "$line" ] || continue
    printf '%s\n' "$line" >> "$tmp_norm"
  done < "$file"

  if [ ! -s "$tmp_norm" ]; then
    rm -f "$tmp_norm"
    printf '[]'
    return 0
  fi

  sort -u "$tmp_norm" -o "$tmp_norm"

  first=1
  printf '['
  while IFS= read -r line || [ -n "$line" ]; do
    esc="$(escape_json "$line")"
    if [ "$first" = "1" ]; then
      printf '"%s"' "$esc"
      first=0
    else
      printf ', "%s"' "$esc"
    fi
  done < "$tmp_norm"
  printf ']'
  rm -f "$tmp_norm"
}

append_route_rule_if_needed() {
  # $1 = domains_file
  # $2 = outbound_tag
  domains_file="$1"
  outbound_tag="$2"

  [ -f "$domains_file" ] || return 0
  if ! grep -q '[^[:space:]]' "$domains_file"; then
    return 0
  fi

  domains_json="$(build_domain_json_array "$domains_file")"

  if [ "$ROUTE_RULES_WRITTEN" = "1" ]; then
    printf ',\n' >> "$OUT_CONF"
  fi

  cat >> "$OUT_CONF" <<EOF
      {
        "domain_suffix": $domains_json,
        "outbound": "$outbound_tag"
      }
EOF
  ROUTE_RULES_WRITTEN=1
}

ACTIVE_PROFILE_ID="$(read_first_line_trim "$ACTIVE_PROFILE_FILE")"

if [ -z "$ACTIVE_PROFILE_ID" ]; then
  log_msg "$LOGFILE" "active profile is empty"
  exit 1
fi

PROFILE_DIR="$PROFILES_DIR/$ACTIVE_PROFILE_ID"
META_FILE="$PROFILE_DIR/meta.conf"

if [ ! -d "$PROFILE_DIR" ]; then
  log_msg "$LOGFILE" "profile directory missing: $PROFILE_DIR"
  exit 1
fi

if [ ! -f "$META_FILE" ]; then
  log_msg "$LOGFILE" "meta.conf missing: $META_FILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$META_FILE"

PROFILE_NAME="${PROFILE_NAME:-$ACTIVE_PROFILE_ID}"
GROUP_ID="${GROUP_ID:-default}"
SERVER="${SERVER:-}"
PORT="${PORT:-443}"
UUID="${UUID:-}"
FLOW="${FLOW:-}"
SECURITY="${SECURITY:-tls}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
FINGERPRINT="${FINGERPRINT:-chrome}"
SNI="${SNI:-}"
SHORT_ID="${SHORT_ID:-}"

ROUTING_ENABLED="$(json_bool_from_state routing_enabled)"
ROUTING_MODE_RAW="$(grep -m1 '"routing_mode"' "$APP_STATE_FILE" 2>/dev/null | sed -E 's/.*: *"([^"]+)".*/\1/' | tr -d '\r')"
[ -n "$ROUTING_MODE_RAW" ] || ROUTING_MODE_RAW="proxy_list"

if [ -z "$SERVER" ] || [ -z "$UUID" ] || [ -z "$SNI" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
  log_msg "$LOGFILE" "profile parse failed: profile=$ACTIVE_PROFILE_ID server='$SERVER' port='$PORT' uuid='$UUID' sni='$SNI' fp='$FINGERPRINT' pbk='$PUBLIC_KEY' sid='$SHORT_ID'"
  exit 1
fi

ESC_PROFILE_ID="$(escape_json "$ACTIVE_PROFILE_ID")"
ESC_PROFILE_NAME="$(escape_json "$PROFILE_NAME")"
ESC_GROUP_ID="$(escape_json "$GROUP_ID")"
ESC_SERVER="$(escape_json "$SERVER")"
ESC_UUID="$(escape_json "$UUID")"
ESC_FLOW="$(escape_json "$FLOW")"
ESC_SNI="$(escape_json "$SNI")"
ESC_FP="$(escape_json "$FINGERPRINT")"
ESC_PBK="$(escape_json "$PUBLIC_KEY")"
ESC_SID="$(escape_json "$SHORT_ID")"

# В sing-box через REDIRECT попадает только заранее отобранный iptables-трафик
# (например Facebook VPN-сервисы). Поэтому default внутри sing-box должен быть
# именно vless-out, иначе unmatched-соединения уйдут обратно напрямую.
FINAL_OUTBOUND="vless-out"

cat > "$OUT_CONF" <<EOF
{
  "log": {
    "level": "warning"
  },
  "inbounds": [
    {
      "type": "redirect",
      "tag": "redir-in",
      "listen": "127.0.0.1",
      "listen_port": 12345
    },
    {
      "type": "direct",
      "tag": "dns-udp-in",
      "listen": "127.0.0.1",
      "listen_port": 1053,
      "network": "udp",
      "override_address": "$DNS_REMOTE_IP",
      "override_port": $DNS_REMOTE_PORT
    },
    {
      "type": "direct",
      "tag": "dns-tcp-in",
      "listen": "127.0.0.1",
      "listen_port": 1053,
      "network": "tcp",
      "override_address": "$DNS_REMOTE_IP",
      "override_port": $DNS_REMOTE_PORT
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "$ESC_SERVER",
      "server_port": $PORT,
      "uuid": "$ESC_UUID",
      "flow": "$ESC_FLOW",
      "tls": {
        "enabled": true,
        "server_name": "$ESC_SNI",
        "insecure": false,
        "utls": {
          "enabled": true,
          "fingerprint": "$ESC_FP"
        },
        "reality": {
          "enabled": true,
          "public_key": "$ESC_PBK",
          "short_id": "$ESC_SID"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "$FINAL_OUTBOUND",
    "rules": [
EOF

ROUTE_RULES_WRITTEN=0

cat >> "$OUT_CONF" <<EOF
      {
        "inbound": ["dns-udp-in", "dns-tcp-in"],
        "outbound": "vless-out"
      }
EOF
ROUTE_RULES_WRITTEN=1

# Правила по доменам полезны как fallback и для диагностик.
# Они не мешают transparent redirect сценарию.
append_route_rule_if_needed "$PROXY_DOMAINS_FILE" "vless-out"
append_route_rule_if_needed "$DIRECT_DOMAINS_FILE" "direct"

cat >> "$OUT_CONF" <<EOF

    ]
  }
}
EOF

log_msg "$LOGFILE" "proxy.json built from $ACTIVE_PROFILE_ID routing_enabled=$ROUTING_ENABLED routing_mode=$ROUTING_MODE_RAW final=$FINAL_OUTBOUND dns_via_vless=${DNS_REMOTE_IP}:${DNS_REMOTE_PORT}"
log_msg "$LOGFILE" "build_proxy_from_active done"
exit 0
