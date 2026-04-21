#!/system/bin/sh
. "$(dirname "$0")/common.sh"

GROUP_ARG="$1"
[ -n "$GROUP_ARG" ] || { echo "usage: $0 <group_id|__ungrouped>"; exit 1; }

ACTIVE_FILE="$CFG_DIR/active_profile.txt"
ACTIVE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

profile_ids_for_group() {
  if [ "$GROUP_ARG" = "__ungrouped" ] || [ "$GROUP_ARG" = "-" ]; then
    for meta in "$CFG_DIR"/profiles/profile_*/meta.conf; do
      [ -f "$meta" ] || continue
      PROFILE_ID=""
      GROUP_ID=""
      . "$meta"
      [ -z "$GROUP_ID" ] && echo "$PROFILE_ID"
    done
    return
  fi

  if [ -f "$CFG_DIR/groups/$GROUP_ARG/profiles.txt" ]; then
    cat "$CFG_DIR/groups/$GROUP_ARG/profiles.txt" 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d'
  else
    for meta in "$CFG_DIR"/profiles/profile_*/meta.conf; do
      [ -f "$meta" ] || continue
      PROFILE_ID=""
      GROUP_ID=""
      . "$meta"
      [ "$GROUP_ID" = "$GROUP_ARG" ] && echo "$PROFILE_ID"
    done
  fi
}

ping_ms() {
  host="$1"
  [ -n "$host" ] || { echo "timeout"; return; }
  out="$(ping -c 1 -W 2 "$host" 2>/dev/null)"
  ms="$(printf '%s\n' "$out" | awk -F'time=' '/time=/{ split($2,a," "); printf "%d", a[1] + 0; exit }')"
  [ -n "$ms" ] && echo "$ms" || echo "timeout"
}

FOUND=0
for profile_id in $(profile_ids_for_group); do
  meta="$CFG_DIR/profiles/$profile_id/meta.conf"
  [ -f "$meta" ] || continue

  PROFILE_ID=""
  PROFILE_NAME=""
  SERVER=""
  PORT=""
  . "$meta"

  active="false"
  [ "$PROFILE_ID" = "$ACTIVE_ID" ] && active="true"
  ms="$(ping_ms "$SERVER")"
  echo "$PROFILE_ID|$ms|$SERVER:$PORT|$PROFILE_NAME|active=$active"
  FOUND=1
done

[ "$FOUND" = "1" ] || { echo "no profiles"; exit 1; }
