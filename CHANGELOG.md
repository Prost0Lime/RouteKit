# Changelog

## 0.9.2 - 2026-04-28

- Add VPN subscription group refresh from the saved source URL.
- Add whole VPN profile group deletion from the app.
- Preserve the group while replacing profiles during subscription refresh.

## 0.9.1 - 2026-04-27

- Make Russian README the default documentation entry point.
- Add English README link and VPN Detector screenshots.
- Add RouteKit UI screenshots and document current arm64-v8a binary target.
- Document RouteKit's non-`VpnService`/non-TUN routing model and detection test results.
- Add notes about where detection checks can still produce indirect network signals.
- Add a default ChatGPT service in direct mode.
- Change the default YouTube zapret strategies to `syndata_multidisorder_tls_google_700` and `fake_6_google_quic`.
- Add module settings for IPv6 collection, IPv6 blocking and DNS resolve repeat count.
- Speed up zapret-only strategy apply without rebuilding VPN/transproxy rules.

## 0.9.0 - 2026-04-22

- Change Android application id to `io.github.prost0lime.routekit`.
- Prepare signed release APK builds through GitHub Actions secrets.
- Add Magisk update metadata with `updateJson` and `update.json`.
- Add in-app GitHub release update checker.
- Refresh release documentation and RouteKit launcher icon.

## 0.8.2 - 2026-04-22

- Synchronize Android app and module version metadata.
- Add release notes and checklist documentation for repeatable GitHub releases.

## 0.8.1 - 2026-04-22

- Initial RouteKit beta source release.
- Add selective routing modes for zapret, direct and VPN/transproxy services.
- Add custom service import/export, service diagnostics and repair helpers.
- Add DNS redirect handling, automatic IP collection and bundled `dnsresolve`.
- Add VPN profile groups with profile checks and faster active-profile switching.
- Add module packaging scripts and GitHub Actions release workflow.
