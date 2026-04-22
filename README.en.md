# RouteKit

[Русский](README.md) | **English**

RouteKit is an Android root toolkit for selective traffic routing.

It combines a Magisk/KernelSU-style module, a small Android manager app, `sing-box`, and zapret/nfqws-based rules so individual services can be routed through one of three modes:

- `VPN` - route selected service IPs through the active VLESS profile using transparent proxy rules.
- `zapret` - apply zapret/nfqws strategies for selected services.
- `direct` - explicitly bypass proxy/zapret routing for selected domains.

The project is currently in beta and is intended for rooted Android devices.

## Features

- Android UI for managing service modes, custom services, and VLESS profiles.
- VPN profile groups with per-profile ping checks and sorting.
- Domain-based service configuration with `suffix:` wildcard-style entries.
- Automatic IPv4/IPv6 collection for VPN-mode services.
- DNS redirect to local `sing-box` DNS listener.
- Transparent proxy rules for selected IPv4 destinations.
- IPv6 block support for environments where IPv6 would bypass IPv4-only transproxy rules.
- Per-service diagnostics and repair actions.
- Per-profile diagnostics.
- Import/export for custom services.
- VLESS import from link, text, or file.

## Project Layout

```text
app/                     Android manager app
module/                  Root module payload
module/files/scripts/    Android shell control scripts
module/files/bin/        Bundled native binaries and zapret payloads
tools/dnsresolve/        Helper resolver source/build scripts
```

## Requirements

- Rooted Android device.
- Magisk, KernelSU, or compatible module environment.
- Android 7.0+ for the manager app.
- A working VLESS profile if you want to use `VPN` mode.

## Download

Download APK and module zip from the latest GitHub Release:

<https://github.com/Prost0Lime/RouteKit/releases/latest>

## Build APK

The Android project uses Gradle with Android Gradle Plugin 8.5.2 and Kotlin 1.9.24.

For quick local checks without a release keystore:

```bash
gradle :app:assembleDebug
```

If you have a local Gradle installation:

```bash
gradle :app:assembleRelease
```

If you add a Gradle wrapper later:

```bash
./gradlew :app:assembleRelease
```

The APK will be produced under `app/build/outputs/apk/`.

Release signing is configured through environment variables:

```text
ROUTEKIT_KEYSTORE_PATH
ROUTEKIT_KEYSTORE_PASSWORD
ROUTEKIT_KEY_ALIAS
ROUTEKIT_KEY_PASSWORD
```

The repository currently contains `gradle-wrapper.properties`, but does not include generated wrapper scripts/jar yet. Generate them with:

```bash
gradle wrapper --gradle-version 8.7
```

## Build Module Zip

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File tools/package-module.ps1
```

Linux/macOS/WSL:

```bash
sh tools/package-module.sh
```

The module zip is written to `dist/`.

The packaging scripts exclude runtime state, logs, generated `proxy.json`, `active_profile.txt`, and user VPN profiles.

## Releases

Release builds are automated with GitHub Actions.

Push a tag like:

```bash
git tag v0.9.0
git push origin v0.9.0
```

The workflow builds the APK, packages the module zip, and attaches both files to the GitHub Release.

See [docs/RELEASE.md](docs/RELEASE.md) for the checklist and [CHANGELOG.md](CHANGELOG.md) for release notes.

Magisk update metadata is published through [update.json](update.json). The module id remains `zapret2_manager` for compatibility.

## Module

The module lives in `module/`.

Important runtime paths on device:

```text
/data/adb/modules/zapret2_manager/files
/data/adb/modules/zapret2_manager/files/scripts
/data/adb/modules/zapret2_manager/files/runtime
```

The module id is still `zapret2_manager` for compatibility with existing installs and scripts.

The Android app package id for public releases is `io.github.prost0lime.routekit`. Older beta builds used `com.example.zapret2manager`, so uninstall the old beta app before installing `v0.9.0+` if Android shows a duplicate app.

## Typical Flow

1. Install the root module.
2. Install/open the Android manager app.
3. Import one or more VLESS profiles.
4. Select the active VPN profile.
5. Create or edit a service.
6. Set the service mode to `VPN`, `zapret`, or `direct`.
7. Press `Apply` in the app.
8. Use diagnostics if a service does not behave as expected.

For wildcard-style domains, use:

```text
suffix:example.com
```

This matches `example.com` and subdomains handled by the routing/resolution logic.

## Safety Notes

- Do not commit real VPN profiles, UUIDs, private keys, or generated runtime configs.
- `module/files/config/profiles/`, `proxy.json`, `active_profile.txt`, and runtime logs are intentionally ignored by git.
- The current transparent proxy implementation is IPv4-focused. IPv6 entries are detected, but IPv6 traffic should be blocked when relying on IPv4-only transproxy routing.
- Large native binaries are currently committed directly. GitHub may warn about `sing-box` being larger than 50 MB. Moving these binaries to Git LFS or release assets can be considered later.

## Status

RouteKit is an active beta. Core workflows are working, but APIs, scripts, and UI can still change.
