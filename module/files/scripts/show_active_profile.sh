#!/system/bin/sh
. "$(dirname "$0")/common.sh"

ACTIVE_FILE="$CFG_DIR/active_profile.txt"
ACTIVE_ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '\r\n')"

if [ -z "$ACTIVE_ID" ]; then
  echo "no active profile"
  exit 0
fi

META_FILE="$CFG_DIR/profiles/$ACTIVE_ID/meta.conf"
if [ ! -f "$META_FILE" ]; then
  echo "active profile is missing"
  exit 1
fi

. "$META_FILE"

GROUP_LABEL="$GROUP_ID"
if [ -n "$GROUP_ID" ] && [ -f "$CFG_DIR/groups/$GROUP_ID/name.txt" ]; then
  GROUP_LABEL="$(cat "$CFG_DIR/groups/$GROUP_ID/name.txt" 2>/dev/null | tr -d '')"
fi
[ -n "$GROUP_LABEL" ] || GROUP_LABEL="-"

echo "id=$PROFILE_ID"
echo "name=$PROFILE_NAME"
echo "server=$SERVER"
echo "port=$PORT"
echo "group=$GROUP_LABEL"
echo "sni=$SNI"
echo "network=$NETWORK"