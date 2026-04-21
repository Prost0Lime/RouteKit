#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/rebuild_service_ipsets.log"
PING_TIMEOUT_SEC="${PING_TIMEOUT_SEC:-1}"
DNS_HELPER_BIN="$(dns_helper_bin)"

TARGET_SERVICE=""
FORCE_REBUILD="false"
VPN_ONLY="false"
FAST_MODE="false"
IPV4_ONLY="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --force|force=true|force=1)
      FORCE_REBUILD="true"
      ;;
    --vpn-only|vpn_only=true|vpn-only=true)
      VPN_ONLY="true"
      ;;
    --fast|fast=true|fast=1)
      FAST_MODE="true"
      ;;
    --ipv4-only|ipv4_only=true|ipv4-only=true)
      IPV4_ONLY="true"
      ;;
    *)
      TARGET_SERVICE="$1"
      ;;
  esac
  shift
done

mkdir -p \
  "$RUNTIME_DIR/ipsets_auto" \
  "$RUNTIME_DIR/ipsets_auto_v6" \
  "$RUNTIME_DIR/unresolved" \
  "$RUNTIME_DIR/network_cache" \
  "$RUNTIME_DIR/domain_cache/suffix"

CURRENT_NET_FINGERPRINT="$(network_fingerprint)"
CURRENT_NET_KEY="$(printf '%s' "$CURRENT_NET_FINGERPRINT" | cksum | awk '{print $1}')"

if [ "$FAST_MODE" = "true" ]; then
  RESOLVE_RETRIES=1
else
  RESOLVE_RETRIES=3
fi

log_msg "$LOGFILE" "rebuild_service_ipsets begin target=${TARGET_SERVICE:-all} force=$FORCE_REBUILD vpn_only=$VPN_ONLY fast=$FAST_MODE ipv4_only=$IPV4_ONLY net=$CURRENT_NET_KEY"

normalize_domain() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//'
}

normalize_domain_entry() {
  local value=""
  value="$(printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$value" in
    \#*|'') printf '%s' "$value" ;;
    suffix:*)
      printf 'suffix:%s' "$(normalize_domain "${value#suffix:}")"
      ;;
    \*.*)
      printf 'suffix:%s' "$(normalize_domain "${value#*.}")"
      ;;
    *)
      printf '%s' "$(normalize_domain "$value")"
      ;;
  esac
}

is_suffix_rule() {
  case "$1" in
    suffix:*) return 0 ;;
    *) return 1 ;;
  esac
}

suffix_domain_from_rule() {
  printf '%s' "${1#suffix:}"
}

domain_suffixes_for_host() {
  local host="$1"
  local rest="$host"
  local dots=0

  dots="$(printf '%s' "$host" | tr -cd '.' | wc -c | tr -d ' ')"
  [ "${dots:-0}" -ge 2 ] || return 0

  while [ "$dots" -ge 2 ]; do
    rest="${rest#*.}"
    printf '%s\n' "$rest"
    dots=$((dots - 1))
  done
}

suffix_cache_v4_file_for() {
  printf '%s/domain_cache/suffix/%s.v4.txt' "$RUNTIME_DIR" "$1"
}

suffix_cache_v6_file_for() {
  printf '%s/domain_cache/suffix/%s.v6.txt' "$RUNTIME_DIR" "$1"
}

append_suffix_cache_ips() {
  local suffix="$1"
  local tmp_v4="$2"
  local tmp_v6="$3"
  local resolved_domains_out="$4"
  local all_domains_out="$5"
  local cache_v4=""
  local cache_v6=""
  local count_v4=0
  local count_v6=0

  cache_v4="$(suffix_cache_v4_file_for "$suffix")"
  cache_v6="$(suffix_cache_v6_file_for "$suffix")"

  printf 'suffix:%s\n' "$suffix" >> "$all_domains_out"
  printf 'suffix:%s\n' "$suffix" >> "$resolved_domains_out"

  if [ -f "$cache_v4" ] && [ -s "$cache_v4" ]; then
    cat "$cache_v4" >> "$tmp_v4"
    count_v4="$(count_non_comment_lines "$cache_v4")"
  fi

  if [ "$IPV4_ONLY" != "true" ] && [ -f "$cache_v6" ] && [ -s "$cache_v6" ]; then
    cat "$cache_v6" >> "$tmp_v6"
    count_v6="$(count_non_comment_lines "$cache_v6")"
  fi

  if [ "$count_v4" -gt 0 ] || [ "$count_v6" -gt 0 ]; then
    log_msg "$LOGFILE" "suffix_cache_hit suffix=$suffix cached_ipv4_count=$count_v4 cached_ipv6_count=$count_v6"
  else
    log_msg "$LOGFILE" "suffix_cache_empty suffix=$suffix"
  fi
}

