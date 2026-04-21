#!/system/bin/sh
. "$(dirname "$0")/common.sh"
SERVICE="$1"
MODE_NEW="$2"
VPN_PROFILE_NEW="$3"
[ -n "$SERVICE" ] && [ -n "$MODE_NEW" ] || { echo "usage: $0 <service_id> <zapret|vpn|direct> [vpn_profile]"; exit 1; }
case "$MODE_NEW" in zapret|vpn|direct) ;; *) echo "invalid mode"; exit 1 ;; esac
FILE="$(service_mode_file_for "$SERVICE")" || { echo "service not found: $SERVICE"; exit 1; }
TMP="$FILE.tmp"
awk -v mode="$MODE_NEW" -v vpn="$VPN_PROFILE_NEW" '
BEGIN{done1=0;done2=0}
/^MODE=/{print "MODE=\"" mode "\""; done1=1; next}
/^VPN_PROFILE=/{if (vpn != "") print "VPN_PROFILE=\"" vpn "\""; else print $0; done2=1; next}
{print}
END{if(!done1) print "MODE=\"" mode "\""; if(vpn != "" && !done2) print "VPN_PROFILE=\"" vpn "\""}
' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
echo ok
