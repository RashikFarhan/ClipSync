<#
.SYNOPSIS
ClipSync Autonomous Build Pipeline
.DESCRIPTION
Cleans workspace, structures a neat "Releases/vX.X" directory hierarchy,
compiles Android split APKs, and generates a single Windows Setup EXE.
#>

param (
    [string]$Version = "1"
)

$ErrorActionPreference = "Stop"

try {
    $ReleaseDir = "Releases\Beta_v$Version"
    $AndroidDir = "$ReleaseDir\Android"
    $WindowsDir = "$ReleaseDir\Windows"

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   ClipSync Build Automator: v$Version (Beta)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # 1. Clean & Organize
    Write-Host "`n[1/5] Structuring Folders & Cleaning Workspace..." -ForegroundColor Yellow
    if (Test-Path "Builds") { Remove-Item "Builds" -Recurse -Force -ErrorAction SilentlyContinue }

    if (-not (Test-Path $AndroidDir)) { New-Item -ItemType Directory -Path $AndroidDir -Force | Out-Null }
    if (-not (Test-Path $WindowsDir)) { New-Item -ItemType Directory -Path $WindowsDir -Force | Out-Null }

    & flutter clean
    & flutter pub get

    # 2. Sanity Checks
    Write-Host "`n[2/5] Running Pre-flight Sanity Checks..." -ForegroundColor Yellow
    $AndroidManifest = "android\app\src\main\AndroidManifest.xml"
    if (-not (Test-Path $AndroidManifest)) { throw "Error: AndroidManifest.xml is missing!" }
    if ((Get-Content $AndroidManifest -Raw) -notmatch "android.permission.INTERNET") { throw "Error: INTERNET permission missing!" }
    Write-Host "Sanity Checks Passed!" -ForegroundColor Green

    # 3. Android Build
    Write-Host "`n[3/5] Compiling Android Release (Split APKs)..." -ForegroundColor Yellow
    & flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "Android build failed! Check output above." }

    Write-Host "Organizing Android Artifacts..." -ForegroundColor Green
    Copy-Item "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" -Destination "$AndroidDir\ClipSync_v${Version}_arm32.apk" -Force
    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" -Destination "$AndroidDir\ClipSync_v${Version}_arm64.apk" -Force
    Copy-Item "build\app\outputs\flutter-apk\app-x86_64-release.apk" -Destination "$AndroidDir\ClipSync_v${Version}_x64.apk" -Force

    # 4. Windows Build
    Write-Host "`n[4/5] Compiling Windows Production Binary..." -ForegroundColor Yellow
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed! Check your C++ bridge or flutter installation." }

    # 5. Windows EXE Installer Packing (Inno Setup)
    Write-Host "`n[5/5] Generating Background-Enabled Windows Installer..." -ForegroundColor Yellow

    $innoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $innoPath)) {
        Write-Host "Inno Setup missing! Downloading..."
        Invoke-WebRequest -Uri "https://jrsoftware.org/download.php/is.exe" -OutFile "$env:TEMP\inno_setup.exe"
        Start-Process -FilePath "$env:TEMP\inno_setup.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait -NoNewWindow
        if (-not (Test-Path $innoPath)) { throw "Failed to install Inno Setup. Please install manually to build the Windows target." }
    }

    Write-Host "Running Inno Setup compiler..."
    & $innoPath "/DAppVersion=$Version" "/O$WindowsDir" "installer\clipsync_installer.iss"
    if ($LASTEXITCODE -ne 0) { throw "Installer generation failed!" }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "       BUILD PIPELINE COMPLETE " -ForegroundColor Green
    Write-Host " Output located in: $ReleaseDir" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
catch {
    Write-Host "`n[BUILD ERROR] $_" -ForegroundColor Red
}
