$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Source = Join-Path $PSScriptRoot "main.go"
$OutDir = Join-Path $RepoRoot "module\files\bin\dns"
$OutBin = Join-Path $OutDir "dnsresolve"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$env:GOOS = "android"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "0"

go build -trimpath -ldflags="-s -w" -o $OutBin $Source

Write-Host "Built $OutBin"
