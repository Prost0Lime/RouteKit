#!/system/bin/sh

MODDIR=${0%/*}
BASE="$MODDIR/files"
CFG="$BASE/config"
RUNTIME="$BASE/runtime"
LOGDIR="$RUNTIME/logs"
PIDDIR="$RUNTIME/pids"
SOCKDIR="$RUNTIME/sockets"
TMPDIR="$RUNTIME/tmp"
PROFILESDIR="$CFG/profiles"
GROUPSDIR="$CFG/groups"

mkdir -p "$CFG" "$LOGDIR" "$PIDDIR" "$SOCKDIR" "$TMPDIR" "$PROFILESDIR" "$GROUPSDIR"

chmod -R 0755 "$BASE/scripts"
find "$BASE/bin" -type f -exec chmod 0755 {} \; 2>/dev/null

if [ ! -f "$CFG/app_state.json" ]; then
cat > "$CFG/app_state.json" <<'EOF'
{
  "zapret_enabled": true,
  "proxy_enabled": false,
  "routing_enabled": false,
  "routing_mode": "proxy_list",
  "transproxy_enabled": false,
  "ipv6_block_enabled": true,
  "dns_redirect_enabled": false,
  "selected_zapret_profile": "default",
  "selected_proxy_group": "default"
}
EOF
fi

if [ ! -f "$CFG/active_profile.txt" ]; then
  echo "" > "$CFG/active_profile.txt"
fi

if [ ! -f "$CFG/profile_counter.txt" ]; then
  echo "0" > "$CFG/profile_counter.txt"
fi

if [ ! -f "$CFG/group_counter.txt" ]; then
  echo "0" > "$CFG/group_counter.txt"
fi

if [ ! -f "$CFG/proxy_domains.txt" ]; then
  cat > "$CFG/proxy_domains.txt" <<'EOF'
# domains routed via VLESS in proxy_list mode
youtube.com
googlevideo.com
ytimg.com
youtu.be
youtubei.googleapis.com
ggpht.com
yt3.ggpht.com
EOF
fi

if [ ! -f "$CFG/direct_domains.txt" ]; then
  cat > "$CFG/direct_domains.txt" <<'EOF'
# domains routed DIRECT in direct_list mode
EOF
fi

echo "[post-fs-data] ok $(date)" >> "$LOGDIR/bootstrap.log"