update_suffix_cache_with_ips() {
  local domain="$1"
  local resolved_v4="$2"
  local resolved_v6="$3"
  local suffix=""
  local cache_v4=""
  local cache_v6=""

  while IFS= read -r suffix || [ -n "$suffix" ]; do
    [ -n "$suffix" ] || continue

    cache_v4="$(suffix_cache_v4_file_for "$suffix")"
    cache_v6="$(suffix_cache_v6_file_for "$suffix")"

    if [ -n "$resolved_v4" ]; then
      printf '%s\n' "$resolved_v4" >> "$cache_v4"
      sort -u "$cache_v4" -o "$cache_v4"
    fi

    if [ -n "$resolved_v6" ]; then
      printf '%s\n' "$resolved_v6" >> "$cache_v6"
      sort -u "$cache_v6" -o "$cache_v6"
    fi
  done <<EOF
$(domain_suffixes_for_host "$domain")
EOF
}

command_works() {
  "$@" >/dev/null 2>&1
}

extract_ipv4_from_nslookup() {
  awk '
    /^Name:/ { capture=1; next }
    capture && /^Address([[:space:]][0-9]+)?:/ {
      value=$NF
      if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print value
    }
  '
}

extract_ipv6_from_nslookup() {
  awk '
    /^Name:/ { capture=1; next }
    capture && /^Address([[:space:]][0-9]+)?:/ {
      value=$NF
      if (value ~ /:/ && value !~ /^fe80:/ && value != "::1") print value
    }
  '
}

dns_helper_servers() {
  local tmp="$RUNTIME_DIR/domain_cache/.dns_servers_$$.tmp"
  : > "$tmp"

  if command -v getprop >/dev/null 2>&1; then
    for key in net.dns1 net.dns2 net.dns3 net.dns4; do
      server="$(getprop "$key" 2>/dev/null | tr -d '\r\n')"
      case "$server" in
        ''|0.0.0.0|::|::1) continue ;;
      esac
      printf '%s\n' "$server" >> "$tmp"
    done
  fi

  printf '%s\n' 1.1.1.1 >> "$tmp"
  printf '%s\n' 8.8.8.8 >> "$tmp"

  sort -u "$tmp" | paste -sd, -
  rm -f "$tmp"
}

resolve_with_dns_helper() {
  local qtype="$1"
  local domain="$2"
  local servers=""
  local repeat="$RESOLVE_RETRIES"
  local interval_ms=250
  local timeout_ms=1200

  [ -x "$DNS_HELPER_BIN" ] || return 1

  if [ "$FAST_MODE" = "true" ]; then
    interval_ms=0
    timeout_ms=900
  fi

  servers="$(dns_helper_servers)"

  "$DNS_HELPER_BIN" \
    --type "$qtype" \
    --repeat "$repeat" \
    --interval-ms "$interval_ms" \
    --timeout-ms "$timeout_ms" \
    --servers "$servers" \
    "$domain" 2>/dev/null
}

resolve_domain_ipv4() {
  local domain="$1"
  local out=""
  local current=""
  local attempt=1
  local acc_file="$RUNTIME_DIR/domain_cache/.resolve_ipv4_${domain//[^a-zA-Z0-9]/_}_$$.tmp"

  if [ -x "$DNS_HELPER_BIN" ]; then
    out="$(resolve_with_dns_helper A "$domain")"
    [ -n "$out" ] && {
      printf '%s\n' "$out"
      return 0
    }
  fi

  : > "$acc_file"

  while [ "$attempt" -le "$RESOLVE_RETRIES" ]; do
    current=""

    if command -v getent >/dev/null 2>&1; then
      current="$(
        {
          getent ahostsv4 "$domain" 2>/dev/null
          getent ahosts "$domain" 2>/dev/null
        } | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
      )"
    fi

    if [ -z "$current" ] && command -v nslookup >/dev/null 2>&1; then
      current="$(
        nslookup "$domain" 2>/dev/null | extract_ipv4_from_nslookup | sort -u
      )"
    fi

    if [ -z "$current" ] && command -v ping >/dev/null 2>&1; then
      if command_works ping -4 -c 1 "$domain"; then
        current="$(
          ping -4 -c 1 -W "$PING_TIMEOUT_SEC" "$domain" 2>/dev/null |
            awk -F'[()]' 'NR==1 {print $2}' |
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
            sort -u
        )"
      else
        current="$(
          ping -c 1 -W "$PING_TIMEOUT_SEC" "$domain" 2>/dev/null |
            awk -F'[()]' 'NR==1 {print $2}' |
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
            sort -u
        )"
      fi
    fi

    if [ -n "$current" ]; then
      printf '%s\n' "$current" >> "$acc_file"
    fi

    attempt=$((attempt + 1))
    [ "$attempt" -le "$RESOLVE_RETRIES" ] && sleep 1
  done

  if [ -s "$acc_file" ]; then
    out="$(sort -u "$acc_file")"
  fi

  rm -f "$acc_file"
  [ -n "$out" ] && printf '%s\n' "$out"
}

