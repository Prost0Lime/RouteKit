#!/system/bin/sh
. "$(dirname "$0")/common.sh"

for f in "$CFG_DIR"/zapret_profiles/*.conf; do
  [ -f "$f" ] || continue

  PROFILE_ID=""
  PROFILE_NAME=""
  ENGINE=""
  ENABLED=""
  TCP_STRATEGY=""
  UDP_STRATEGY=""
  STUN_STRATEGY=""
  TCP_HOSTLIST=""
  TCP_IPSET=""
  UDP_HOSTLIST=""
  UDP_IPSET=""
  PRESET_FILE=""

  . "$f"

  [ -n "$PROFILE_ID" ] || PROFILE_ID="$(basename "$f" .conf)"

  summary=""

  [ -n "$ENGINE" ] && summary="$summary | $ENGINE"
  [ -n "$TCP_STRATEGY" ] && summary="$summary | tcp=$TCP_STRATEGY"
  [ -n "$UDP_STRATEGY" ] && summary="$summary | udp=$UDP_STRATEGY"
  [ -n "$STUN_STRATEGY" ] && summary="$summary | stun=$STUN_STRATEGY"
  [ -n "$TCP_HOSTLIST" ] && summary="$summary | tcp_hostlist=$(basename "$TCP_HOSTLIST")"
  [ -n "$TCP_IPSET" ] && summary="$summary | tcp_ipset=$(basename "$TCP_IPSET")"
  [ -n "$UDP_HOSTLIST" ] && summary="$summary | udp_hostlist=$(basename "$UDP_HOSTLIST")"
  [ -n "$UDP_IPSET" ] && summary="$summary | udp_ipset=$(basename "$UDP_IPSET")"
  [ -n "$PRESET_FILE" ] && summary="$summary | preset=$(basename "$PRESET_FILE")"

  if [ -z "$summary" ]; then
    echo "$PROFILE_ID | $PROFILE_NAME"
  else
    echo "$PROFILE_ID | $PROFILE_NAME$summary"
  fi
done