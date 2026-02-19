# =============================================================================
# MimikaStudio - Windows Installer Build Script
# =============================================================================
# Builds the complete installer:
#   1. Flutter Windows app
#   2. Python backend (PyInstaller)
#   3. Inno Setup installer (.exe)
#
# Prerequisites:
#   - Flutter SDK (for Windows desktop build)
#   - Python venv at .\venv with all dependencies
#   - PyInstaller (pip install pyinstaller)
#   - Inno Setup 6 (https://jrsoftware.org/isinfo.php)
#
# Usage:
#   .\scripts\build_installer.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# Resolve the script's absolute path first, then go up to the repo root
$ScriptPath = $MyInvocation.MyCommand.Path
if (-not $ScriptPath) {
    # Fallback: assume we're running from the repo root
    $ScriptPath = Join-Path (Get-Location).Path "scripts\build_installer.ps1"
}
$ScriptPath = (Resolve-Path $ScriptPath).Path
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptPath)
$BackendDir = Join-Path $RootDir "backend"
$FlutterDir = Join-Path $RootDir "flutter_app"
$ScriptsDir = Join-Path $RootDir "scripts"
$VenvDir = Join-Path $RootDir "venv"
$DistDir = Join-Path $RootDir "dist"
$BuildDir = Join-Path $RootDir "build"
$Python = Join-Path $VenvDir "Scripts\python.exe"
$PyInstaller = Join-Path $VenvDir "Scripts\pyinstaller.exe"

# Inno Setup compiler - check common locations
$InnoSetup = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-Host ""
Write-Host "=== MimikaStudio Installer Build ===" -ForegroundColor Cyan
Write-Host "  Root: $RootDir" -ForegroundColor DarkGray
Write-Host ""

# =============================================================================
# 1. Validate prerequisites
# =============================================================================
Write-Host "[1/4] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-Path $Python)) {
    Write-Host "[ERROR] Python venv not found at $VenvDir" -ForegroundColor Red
    Write-Host "        Run install.bat first." -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Python venv found"

# Ensure PyInstaller is installed
if (-not (Test-Path $PyInstaller)) {
    Write-Host "  Installing PyInstaller..."
    & $Python -m pip install pyinstaller --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install PyInstaller" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  [OK] PyInstaller available"

$FlutterAvailable = $null
try {
    $FlutterAvailable = Get-Command flutter -ErrorAction SilentlyContinue
} catch {}

if (-not $FlutterAvailable) {
    Write-Host "[WARN] Flutter not found - will skip Windows UI build" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] Flutter available"
}

if (-not $InnoSetup) {
    Write-Host "[WARN] Inno Setup 6 not found - will skip installer generation" -ForegroundColor Yellow
    Write-Host "        Install from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] Inno Setup found at $InnoSetup"
}

# =============================================================================
# 2. Build Flutter Windows app
# =============================================================================
Write-Host ""
Write-Host "[2/4] Building Flutter Windows app..." -ForegroundColor Yellow

if ($FlutterAvailable) {
    Push-Location $FlutterDir
    try {
        flutter pub get
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Flutter Windows build failed" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Flutter Windows build complete"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [SKIP] Flutter not available"
}

# =============================================================================
# 3. Package Python backend with PyInstaller
# =============================================================================
Write-Host ""
Write-Host "[3/4] Packaging Python backend with PyInstaller..." -ForegroundColor Yellow

$SpecFile = Join-Path $ScriptsDir "mimikastudio.spec"

if (Test-Path $SpecFile) {
    & $PyInstaller $SpecFile --noconfirm --distpath $DistDir --workpath $BuildDir
} else {
    # Fallback: build from main.py directly
    & $PyInstaller `
        --name "MimikaStudio" `
        --noconfirm `
        --distpath $DistDir `
        --workpath $BuildDir `
        --add-data "$BackendDir\data;data" `
        --add-data "$BackendDir\tts;tts" `
        --add-data "$BackendDir\llm;llm" `
        --add-data "$BackendDir\models;models" `
        --add-data "$BackendDir\language;language" `
        --hidden-import "kokoro" `
        --hidden-import "qwen_tts" `
        --hidden-import "chatterbox" `
        --hidden-import "indextts" `
        --hidden-import "transformers" `
        --hidden-import "soundfile" `
        --hidden-import "librosa" `
        --hidden-import "scipy" `
        --hidden-import "omegaconf" `
        --hidden-import "uvicorn" `
        --hidden-import "uvicorn.logging" `
        --hidden-import "uvicorn.loops" `
        --hidden-import "uvicorn.loops.auto" `
        --hidden-import "uvicorn.protocols" `
        --hidden-import "uvicorn.protocols.http" `
        --hidden-import "uvicorn.protocols.http.auto" `
        --hidden-import "uvicorn.protocols.websockets" `
        --hidden-import "uvicorn.protocols.websockets.auto" `
        --hidden-import "uvicorn.lifespan" `
        --hidden-import "uvicorn.lifespan.on" `
        "$BackendDir\main.py"
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] PyInstaller build failed" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] PyInstaller build complete"

# Copy Flutter Windows build into dist
$FlutterBuildDir = Join-Path $FlutterDir "build\windows\x64\runner\Release"
$DistUiDir = Join-Path $DistDir "MimikaStudio\flutter_windows"

if (Test-Path $FlutterBuildDir) {
    Write-Host "  Copying Flutter Windows build to dist..."
    if (Test-Path $DistUiDir) {
        Remove-Item -Recurse -Force $DistUiDir
    }
    Copy-Item -Recurse $FlutterBuildDir $DistUiDir
    Write-Host "  [OK] Flutter Windows files copied"
} else {
    Write-Host "  [SKIP] No Flutter Windows build found"
}

# =============================================================================
# 4. Build Inno Setup installer
# =============================================================================
Write-Host ""
Write-Host "[4/4] Building Inno Setup installer..." -ForegroundColor Yellow

if ($InnoSetup) {
    $IssFile = Join-Path $ScriptsDir "mimikastudio.iss"
    if (Test-Path $IssFile) {
        & $InnoSetup $IssFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Inno Setup build failed" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Installer built successfully"
    } else {
        Write-Host "  [ERROR] mimikastudio.iss not found at $IssFile" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [SKIP] Inno Setup not available"
}

# =============================================================================
# Done
# =============================================================================
Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host ""

$DistMimikaDir = Join-Path $DistDir "MimikaStudio"
if (Test-Path $DistMimikaDir) {
    $size = (Get-ChildItem -Recurse $DistMimikaDir | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host "  PyInstaller output: $DistMimikaDir ($([math]::Round($size, 1)) MB)"
}

$InstallerExe = Join-Path $RootDir "Output\MimikaStudio_Setup.exe"
if (Test-Path $InstallerExe) {
    $exeSize = (Get-Item $InstallerExe).Length / 1MB
    Write-Host "  Installer: $InstallerExe ($([math]::Round($exeSize, 1)) MB)"
}

Write-Host ""