resolve_domain_ipv6() {
  local domain="$1"
  local out=""
  local current=""
  local attempt=1
  local acc_file="$RUNTIME_DIR/domain_cache/.resolve_ipv6_${domain//[^a-zA-Z0-9]/_}_$$.tmp"

  [ "$IPV4_ONLY" = "true" ] && return 0

  if [ -x "$DNS_HELPER_BIN" ]; then
    out="$(resolve_with_dns_helper AAAA "$domain")"
    [ -n "$out" ] && {
      printf '%s\n' "$out"
      return 0
    }
  fi

  : > "$acc_file"

  while [ "$attempt" -le "$RESOLVE_RETRIES" ]; do
    current=""

    if command -v getent >/dev/null 2>&1; then
      current="$(
        {
          getent ahostsv6 "$domain" 2>/dev/null
          getent ahosts "$domain" 2>/dev/null
        } | awk '{print $1}' | grep ':' | grep -v '^fe80:' | grep -v '^::1$' | sort -u
      )"
    fi

    if [ -z "$current" ] && command -v nslookup >/dev/null 2>&1; then
      current="$(
        nslookup -query=AAAA "$domain" 2>/dev/null | extract_ipv6_from_nslookup | sort -u
      )"
    fi

    if [ -z "$current" ]; then
      if command -v ping >/dev/null 2>&1 && command_works ping -6 -c 1 "$domain"; then
        current="$(
          ping -6 -c 1 -W "$PING_TIMEOUT_SEC" "$domain" 2>/dev/null |
            sed -n '1s/.*(\([0-9A-Fa-f:]*\)).*/\1/p' |
            grep ':' |
            grep -v '^fe80:' |
            grep -v '^::1$' |
            sort -u
        )"
      elif command -v ping6 >/dev/null 2>&1; then
        current="$(
          ping6 -c 1 -W "$PING_TIMEOUT_SEC" "$domain" 2>/dev/null |
            sed -n '1s/.*(\([0-9A-Fa-f:]*\)).*/\1/p' |
            grep ':' |
            grep -v '^fe80:' |
            grep -v '^::1$' |
            sort -u
        )"
      fi
    fi

    if [ -n "$current" ]; then
      printf '%s\n' "$current" >> "$acc_file"
    fi

    attempt=$((attempt + 1))
    [ "$attempt" -le "$RESOLVE_RETRIES" ] && sleep 1
  done

  if [ -s "$acc_file" ]; then
    out="$(sort -u "$acc_file")"
  fi

  rm -f "$acc_file"
  [ -n "$out" ] && printf '%s\n' "$out"
}

