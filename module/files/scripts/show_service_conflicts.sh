#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
[ -n "$SERVICE_ID" ] || { echo "usage: $0 <service_id>"; exit 1; }
MODE_FILE="$(service_mode_file_for "$SERVICE_ID")" || { echo "service not found: $SERVICE_ID"; exit 1; }
SERVICE_ID=""; MODE="direct"; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; . "$MODE_FILE"
THIS_ID="$SERVICE_ID"
THIS_MODE="$MODE"
THIS_DOMAINS_FILE="$RUNTIME_DIR/conflicts/.this_${SERVICE_ID}_$$.txt"
ALL_DOMAINS_FILE="$RUNTIME_DIR/conflicts/.all_${SERVICE_ID}_$$.txt"
mkdir -p "$RUNTIME_DIR/conflicts"
trap 'rm -f "$THIS_DOMAINS_FILE" "$ALL_DOMAINS_FILE"' EXIT
: > "$THIS_DOMAINS_FILE"
for p in "$TCP_HOSTLIST" "$UDP_HOSTLIST" "$STUN_HOSTLIST"; do
  [ -n "$p" ] || continue
  fp="$(expand_cfg_path "$p")"
  [ -f "$fp" ] || continue
  grep -v '^[[:space:]]*$' "$fp" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | tr '[:upper:]' '[:lower:]' >> "$THIS_DOMAINS_FILE"
done
sort -u "$THIS_DOMAINS_FILE" -o "$THIS_DOMAINS_FILE"
: > "$ALL_DOMAINS_FILE"
for f in $(service_mode_files); do
  [ -f "$f" ] || continue
  SERVICE_ID=""; MODE="direct"; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; . "$f"
  OTHER_ID="$SERVICE_ID"
  [ "$OTHER_ID" = "$THIS_ID" ] && continue
  NAME="$OTHER_ID"
  DEF="$CFG_DIR/services/$OTHER_ID.conf"
  if [ -f "$DEF" ]; then
    SERVICE_NAME=""; . "$DEF"
    [ -n "$SERVICE_NAME" ] && NAME="$SERVICE_NAME"
  fi
  for p in "$TCP_HOSTLIST" "$UDP_HOSTLIST" "$STUN_HOSTLIST"; do
    [ -n "$p" ] || continue
    fp="$(expand_cfg_path "$p")"
    [ -f "$fp" ] || continue
    grep -v '^[[:space:]]*$' "$fp" 2>/dev/null | grep -v '^[[:space:]]*#' 2>/dev/null | tr '[:upper:]' '[:lower:]' | while IFS= read -r d; do
      [ -n "$d" ] || continue
      printf '%s|%s|%s|%s
' "$d" "$OTHER_ID" "$NAME" "$MODE" >> "$ALL_DOMAINS_FILE"
    done
  done
done
sort -u "$ALL_DOMAINS_FILE" -o "$ALL_DOMAINS_FILE"
while IFS='|' read -r domain other_id other_name other_mode || [ -n "$domain" ]; do
  [ -n "$domain" ] || continue
  if grep -Fxq "$domain" "$THIS_DOMAINS_FILE"; then
    relation="same_mode"
    [ "$other_mode" != "$THIS_MODE" ] && relation="mode_conflict"
    printf '%s|%s|%s|%s|%s
' "$domain" "$other_id" "$other_name" "$other_mode" "$relation"
  fi
done < "$ALL_DOMAINS_FILE"
