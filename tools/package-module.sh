#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MODULE="$ROOT/module"
OUTDIR="${1:-$ROOT/dist}"

if [ ! -f "$MODULE/module.prop" ]; then
  echo "module/module.prop not found" >&2
  exit 1
fi

NAME="$(sed -n 's/^name=//p' "$MODULE/module.prop" | head -n 1)"
VERSION="$(sed -n 's/^version=//p' "$MODULE/module.prop" | head -n 1)"
[ -n "$NAME" ] || NAME="RouteKit"
[ -n "$VERSION" ] || VERSION="dev"

SAFE_NAME="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '-')"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/${SAFE_NAME}-module-v${VERSION}.zip"
rm -f "$OUT"

(
  cd "$MODULE"
  zip -r "$OUT" . \
    -x 'module.zip' \
    -x 'files/config/proxy.json' \
    -x 'files/config/active_profile.txt' \
    -x 'files/runtime/*' \
    -x 'files/config/profiles/*' \
    -x '*.log' \
    -x '.gitkeep' \
    -x '*/.gitkeep'
)

echo "Created $OUT"
