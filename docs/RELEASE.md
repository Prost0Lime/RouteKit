# Release Checklist

This project publishes release artifacts from GitHub Actions when a tag like `v0.9.0` is pushed.

## Before Tagging

- Update `versionName` and `versionCode` in `app/build.gradle.kts`.
- Update `version` and `versionCode` in `module/module.prop`.
- Update `update.json` so Magisk can find the new module zip.
- Add a short entry to `CHANGELOG.md`.
- Build and test the APK locally if possible.
- Install the module on a test device.
- Confirm `healthcheck.sh` reports expected state.
- Confirm a VPN-mode custom service works after pressing `Apply`.
- Confirm `diagnose_service.sh <service>` returns `status=OK` for a known working service.
- Confirm no real VPN profiles or generated runtime files are tracked by git.

## Local Module Package

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/package-module.ps1
```

Linux/macOS/WSL:

```bash
sh tools/package-module.sh
```

The zip is written to `dist/`.

## Create a Release

GitHub Actions requires these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Create the base64 value from your local keystore without committing the keystore:

```bash
keytool -genkeypair \
  -v \
  -keystore routekit-release.jks \
  -alias routekit \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

```bash
base64 -w 0 routekit-release.jks
```

PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("routekit-release.jks"))
```

```bash
git tag v0.9.0
git push origin v0.9.0
```

GitHub Actions will build:

- `RouteKit-app-release.apk`
- `RouteKit-module-v0.9.0.zip`

The workflow also supports manual runs from the Actions tab. Manual runs upload workflow artifacts but do not create a GitHub Release unless they are running on a tag.

## Notes

- `v0.9.0` changes the Android package id to `io.github.prost0lime.routekit`; uninstall old `com.example.zapret2manager` beta builds before testing.
- The module id remains `zapret2_manager` for compatibility.
- `sing-box` is bundled in the repository and is larger than GitHub's recommended 50 MB file size.
