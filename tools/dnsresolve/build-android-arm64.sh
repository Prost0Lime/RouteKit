#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/module/files/bin/dns"
OUT_BIN="$OUT_DIR/dnsresolve"

mkdir -p "$OUT_DIR"

export GOOS=android
export GOARCH=arm64
export CGO_ENABLED=0

go build -trimpath -ldflags="-s -w" -o "$OUT_BIN" "$SCRIPT_DIR/main.go"
echo "Built $OUT_BIN"
