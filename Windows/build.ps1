# ScheutieOS Windows build script.
#
# Produces ONE file:  build\ScheutieOS-<version>-Setup.exe
# That exe is both the installer and the app:
#   · double-click it anywhere else  → it "unpacks" (copies) itself to
#     %LOCALAPPDATA%\ScheutieOS, creates shortcuts, registers an uninstall
#     entry, then launches the installed copy;
#   · the installed copy just runs the app.
#
# Requirements: .NET SDK 8 (auto-installed via winget or the official
# dotnet-install script if missing), Windows 10+.

#Requires -Version 5.1
param(
    [string]$Configuration = "Release",
    [switch]$NoIconRegen
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $Root "build"

Write-Host "==> ScheutieOS Windows build" -ForegroundColor Cyan

# ---------------------------------------------------------------- 0) icon

if (-not $NoIconRegen) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        Write-Host "==> regenerating icon (tools/make_ico.py)"
        & python (Join-Path $Root "tools\make_ico.py") `
            (Join-Path $Root "assets\icon-source.png") `
            (Join-Path $Root "assets\AppIcon.ico")
        if ($LASTEXITCODE -ne 0) { Write-Warning "icon regen failed, keeping existing .ico" }
    } else {
        Write-Host "    python not found - using the prebuilt assets/AppIcon.ico"
    }
}

# ---------------------------------------------------------------- 1) dotnet

function Get-DotNetExe {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnet) {
        $version = & dotnet --version 2>$null
        if ($version -and $version.StartsWith("8.")) { return (Get-Command dotnet).Source }
        if ($version -and $version -match '^(\d+)\.') {
            if ([int]$Matches[1] -ge 8) { return (Get-Command dotnet).Source }
        }
    }

    Write-Host "==> .NET SDK 8 not found, installing..." -ForegroundColor Yellow

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id Microsoft.DotNet.SDK.8 -e --silent `
            --accept-source-agreements --accept-package-agreements
        # refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dotnet) { return $dotnet.Source }
    }

    # Fallback: per-user install, no admin rights needed.
    $localDotnet = Join-Path $Root ".dotnet"
    $installScript = Join-Path $env:TEMP "dotnet-install.ps1"
    Write-Host "==> downloading dotnet-install script"
    Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $installScript -UseBasicParsing
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -Channel 8.0 -InstallDir $localDotnet
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install the .NET SDK 8. Please install it from https://dotnet.microsoft.com/download/dotnet/8.0 and re-run."
    }
    return (Join-Path $localDotnet "dotnet.exe")
}

$dotnet = Get-DotNetExe
Write-Host "==> using dotnet: $dotnet"
& $dotnet --version

# ---------------------------------------------------------------- 2) publish

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$publishDir = Join-Path $BuildDir "publish"

Write-Host "==> publishing (self-contained single file, win-x64)"
& $dotnet publish (Join-Path $Root "src\ScheutieOS.csproj") `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=none `
    -p:DebugSymbols=false `
    -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

$appExe = Join-Path $publishDir "ScheutieOS.exe"
if (-not (Test-Path $appExe)) { throw "publish output missing: $appExe" }

# ---------------------------------------------------------------- 3) package

# Read the version straight out of the csproj so the name stays in sync.
$csproj = Get-Content (Join-Path $Root "src\ScheutieOS.csproj") -Raw
$version = "8.4.1"
if ($csproj -match '<FileVersion>([^<]+)</FileVersion>') { $version = $Matches[1] }

$setupExe = Join-Path $BuildDir ("ScheutieOS-{0}-Setup.exe" -f $version)
Copy-Item $appExe $setupExe -Force

$sizeMb = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)
Write-Host ""
Write-Host "==> done: $setupExe  ($sizeMb MB)" -ForegroundColor Green
Write-Host ""
Write-Host "Usage on Windows:"
Write-Host "  1. copy the exe to the Windows machine"
Write-Host "  2. double-click it  -> install window -> 'install' -> app starts"
Write-Host "  silent install:     .\ScheutieOS-$version-Setup.exe --install --silent"
Write-Host "  run without install: .\ScheutieOS-$version-Setup.exe --app"
Write-Host "  uninstall:          installed app -> Help menu -> 'Uninstall ScheutieOS…'"
Write-Host ""
