#!/system/bin/sh
. "$(dirname "$0")/common.sh"

LOGFILE="$LOG_DIR/zapret-manager.log"
PIDFILE="$PID_DIR/zapret.pid"
STATE_FILE="$CFG_DIR/app_state.json"

DUMMY_RUNNER="$BASE_DIR/bin/zapret/zapret-runner.sh"
NFQWS2_RUNNER="$BASE_DIR/bin/zapret/nfqws2-runner.sh"

log_msg "$LOGFILE" "start_zapret begin"

if [ ! -f "$STATE_FILE" ]; then
  log_msg "$LOGFILE" "state file missing"
  exit 1
fi

ZAPRET_ENABLED="$(json_bool zapret_enabled "$STATE_FILE")"
[ "$ZAPRET_ENABLED" = "true" ] || {
  log_msg "$LOGFILE" "zapret disabled in app_state"
  exit 0
}

PROFILE_ID="$(grep -o '"selected_zapret_profile"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/')"
[ -n "$PROFILE_ID" ] || PROFILE_ID="default"

PROFILE_FILE="$CFG_DIR/zapret_profiles/$PROFILE_ID.conf"
if [ ! -f "$PROFILE_FILE" ]; then
  log_msg "$LOGFILE" "zapret profile missing: $PROFILE_ID"
  exit 1
fi

PROFILE_NAME=""
ENGINE=""
ENABLED=""
TCP_PORTS=""
UDP_PORTS=""
MODE=""

PRESET_FILE=""
TCP_STRATEGY=""
UDP_STRATEGY=""
STUN_STRATEGY=""
TCP_HOSTLIST=""
TCP_IPSET=""
UDP_HOSTLIST=""
UDP_IPSET=""

NFQWS2_BIN=""
NFQWS2_DEBUG=""
NFQWS2_QNUM=""
NFQWS2_INTERCEPT=""
NFQWS2_DRY_RUN=""
NFQWS2_FILTER_TCP=""
NFQWS2_FILTER_UDP=""
NFQWS2_ARGS=""
ARGS=""

. "$PROFILE_FILE"

if [ "$ENABLED" != "true" ]; then
  log_msg "$LOGFILE" "zapret profile disabled: $PROFILE_ID"
  exit 0
fi

if pid_is_running "$PIDFILE"; then
  log_msg "$LOGFILE" "zapret already running"
  exit 0
fi

RUNNER=""
case "$ENGINE" in
  dummy)
    RUNNER="$DUMMY_RUNNER"
    ;;
  nfqws2)
    RUNNER="$NFQWS2_RUNNER"
    ;;
  *)
    log_msg "$LOGFILE" "unknown zapret engine: $ENGINE"
    exit 1
    ;;
esac

if [ ! -f "$RUNNER" ]; then
  log_msg "$LOGFILE" "runner missing: $RUNNER"
  exit 1
fi

chmod 0755 "$RUNNER" 2>/dev/null

sh "$(dirname "$0")/apply_zapret_nfqueue.sh" >> "$LOGFILE" 2>&1

(
  export ZAPRET_PROFILE_ID="$PROFILE_ID"
  export ZAPRET_PROFILE_NAME="$PROFILE_NAME"
  export ZAPRET_ENGINE="$ENGINE"
  export ZAPRET_TCP_PORTS="$TCP_PORTS"
  export ZAPRET_UDP_PORTS="$UDP_PORTS"
  export ZAPRET_MODE="$MODE"

  export ZAPRET_PRESET_FILE="$PRESET_FILE"
  export ZAPRET_TCP_STRATEGY="$TCP_STRATEGY"
  export ZAPRET_UDP_STRATEGY="$UDP_STRATEGY"
  export ZAPRET_STUN_STRATEGY="$STUN_STRATEGY"

  export ZAPRET_TCP_HOSTLIST="$TCP_HOSTLIST"
  export ZAPRET_TCP_IPSET="$TCP_IPSET"
  export ZAPRET_UDP_HOSTLIST="$UDP_HOSTLIST"
  export ZAPRET_UDP_IPSET="$UDP_IPSET"

  export ZAPRET_NFQWS2_BIN="$NFQWS2_BIN"
  export ZAPRET_NFQWS2_DEBUG="$NFQWS2_DEBUG"
  export ZAPRET_NFQWS2_QNUM="$NFQWS2_QNUM"
  export ZAPRET_NFQWS2_INTERCEPT="$NFQWS2_INTERCEPT"
  export ZAPRET_NFQWS2_DRY_RUN="$NFQWS2_DRY_RUN"
  export ZAPRET_NFQWS2_FILTER_TCP="$NFQWS2_FILTER_TCP"
  export ZAPRET_NFQWS2_FILTER_UDP="$NFQWS2_FILTER_UDP"
  export ZAPRET_NFQWS2_ARGS="$NFQWS2_ARGS"
  export ZAPRET_ARGS="$ARGS"

  nohup "$RUNNER" </dev/null >> "$LOG_DIR/zapret.log" 2>&1
) &

PID=$!
echo "$PID" > "$PIDFILE"

sleep 1

if pid_is_running "$PIDFILE"; then
  log_msg "$LOGFILE" "zapret started pid=$PID profile=$PROFILE_ID engine=$ENGINE"
else
  log_msg "$LOGFILE" "zapret failed to start profile=$PROFILE_ID engine=$ENGINE"
  rm -f "$PIDFILE"
  exit 1
fi