append_hostlist_ips() {
  local hostlist="$1"
  local tmp_v4="$2"
  local tmp_v6="$3"
  local unresolved_out="$4"
  local resolved_domains_out="$5"
  local all_domains_out="$6"
  local line=""
  local domain=""
  local resolved_v4=""
  local resolved_v6=""

  [ -f "$hostlist" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(normalize_domain_entry "$line")"
    [ -n "$line" ] || continue
    case "$line" in \#*) continue ;; esac
    if is_suffix_rule "$line"; then
      append_suffix_cache_ips "$(suffix_domain_from_rule "$line")" "$tmp_v4" "$tmp_v6" "$resolved_domains_out" "$all_domains_out"
      continue
    fi

    domain="$(normalize_domain "$line")"
    [ -n "$domain" ] || continue

    printf '%s\n' "$domain" >> "$all_domains_out"

    resolved_v4="$(resolve_domain_ipv4 "$domain")"
    resolved_v6="$(resolve_domain_ipv6 "$domain")"

    if [ -n "$resolved_v4" ]; then
      printf '%s\n' "$resolved_v4" >> "$tmp_v4"
      printf '%s\n' "$domain" >> "$resolved_domains_out"
      log_msg "$LOGFILE" "resolved_ipv4 domain=$domain ips=$(printf '%s' "$resolved_v4" | tr '\n' ',' | sed 's/,$//')"
    fi

    if [ -n "$resolved_v6" ]; then
      printf '%s\n' "$resolved_v6" >> "$tmp_v6"
      printf '%s\n' "$domain" >> "$resolved_domains_out"
      log_msg "$LOGFILE" "resolved_ipv6 domain=$domain ips=$(printf '%s' "$resolved_v6" | tr '\n' ',' | sed 's/,$//')"
    fi

    if [ -n "$resolved_v4" ] || [ -n "$resolved_v6" ]; then
      update_suffix_cache_with_ips "$domain" "$resolved_v4" "$resolved_v6"
    fi

    if [ -z "$resolved_v4" ] && [ -z "$resolved_v6" ]; then
      printf '%s\n' "$domain" >> "$unresolved_out"
      log_msg "$LOGFILE" "unresolved domain=$domain"
    fi
  done < "$hostlist"
}

write_current_snapshot() {
  local tmp_v4="$1"
  local tmp_v6="$2"
  local unresolved_file="$3"
  local cache_v4="$4"
  local cache_v6="$5"
  local cache_unresolved="$6"
  local cache_meta="$7"
  local current_sig="$8"
  local resolved_domains_file="$9"
  local all_domains_file="${10}"
  local cache_resolved_domains="${11}"
  local cache_all_domains="${12}"

  if [ -s "$tmp_v4" ]; then
    sort -u "$tmp_v4" | sed 's#$#/32#' > "$cache_v4"
  else
    : > "$cache_v4"
  fi

  if [ -s "$tmp_v6" ]; then
    sort -u "$tmp_v6" | sed 's#$#/128#' > "$cache_v6"
  else
    : > "$cache_v6"
  fi

  if [ -s "$unresolved_file" ]; then
    sort -u "$unresolved_file" > "$cache_unresolved"
  else
    : > "$cache_unresolved"
  fi

  if [ -s "$resolved_domains_file" ]; then
    sort -u "$resolved_domains_file" > "$cache_resolved_domains"
  else
    : > "$cache_resolved_domains"
  fi

  if [ -s "$all_domains_file" ]; then
    sort -u "$all_domains_file" > "$cache_all_domains"
  else
    : > "$cache_all_domains"
  fi

  printf 'signature=%s\n' "$current_sig" > "$cache_meta"
}

append_existing_auto_ips() {
  local source_file="$1"
  local target_tmp="$2"

  [ -f "$source_file" ] || return 0
  grep -v '^[[:space:]]*$' "$source_file" 2>/dev/null |
    grep -v '^[[:space:]]*#' 2>/dev/null |
    sed 's#/32$##; s#/128$##' >> "$target_tmp"
}

aggregate_service_cache() {
  local service_id="$1"
  local cache_dir="$2"
  local sig="$3"
  local out_v4="$4"
  local out_v6="$5"
  local out_unresolved="$6"
  local current_unresolved="$7"

  local tmp_all_v4="$out_v4.aggregate.tmp"
  local tmp_all_v6="$out_v6.aggregate.tmp"
  local tmp_all_unresolved="$out_unresolved.aggregate.tmp"
  local tmp_all_domains="$out_unresolved.aggregate.domains.tmp"
  local tmp_resolved_domains="$out_unresolved.aggregate.resolved.tmp"

  : > "$tmp_all_v4"
  : > "$tmp_all_v6"
  : > "$tmp_all_unresolved"
  : > "$tmp_all_domains"
  : > "$tmp_resolved_domains"

  for meta in "$cache_dir"/*.meta; do
    [ -f "$meta" ] || continue

    local cache_sig=""
    cache_sig="$(grep '^signature=' "$meta" 2>/dev/null | head -n1 | cut -d= -f2)"
    [ "$cache_sig" = "$sig" ] || continue

    local base="${meta%.meta}"

    [ -f "${base}.v4.txt" ] && cat "${base}.v4.txt" >> "$tmp_all_v4"
    [ -f "${base}.v6.txt" ] && cat "${base}.v6.txt" >> "$tmp_all_v6"
    [ -f "${base}.unresolved.txt" ] && cat "${base}.unresolved.txt" >> "$tmp_all_unresolved"
    [ -f "${base}.domains.txt" ] && cat "${base}.domains.txt" >> "$tmp_all_domains"
    [ -f "${base}.resolved_domains.txt" ] && cat "${base}.resolved_domains.txt" >> "$tmp_resolved_domains"
  done

  if [ -s "$tmp_all_v4" ]; then
    sort -u "$tmp_all_v4" > "$out_v4"
  else
    : > "$out_v4"
  fi

  if [ -s "$tmp_all_v6" ]; then
    sort -u "$tmp_all_v6" > "$out_v6"
  else
    : > "$out_v6"
  fi

  if [ -s "$tmp_all_domains" ]; then
    sort -u "$tmp_all_domains" > "${tmp_all_domains}.sorted"
  else
    : > "${tmp_all_domains}.sorted"
  fi

  if [ -s "$tmp_resolved_domains" ]; then
    sort -u "$tmp_resolved_domains" > "${tmp_resolved_domains}.sorted"
  else
    : > "${tmp_resolved_domains}.sorted"
  fi

  if [ -s "${tmp_all_domains}.sorted" ]; then
    grep -F -x -v -f "${tmp_resolved_domains}.sorted" "${tmp_all_domains}.sorted" > "$out_unresolved" 2>/dev/null || : > "$out_unresolved"
  elif [ -f "$current_unresolved" ] && [ -s "$current_unresolved" ]; then
    sort -u "$current_unresolved" > "$out_unresolved"
  else
    : > "$out_unresolved"
  fi

  rm -f \
    "$tmp_all_v4" "$tmp_all_v6" "$tmp_all_unresolved" \
    "$tmp_all_domains" "$tmp_resolved_domains" \
    "${tmp_all_domains}.sorted" "${tmp_resolved_domains}.sorted"
}

for f in $(service_mode_files); do
  [ -f "$f" ] || continue

  SERVICE_ID=""
  ENABLED="true"
  MODE="direct"
  TCP_HOSTLIST=""
  UDP_HOSTLIST=""
  STUN_HOSTLIST=""

  . "$f"

  if [ -n "$TARGET_SERVICE" ] && [ "$SERVICE_ID" != "$TARGET_SERVICE" ]; then
    continue
  fi

  auto_v4_file="$(service_auto_ipset_v4_file_for "$SERVICE_ID")"
  auto_v6_file="$(service_auto_ipset_v6_file_for "$SERVICE_ID")"
  unresolved_file="$(service_unresolved_file_for "$SERVICE_ID")"
  resolved_domains_file="$unresolved_file.resolved_domains.tmp"
  all_domains_file="$unresolved_file.all_domains.tmp"

  tmp_v4="$auto_v4_file.tmp"
  tmp_v6="$auto_v6_file.tmp"

  : > "$tmp_v4"
  : > "$tmp_v6"
  : > "$unresolved_file"
  : > "$resolved_domains_file"
  : > "$all_domains_file"

  cache_dir="$RUNTIME_DIR/network_cache/$SERVICE_ID"
  mkdir -p "$cache_dir"

  cache_base="$cache_dir/$CURRENT_NET_KEY"
  cache_v4="${cache_base}.v4.txt"
  cache_v6="${cache_base}.v6.txt"
  cache_unresolved="${cache_base}.unresolved.txt"
  cache_meta="${cache_base}.meta"
  cache_resolved_domains="${cache_base}.resolved_domains.txt"
  cache_all_domains="${cache_base}.domains.txt"

  current_sig="$(
    {
      [ -n "$TCP_HOSTLIST" ] && [ -f "$(expand_cfg_path "$TCP_HOSTLIST")" ] && cat "$(expand_cfg_path "$TCP_HOSTLIST")"
      [ -n "$UDP_HOSTLIST" ] && [ -f "$(expand_cfg_path "$UDP_HOSTLIST")" ] && cat "$(expand_cfg_path "$UDP_HOSTLIST")"
      [ -n "$STUN_HOSTLIST" ] && [ -f "$(expand_cfg_path "$STUN_HOSTLIST")" ] && cat "$(expand_cfg_path "$STUN_HOSTLIST")"
      printf 'mode=%s\nenabled=%s\n' "$MODE" "$ENABLED"
    } | cksum | awk '{print $1}'
  )"

  cached_sig=""
  if [ -f "$cache_meta" ]; then
    cached_sig="$(grep '^signature=' "$cache_meta" 2>/dev/null | head -n1 | cut -d= -f2)"
  fi

  if [ "$ENABLED" != "true" ] || [ "$MODE" != "vpn" ]; then
    if [ "$VPN_ONLY" = "true" ]; then
      rm -f "$tmp_v4" "$tmp_v6" "$resolved_domains_file" "$all_domains_file"
      continue
    fi

    : > "$auto_v4_file"
    : > "$auto_v6_file"
    : > "$unresolved_file"

    log_msg "$LOGFILE" "service=$SERVICE_ID mode=$MODE enabled=$ENABLED auto_ipv4_count=0 auto_ipv6_count=0 unresolved_count=0 file_v4=$auto_v4_file file_v6=$auto_v6_file"
    rm -f "$tmp_v4" "$tmp_v6" "$resolved_domains_file" "$all_domains_file"
    continue
  fi

  if [ "$FORCE_REBUILD" != "true" ] && [ -f "$cache_v4" ] && [ -f "$cache_v6" ] && [ -f "$cache_unresolved" ] && [ "$cached_sig" = "$current_sig" ]; then
    aggregate_service_cache "$SERVICE_ID" "$cache_dir" "$current_sig" "$auto_v4_file" "$auto_v6_file" "$unresolved_file" "$cache_unresolved"

    count_v4="$(count_non_comment_lines "$auto_v4_file")"
    count_v6="$(count_non_comment_lines "$auto_v6_file")"
    unresolved_count="$(count_non_comment_lines "$unresolved_file")"

    log_msg "$LOGFILE" "cache_hit service=$SERVICE_ID net=$CURRENT_NET_KEY auto_ipv4_count=$count_v4 auto_ipv6_count=$count_v6 unresolved_count=$unresolved_count"

    rm -f "$tmp_v4" "$tmp_v6" "$resolved_domains_file" "$all_domains_file"
    continue
  fi

  [ -n "$TCP_HOSTLIST" ] && append_hostlist_ips "$(expand_cfg_path "$TCP_HOSTLIST")" "$tmp_v4" "$tmp_v6" "$unresolved_file" "$resolved_domains_file" "$all_domains_file"
  [ -n "$UDP_HOSTLIST" ] && append_hostlist_ips "$(expand_cfg_path "$UDP_HOSTLIST")" "$tmp_v4" "$tmp_v6" "$unresolved_file" "$resolved_domains_file" "$all_domains_file"
  [ -n "$STUN_HOSTLIST" ] && append_hostlist_ips "$(expand_cfg_path "$STUN_HOSTLIST")" "$tmp_v4" "$tmp_v6" "$unresolved_file" "$resolved_domains_file" "$all_domains_file"

  if [ "$FORCE_REBUILD" = "true" ] && [ "$FAST_MODE" = "true" ]; then
    append_existing_auto_ips "$auto_v4_file" "$tmp_v4"
    append_existing_auto_ips "$cache_v4" "$tmp_v4"
    if [ "$IPV4_ONLY" = "true" ]; then
      append_existing_auto_ips "$auto_v6_file" "$tmp_v6"
      append_existing_auto_ips "$cache_v6" "$tmp_v6"
    fi
  fi

  write_current_snapshot \
    "$tmp_v4" "$tmp_v6" "$unresolved_file" \
    "$cache_v4" "$cache_v6" "$cache_unresolved" "$cache_meta" "$current_sig" \
    "$resolved_domains_file" "$all_domains_file" "$cache_resolved_domains" "$cache_all_domains"

  aggregate_service_cache "$SERVICE_ID" "$cache_dir" "$current_sig" "$auto_v4_file" "$auto_v6_file" "$unresolved_file" "$cache_unresolved"

  rm -f "$tmp_v4" "$tmp_v6" "$resolved_domains_file" "$all_domains_file"

  count_v4="$(count_non_comment_lines "$auto_v4_file")"
  count_v6="$(count_non_comment_lines "$auto_v6_file")"
  unresolved_count="$(count_non_comment_lines "$unresolved_file")"

  log_msg "$LOGFILE" "service=$SERVICE_ID mode=$MODE enabled=$ENABLED auto_ipv4_count=$count_v4 auto_ipv6_count=$count_v6 unresolved_count=$unresolved_count file_v4=$auto_v4_file file_v6=$auto_v6_file net=$CURRENT_NET_KEY"
done

log_msg "$LOGFILE" "rebuild_service_ipsets done target=${TARGET_SERVICE:-all} force=$FORCE_REBUILD vpn_only=$VPN_ONLY fast=$FAST_MODE ipv4_only=$IPV4_ONLY net=$CURRENT_NET_KEY"
echo ok
