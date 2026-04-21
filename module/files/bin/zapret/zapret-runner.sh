#!/system/bin/sh

BASE_DIR="${0%/*/*/*}"
LOGFILE="$BASE_DIR/runtime/logs/zapret.log"

mkdir -p "$BASE_DIR/runtime/logs"

echo "[zapret-runner] started" >> "$LOGFILE"
echo "[zapret-runner] profile_id=$ZAPRET_PROFILE_ID" >> "$LOGFILE"
echo "[zapret-runner] profile_name=$ZAPRET_PROFILE_NAME" >> "$LOGFILE"
echo "[zapret-runner] engine=$ZAPRET_ENGINE" >> "$LOGFILE"
echo "[zapret-runner] tcp_ports=$ZAPRET_TCP_PORTS" >> "$LOGFILE"
echo "[zapret-runner] udp_ports=$ZAPRET_UDP_PORTS" >> "$LOGFILE"
echo "[zapret-runner] mode=$ZAPRET_MODE" >> "$LOGFILE"
echo "[zapret-runner] args=$ZAPRET_ARGS" >> "$LOGFILE"

while true; do
  echo "[zapret-runner] heartbeat $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE"
  sleep 30
done