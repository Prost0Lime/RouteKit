param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ModuleDir = Join-Path $Root "module"
$ModulePrefix = (Resolve-Path $ModuleDir).Path.TrimEnd("\") + "\"

if (-not (Test-Path (Join-Path $ModuleDir "module.prop"))) {
    throw "module/module.prop not found"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $Root "dist"
}

$moduleProp = Get-Content (Join-Path $ModuleDir "module.prop")
$name = ($moduleProp | Where-Object { $_ -like "name=*" } | Select-Object -First 1).Substring(5)
$version = ($moduleProp | Where-Object { $_ -like "version=*" } | Select-Object -First 1).Substring(8)

if ([string]::IsNullOrWhiteSpace($name)) { $name = "RouteKit" }
if ([string]::IsNullOrWhiteSpace($version)) { $version = "dev" }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$safeName = ($name -replace "[^A-Za-z0-9._-]", "-")
$zipPath = Join-Path $OutputDir "$safeName-module-v$version.zip"
if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)

try {
    Get-ChildItem -Path $ModuleDir -Recurse -File | ForEach-Object {
        $fullPath = $_.FullName
        $relative = $fullPath.Substring($ModulePrefix.Length).Replace("\", "/")

        if ($relative -eq "module.zip") { return }
        if ($relative -eq "files/config/proxy.json") { return }
        if ($relative -eq "files/config/active_profile.txt") { return }
        if ($relative -like "files/runtime/*") { return }
        if ($relative -like "files/config/profiles/*") { return }
        if ($relative -like "*.log") { return }
        if ($relative -eq ".gitkeep" -or $relative -like "*/.gitkeep") { return }

        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $fullPath,
            $relative,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Created $zipPath"
