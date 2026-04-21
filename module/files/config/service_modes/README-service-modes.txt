Per-service defaults updated from working magisk-zapret2 lists.
Added ready ipsets for: youtube, instagram, facebook, discord, telegram, x.
Instagram/Facebook/X use hostlist for TCP and ipset for UDP/QUIC by default.
Discord has ready STUN ipset + fake_veryfast_stun_discord default.
Telegram now also has ready TCP ipset available in service_modes, but hostlist remains for VPN/direct domain routing.
