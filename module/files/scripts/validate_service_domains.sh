#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE_ID="$1"
SRC_FILE="$2"
[ -n "$SERVICE_ID" ] && [ -n "$SRC_FILE" ] || { echo "usage: $0 <service_id> <domains_file>"; exit 1; }
THIS_MODE_FILE="$(service_mode_file_for "$SERVICE_ID")" || { echo "service not found: $SERVICE_ID"; exit 1; }
SERVICE_ID=""; MODE="direct"; . "$THIS_MODE_FILE"
THIS_MODE="$MODE"
TMP_THIS="$(service_conflicts_file_for "tmp_this_${SERVICE_ID}_$$")"
TMP_ALL="$(service_conflicts_file_for "tmp_all_${SERVICE_ID}_$$")"
trap 'rm -f "$TMP_THIS" "$TMP_ALL"' EXIT

normalize_domains_file() {
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    {
      line=$0
      gsub(/\r/, "", line)
      line=trim(line)
      if (line == "" || line ~ /^#/) next
      line=tolower(line)
      sub(/\.$/, "", line)
      if (line ~ /^\*\./) {
        line="suffix:" substr(line, 3)
      } else if (line ~ /^suffix:/) {
        sub(/^suffix:\*\./, "suffix:", line)
        sub(/\.$/, "", line)
      }
      print line
    }
  ' "$1"
}

normalize_domains_file "$SRC_FILE" | sort -u > "$TMP_THIS"
: > "$TMP_ALL"
for f in $(service_mode_files); do
  [ -f "$f" ] || continue
  SERVICE_ID=""; MODE="direct"; TCP_HOSTLIST=""; UDP_HOSTLIST=""; STUN_HOSTLIST=""; . "$f"
  OTHER_ID="$SERVICE_ID"
  [ "$OTHER_ID" = "$1" ] && continue
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
    normalize_domains_file "$fp" 2>/dev/null | while IFS= read -r d; do
      [ -n "$d" ] || continue
      printf '%s|%s|%s|%s\n' "$d" "$OTHER_ID" "$NAME" "$MODE" >> "$TMP_ALL"
    done
  done
done
sort -u "$TMP_ALL" -o "$TMP_ALL"
while IFS='|' read -r domain other_id other_name other_mode || [ -n "$domain" ]; do
  [ -n "$domain" ] || continue
  if grep -Fxq "$domain" "$TMP_THIS"; then
    relation="same_mode"
    [ "$other_mode" != "$THIS_MODE" ] && relation="mode_conflict"
    printf '%s|%s|%s|%s|%s\n' "$domain" "$other_id" "$other_name" "$other_mode" "$relation"
  fi
done < "$TMP_ALL"
