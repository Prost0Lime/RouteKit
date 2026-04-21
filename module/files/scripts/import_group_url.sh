#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/import_group_url.log"
TMP_DIR="$RUNTIME_DIR/tmp"

URL="$1"
GROUP_NAME="$2"

if [ -z "$URL" ]; then
  echo "usage: import_group_url.sh 'https://example.com/list.txt' [group_name]"
  exit 1
fi

mkdir -p "$TMP_DIR"

TMP_FILE="$TMP_DIR/group_import_$(date +%s).txt"

log_msg "$LOGFILE" "import_group_url begin url=$URL"

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --silent --show-error "$URL" -o "$TMP_FILE"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_msg "$LOGFILE" "curl download failed rc=$RC"
    rm -f "$TMP_FILE"
    echo "download failed"
    exit 1
  fi
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMP_FILE" "$URL"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_msg "$LOGFILE" "wget download failed rc=$RC"
    rm -f "$TMP_FILE"
    echo "download failed"
    exit 1
  fi
else
  log_msg "$LOGFILE" "no curl or wget found"
  echo "no curl or wget found"
  exit 1
fi

GROUP_ID="$(sh "$(dirname "$0")/import_group_file.sh" "$TMP_FILE" "$GROUP_NAME")"
RC=$?

rm -f "$TMP_FILE"

if [ "$RC" -ne 0 ] || [ -z "$GROUP_ID" ]; then
  log_msg "$LOGFILE" "import_group_file failed"
  echo "import failed"
  exit 1
fi

log_msg "$LOGFILE" "import_group_url done group_id=$GROUP_ID"
echo "$GROUP_ID"