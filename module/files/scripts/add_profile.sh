#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/add_profile.log"
COUNTER_FILE="$CFG_DIR/profile_counter.txt"
PROFILES_DIR="$CFG_DIR/profiles"

URI="$1"
GROUP_ID="$2"
PROFILE_NAME="$3"

log_msg "$LOGFILE" "add_profile begin"

if [ -z "$URI" ]; then
  echo "usage: add_profile.sh 'vless://...' [group_id] [name]"
  log_msg "$LOGFILE" "empty uri"
  exit 1
fi

case "$URI" in
  vless://*) ;;
  *)
    echo "invalid uri"
    log_msg "$LOGFILE" "invalid scheme"
    exit 1
    ;;
esac

mkdir -p "$PROFILES_DIR"

COUNTER="$(cat "$COUNTER_FILE" 2>/dev/null)"
[ -n "$COUNTER" ] || COUNTER=0
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE"

PROFILE_ID="$(printf "profile_%04d" "$COUNTER")"
PROFILE_DIR="$PROFILES_DIR/$PROFILE_ID"
mkdir -p "$PROFILE_DIR"

MAIN="${URI#vless://}"
LABEL=""
case "$MAIN" in
  *#*)
    LABEL="${MAIN#*#}"
    MAIN="${MAIN%%#*}"
    ;;
esac

USERINFO="${MAIN%%@*}"
REST="${MAIN#*@}"

HOSTPORT="${REST%%\?*}"
QUERY=""
if echo "$REST" | grep -q '\?'; then
  QUERY="${REST#*\?}"
fi

UUID="$USERINFO"
SERVER="${HOSTPORT%:*}"
PORT="${HOSTPORT##*:}"

get_qparam() {
  KEY="$1"
  echo "$QUERY" | tr '&' '\n' | grep "^${KEY}=" | head -n1 | sed "s/^${KEY}=//"
}

urldecode() {
  local data
  data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

TYPE="$(urldecode "$(get_qparam type)")"
SECURITY="$(urldecode "$(get_qparam security)")"
PBK="$(urldecode "$(get_qparam pbk)")"
FP="$(urldecode "$(get_qparam fp)")"
SNI="$(urldecode "$(get_qparam sni)")"
SID="$(urldecode "$(get_qparam sid)")"

[ -n "$TYPE" ] || TYPE="tcp"
[ -n "$FP" ] || FP="chrome"
[ -n "$GROUP_ID" ] || GROUP_ID=""
[ -n "$PROFILE_NAME" ] || PROFILE_NAME="$(urldecode "$LABEL")"
[ -n "$PROFILE_NAME" ] || PROFILE_NAME="$PROFILE_ID"

if [ -z "$UUID" ] || [ -z "$SERVER" ] || [ -z "$PORT" ]; then
  echo "missing required fields"
  log_msg "$LOGFILE" "missing uuid/server/port"
  exit 1
fi

if [ "$SECURITY" != "reality" ]; then
  echo "currently only reality is supported"
  log_msg "$LOGFILE" "unsupported security=$SECURITY"
  exit 1
fi

if [ -z "$PBK" ] || [ -z "$SNI" ] || [ -z "$SID" ]; then
  echo "missing reality fields"
  log_msg "$LOGFILE" "missing reality fields"
  exit 1
fi

echo "$URI" > "$PROFILE_DIR/raw_uri.txt"

cat > "$PROFILE_DIR/meta.conf" <<EOF
PROFILE_ID='$PROFILE_ID'
GROUP_ID='$GROUP_ID'
PROFILE_NAME='$PROFILE_NAME'
TYPE='vless'
SERVER='$SERVER'
PORT='$PORT'
UUID='$UUID'
NETWORK='$TYPE'
SECURITY='$SECURITY'
PUBLIC_KEY='$PBK'
FINGERPRINT='$FP'
SNI='$SNI'
SHORT_ID='$SID'
ENABLED='true'
EOF

log_msg "$LOGFILE" "profile created id=$PROFILE_ID server=$SERVER port=$PORT group_id=$GROUP_ID"
echo "$PROFILE_ID"