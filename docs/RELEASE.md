# Release Checklist

This project publishes release artifacts from GitHub Actions when a tag like `v0.8.1` is pushed.

## Before Tagging

- Update `versionName` and `versionCode` in `app/build.gradle.kts`.
- Update `version` and `versionCode` in `module/module.prop`.
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

```bash
git tag v0.8.2
git push origin v0.8.2
```

GitHub Actions will build:

- `RouteKit-app-debug.apk`
- `RouteKit-module-v0.8.2.zip`

The workflow also supports manual runs from the Actions tab. Manual runs upload workflow artifacts but do not create a GitHub Release unless they are running on a tag.

## Notes

- The APK is currently a debug APK.
- The module id remains `zapret2_manager` for compatibility.
- `sing-box` is bundled in the repository and is larger than GitHub's recommended 50 MB file size.
