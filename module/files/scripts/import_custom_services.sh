#!/system/bin/sh
. "$(dirname "$0")/common.sh"

IMPORT_FILE="$1"
[ -n "$IMPORT_FILE" ] || { echo "usage: $0 <import_file>"; exit 1; }
[ -f "$IMPORT_FILE" ] || { echo "import file not found"; exit 1; }

validate_import_file() {
  local in_block=0
  local service_count=0
  local block_name=""
  local block_mode=""
  local block_enabled=""
  local line=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    [ -n "$line" ] || continue

    case "$line" in
      BEGIN_SERVICE)
        [ "$in_block" = "0" ] || { echo "invalid import: nested BEGIN_SERVICE"; return 1; }
        in_block=1
        block_name=""
        block_mode=""
        block_enabled=""
        ;;
      END_SERVICE)
        [ "$in_block" = "1" ] || { echo "invalid import: END_SERVICE without BEGIN_SERVICE"; return 1; }
        [ -n "$block_name" ] || { echo "invalid import: service_name missing"; return 1; }
        if [ -n "$block_mode" ]; then
          case "$block_mode" in direct|zapret|vpn) ;; *) echo "invalid import: bad mode=$block_mode"; return 1 ;; esac
        fi
        if [ -n "$block_enabled" ]; then
          case "$block_enabled" in true|false) ;; *) echo "invalid import: bad enabled=$block_enabled"; return 1 ;; esac
        fi
        service_count=$((service_count + 1))
        in_block=0
        ;;
      service_name=*)
        [ "$in_block" = "1" ] || { echo "invalid import: service_name outside service block"; return 1; }
        block_name="${line#service_name=}"
        ;;
      mode=*)
        [ "$in_block" = "1" ] || { echo "invalid import: mode outside service block"; return 1; }
        block_mode="${line#mode=}"
        ;;
      enabled=*)
        [ "$in_block" = "1" ] || { echo "invalid import: enabled outside service block"; return 1; }
        block_enabled="${line#enabled=}"
        ;;
      domain=*|service_id=*|tcp_strategy=*|udp_strategy=*|stun_strategy=*)
        [ "$in_block" = "1" ] || { echo "invalid import: value outside service block"; return 1; }
        ;;
      *)
        echo "invalid import: unknown line=$line"
        return 1
        ;;
    esac
  done < "$IMPORT_FILE"

  [ "$in_block" = "0" ] || { echo "invalid import: missing END_SERVICE"; return 1; }
  [ "$service_count" -gt 0 ] || { echo "invalid import: no services found"; return 1; }
  return 0
}

validate_import_file || exit 1

CURRENT_NAME=""
CURRENT_MODE=""
CURRENT_ENABLED="true"
CURRENT_TCP=""
CURRENT_UDP=""
CURRENT_STUN=""
TMP_DOMAINS=""
IMPORTED_IDS=""
IN_BLOCK=0

reset_block() {
  CURRENT_NAME=""
  CURRENT_MODE=""
  CURRENT_ENABLED="true"
  CURRENT_TCP=""
  CURRENT_UDP=""
  CURRENT_STUN=""
  [ -n "$TMP_DOMAINS" ] && rm -f "$TMP_DOMAINS"
  TMP_DOMAINS="$RUNTIME_DIR/tmp/custom_services_import.$$.$RANDOM.txt"
  : > "$TMP_DOMAINS"
}

finalize_block() {
  [ "$IN_BLOCK" = "1" ] || return 0
  [ -n "$CURRENT_NAME" ] || { echo "invalid import: service_name missing"; return 1; }
  [ -n "$CURRENT_MODE" ] || CURRENT_MODE="direct"

  CREATED_ID="$(sh "$(dirname "$0")/create_service.sh" "$CURRENT_NAME" "$CURRENT_MODE" "$TMP_DOMAINS")" || return 1
  if [ "$CURRENT_ENABLED" = "false" ]; then
    MODE_FILE="$CFG_DIR/service_modes/$CREATED_ID.conf"
    MODE_TMP="$RUNTIME_DIR/tmp/custom_services_mode.$$.$RANDOM.conf"
    awk -v enabled="$CURRENT_ENABLED" '
      BEGIN { done = 0 }
      /^ENABLED=/ {
        printf "ENABLED=\"%s\"\n", enabled
        done = 1
        next
      }
      { print }
      END {
        if (!done) {
          printf "ENABLED=\"%s\"\n", enabled
        }
      }
    ' "$MODE_FILE" > "$MODE_TMP" && mv "$MODE_TMP" "$MODE_FILE"
  fi
  [ -n "$CURRENT_TCP" ] && sh "$(dirname "$0")/set_service_strategy.sh" "$CREATED_ID" tcp "$CURRENT_TCP" >/dev/null 2>&1
  [ -n "$CURRENT_UDP" ] && sh "$(dirname "$0")/set_service_strategy.sh" "$CREATED_ID" udp "$CURRENT_UDP" >/dev/null 2>&1
  [ -n "$CURRENT_STUN" ] && sh "$(dirname "$0")/set_service_strategy.sh" "$CREATED_ID" stun "$CURRENT_STUN" >/dev/null 2>&1

  IMPORTED_IDS="${IMPORTED_IDS}${CREATED_ID}\n"
  IN_BLOCK=0
  reset_block
}

mkdir -p "$RUNTIME_DIR/tmp"
reset_block

while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | tr -d '\r')"
  [ -n "$line" ] || continue

  case "$line" in
    BEGIN_SERVICE)
      [ "$IN_BLOCK" = "1" ] && finalize_block || true
      IN_BLOCK=1
      ;;
    END_SERVICE)
      finalize_block || exit 1
      ;;
    service_name=*)
      CURRENT_NAME="${line#service_name=}"
      ;;
    mode=*)
      CURRENT_MODE="${line#mode=}"
      ;;
    enabled=*)
      CURRENT_ENABLED="${line#enabled=}"
      ;;
    tcp_strategy=*)
      CURRENT_TCP="${line#tcp_strategy=}"
      ;;
    udp_strategy=*)
      CURRENT_UDP="${line#udp_strategy=}"
      ;;
    stun_strategy=*)
      CURRENT_STUN="${line#stun_strategy=}"
      ;;
    domain=*)
      printf '%s\n' "${line#domain=}" >> "$TMP_DOMAINS"
      ;;
  esac
done < "$IMPORT_FILE"

[ "$IN_BLOCK" = "1" ] && finalize_block || true
[ -n "$TMP_DOMAINS" ] && rm -f "$TMP_DOMAINS"

if [ -z "$IMPORTED_IDS" ]; then
  echo "no services imported"
  exit 1
fi

printf '%b' "$IMPORTED_IDS" | sed '/^[[:space:]]*$/d'
