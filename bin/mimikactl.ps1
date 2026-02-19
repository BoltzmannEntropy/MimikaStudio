#Requires -Version 5.1
<#
.SYNOPSIS
    MimikaStudio Control Script (Windows)
    Local-first voice cloning with Qwen3-TTS

.DESCRIPTION
    PowerShell port of bin/mimikactl for Windows service orchestration.

.EXAMPLE
    .\bin\mimikactl.ps1 up
    .\bin\mimikactl.ps1 status
    .\bin\mimikactl.ps1 down
#>

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$SubCommand,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============== Paths ==============

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$BackendDir = Join-Path $RootDir "backend"
$FlutterDir = Join-Path $RootDir "flutter_app"
$PidDir = Join-Path $RootDir ".pids"
$LogDir = Join-Path $RootDir ".logs"
$RunsLogDir = Join-Path (Join-Path $RootDir "runs") "logs"

# Locate venv: prefer root-level (install.sh), fall back to backend\venv
if (Test-Path (Join-Path $RootDir "venv")) {
    $VenvDir = Join-Path $RootDir "venv"
} elseif (Test-Path (Join-Path $BackendDir "venv")) {
    $VenvDir = Join-Path $BackendDir "venv"
} else {
    $VenvDir = Join-Path $RootDir "venv"  # default target for auto-creation
}

# Ports
$BackendPort = if ($env:MIMIKA_BACKEND_PORT) { [int]$env:MIMIKA_BACKEND_PORT } else { 7693 }
$McpPort = if ($env:MIMIKA_MCP_PORT) { [int]$env:MIMIKA_MCP_PORT } else { 8010 }

# Flutter
$FlutterAppName = "mimika_studio"

# Ensure directories exist
foreach ($dir in @($PidDir, $LogDir, $RunsLogDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ============== Resolve Python ==============

function Get-VenvPython {
    $candidates = @(
        (Join-Path (Join-Path $VenvDir "Scripts") "python.exe"),
        (Join-Path (Join-Path $VenvDir "bin") "python.exe"),
        (Join-Path (Join-Path $VenvDir "bin") "python")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    # Fallback to system python
    $sys = Get-Command python -ErrorAction SilentlyContinue
    if ($sys) { return $sys.Source }
    $sys3 = Get-Command python3 -ErrorAction SilentlyContinue
    if ($sys3) { return $sys3.Source }
    Write-Host "Python not found. Install Python 3.10+ and try again." -ForegroundColor Red
    exit 1
}

function Get-VenvPip {
    $candidates = @(
        (Join-Path (Join-Path $VenvDir "Scripts") "pip.exe"),
        (Join-Path (Join-Path $VenvDir "bin") "pip.exe"),
        (Join-Path (Join-Path $VenvDir "bin") "pip")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ============== Resolve Flutter ==============

function Get-FlutterExe {
    $fl = Get-Command flutter -ErrorAction SilentlyContinue
    if ($fl) { return $fl.Source }
    # Check common install locations
    $candidates = @(
        "C:\flutter\bin\flutter.bat",
        (Join-Path $env:USERPROFILE "flutter\bin\flutter.bat"),
        (Join-Path $env:LOCALAPPDATA "flutter\bin\flutter.bat")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

# ============== Helper Functions ==============

function Write-Status {
    param(
        [string]$Name,
        [int]$Port
    )

    $listening = $false
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($connections) { $listening = $true }
    } catch {}

    if ($listening) {
        $procId = ($connections | Select-Object -First 1).OwningProcess
        Write-Host "$([char]0x25CF) " -ForegroundColor Green -NoNewline
        Write-Host "${Name}: " -NoNewline
        Write-Host "RUNNING" -ForegroundColor Green -NoNewline
        Write-Host " [PID: $procId, Port: $Port]"
    } else {
        Write-Host "$([char]0x25CB) " -ForegroundColor Red -NoNewline
        Write-Host "${Name}: " -NoNewline
        Write-Host "STOPPED" -ForegroundColor Red
    }
}

function Stop-Port {
    param([int]$Port)

    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($connections) {
            $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            foreach ($p in $pids) {
                if ($p -and $p -ne 0) {
                    Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Seconds 1
        }
    } catch {}
}

function Wait-ForHealth {
    param(
        [string]$Url,
        [int]$MaxRetries = 60
    )

    Write-Host "Waiting for $Url " -NoNewline
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $null = $wc.DownloadString($Url)
            $wc.Dispose()
            Write-Host " OK" -ForegroundColor Green
            return $true
        } catch {
            # Connection refused or timeout — server not ready yet, keep retrying
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host " FAILED" -ForegroundColor Red
    return $false
}

function Save-Pid {
    param(
        [string]$Name,
        [int]$ProcessId
    )
    $pidFile = Join-Path $PidDir "$Name.pid"
    Set-Content -Path $pidFile -Value $ProcessId -NoNewline
}

function Remove-PidFile {
    param([string]$Name)
    $pidFile = Join-Path $PidDir "$Name.pid"
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-SavedPid {
    param([string]$Name)
    $pidFile = Join-Path $PidDir "$Name.pid"
    if (Test-Path $pidFile) {
        $content = (Get-Content $pidFile -ErrorAction SilentlyContinue).Trim()
        if ($content -match '^\d+$') {
            return [int]$content
        }
    }
    return $null
}

# ============== Backend Functions ==============

function Start-Backend {
    Write-Host "Starting backend..." -ForegroundColor Blue

    # Kill existing
    Stop-Port $BackendPort

    $python = Get-VenvPython

    # Check for venv — create if missing
    if (-not (Test-Path $VenvDir)) {
        Write-Host "Creating Python virtual environment..."
        & python -m venv $VenvDir
        $python = Get-VenvPython
        $pip = Get-VenvPip
        & $pip install -r (Join-Path $RootDir "requirements.txt")
    }

    # Ensure backend deps match pinned versions (notably transformers)
    $checkScript = Join-Path $PidDir "_check.py"
    Set-Content -Path $checkScript -Value @'
import sys
try:
    from packaging.version import Version
    import transformers
    sys.exit(0 if Version(transformers.__version__) == Version("4.57.3") else 1)
except Exception:
    sys.exit(1)
'@
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & $python $checkScript 2>$null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installing/updating requirements..."
        $pip = Get-VenvPip
        if ($pip) {
            & $pip install -r (Join-Path $RootDir "requirements.txt")
        }
    }
    Remove-Item $checkScript -Force -ErrorAction SilentlyContinue

    # Check chatterbox
    Set-Content -Path $checkScript -Value @'
import sys
try:
    import chatterbox
    sys.exit(0)
except Exception:
    sys.exit(1)
'@
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & $python $checkScript 2>$null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        $pip = Get-VenvPip
        if ($pip) {
            & $pip install --no-deps chatterbox-tts==0.1.6
        }
    }
    Remove-Item $checkScript -Force -ErrorAction SilentlyContinue

    # Start FastAPI
    $backendLog = Join-Path $LogDir "backend.log"
    $proc = Start-Process -FilePath $python `
        -ArgumentList "main.py" `
        -WorkingDirectory $BackendDir `
        -RedirectStandardOutput $backendLog `
        -RedirectStandardError (Join-Path $LogDir "backend_err.log") `
        -NoNewWindow `
        -PassThru

    Save-Pid "backend" $proc.Id

    $null = Wait-ForHealth "http://localhost:$BackendPort/api/health"
}

function Stop-Backend {
    Write-Host "Stopping backend..." -ForegroundColor Blue
    Stop-Port $BackendPort
    Remove-PidFile "backend"
    Write-Host "Backend stopped" -ForegroundColor Green
}

# ============== Flutter Functions ==============

function Start-Flutter {
    param(
        [string]$Mode = "dev"
    )

    $flutter = Get-FlutterExe
    if (-not $flutter) {
        Write-Host "Flutter not found - skipping Flutter UI." -ForegroundColor Yellow
        Write-Host "Install Flutter: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
        return
    }

    Write-Host "Starting Flutter UI (Windows, $Mode mode)..." -ForegroundColor Blue

    $runArgs = @("run", "-d", "windows")
    if ($Mode -eq "release") {
        $runArgs += "--release"
    }

    Push-Location $FlutterDir
    try {
        $flutterLog = Join-Path $LogDir "flutter.log"
        $proc = Start-Process -FilePath $flutter `
            -ArgumentList $runArgs `
            -WorkingDirectory $FlutterDir `
            -RedirectStandardOutput $flutterLog `
            -RedirectStandardError (Join-Path $LogDir "flutter_err.log") `
            -NoNewWindow `
            -PassThru

        Save-Pid "flutter" $proc.Id
    } finally {
        Pop-Location
    }
}

function Stop-Flutter {
    Write-Host "Stopping Flutter UI..." -ForegroundColor Blue

    # Kill by PID file
    $flutterPid = Get-SavedPid "flutter"
    if ($flutterPid) {
        Stop-Process -Id $flutterPid -Force -ErrorAction SilentlyContinue
        Remove-PidFile "flutter"
    }

    Write-Host "Flutter stopped" -ForegroundColor Green
}

function Build-Flutter {
    $flutter = Get-FlutterExe
    if (-not $flutter) {
        Write-Host "Flutter not found. Install Flutter first." -ForegroundColor Red
        return
    }
    Write-Host "Building Flutter app..." -ForegroundColor Blue
    Push-Location $FlutterDir
    try {
        & $flutter pub get
        & $flutter build windows --release
    } finally {
        Pop-Location
    }
    Write-Host "Build complete" -ForegroundColor Green
}

# ============== MCP Functions ==============

function Start-Mcp {
    Write-Host "Starting MCP Server..." -ForegroundColor Blue

    # Kill existing
    Stop-Port $McpPort

    $python = Get-VenvPython
    $mcpScript = Join-Path $ScriptDir "tts_mcp_server.py"
    $mcpLog = Join-Path $RunsLogDir "mcp_server.log"

    $proc = Start-Process -FilePath $python `
        -ArgumentList "`"$mcpScript`"", "--host", "127.0.0.1", "--port", $McpPort `
        -WorkingDirectory $RootDir `
        -RedirectStandardOutput $mcpLog `
        -RedirectStandardError (Join-Path $RunsLogDir "mcp_server_err.log") `
        -NoNewWindow `
        -PassThru

    Save-Pid "mcp" $proc.Id

    Start-Sleep -Seconds 1

    $listening = $false
    try {
        $conn = Get-NetTCPConnection -LocalPort $McpPort -State Listen -ErrorAction SilentlyContinue
        if ($conn) { $listening = $true }
    } catch {}

    if ($listening) {
        Write-Host "MCP Server started on port $McpPort" -ForegroundColor Green
    } else {
        Write-Host "MCP Server failed to start" -ForegroundColor Red
        if (Test-Path $mcpLog) {
            Get-Content $mcpLog -Tail 5
        }
    }
}

function Stop-Mcp {
    Write-Host "Stopping MCP Server..." -ForegroundColor Blue
    Stop-Port $McpPort
    Remove-PidFile "mcp"
    Write-Host "MCP Server stopped" -ForegroundColor Green
}

# ============== Model Functions ==============

function Invoke-DownloadModels {
    Write-Host "Downloading models..." -ForegroundColor Blue
    $python = Get-VenvPython

    $downloadScript = Join-Path $PidDir "_download.py"
    Set-Content -Path $downloadScript -Value @'
from tts.kokoro_engine import get_kokoro_engine
print('Loading Kokoro model...')
get_kokoro_engine().load_model()
print('All models loaded.')
'@
    & $python $downloadScript
    Remove-Item $downloadScript -Force -ErrorAction SilentlyContinue
    Write-Host "Models ready" -ForegroundColor Green
}

# ============== Database Functions ==============

function Invoke-SeedDb {
    Write-Host "Seeding database..." -ForegroundColor Blue
    $python = Get-VenvPython
    Push-Location $BackendDir
    try {
        & $python database.py
    } finally {
        Pop-Location
    }
    Write-Host "Database seeded" -ForegroundColor Green
}

# ============== Test Functions ==============

function Invoke-RunTests {
    Write-Host "Running API tests..." -ForegroundColor Blue
    $python = Get-VenvPython
    & $python (Join-Path (Join-Path $RootDir "scripts") "test_api.py")
}

# ============== Main Commands ==============

function Invoke-Up {
    param([string[]]$Args)

    $skipFlutter = $false
    $skipMcp = $false
    $flutterMode = "dev"

    foreach ($a in $Args) {
        switch ($a) {
            "--no-flutter"       { $skipFlutter = $true }
            "--no-mcp"           { $skipMcp = $true }
            "--flutter-release"  { $flutterMode = "release" }
            default              { Write-Host "Unknown option: $a" -ForegroundColor Yellow }
        }
    }

    Write-Host "=== Starting MimikaStudio ===" -ForegroundColor Blue
    Start-Backend

    if (-not $skipMcp) {
        Start-Mcp
    }

    if (-not $skipFlutter) {
        Start-Flutter -Mode $flutterMode
    }

    Write-Host ""
    Write-Host "=== MimikaStudio Ready ===" -ForegroundColor Green
    Write-Host "Backend:    http://localhost:$BackendPort"
    Write-Host "API Docs:   http://localhost:$BackendPort/docs"
    Write-Host "MCP Server: http://localhost:$McpPort"
}

function Invoke-Down {
    Write-Host "=== Stopping MimikaStudio ===" -ForegroundColor Blue
    Stop-Flutter
    Stop-Mcp
    Stop-Backend
    Write-Host "=== MimikaStudio Stopped ===" -ForegroundColor Green
}

function Invoke-Status {
    Write-Host "=== MimikaStudio Status ===" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Services:" -ForegroundColor Green
    Write-Status "Backend" $BackendPort
    Write-Status "MCP Server" $McpPort

    # Flutter status (check by PID)
    $flutterRunning = $false
    $flutterPid = Get-SavedPid "flutter"
    if ($flutterPid) {
        $proc = Get-Process -Id $flutterPid -ErrorAction SilentlyContinue
        if ($proc) {
            $flutterRunning = $true
            Write-Host "$([char]0x25CF) " -ForegroundColor Green -NoNewline
            Write-Host "Flutter UI: " -NoNewline
            Write-Host "RUNNING" -ForegroundColor Green -NoNewline
            Write-Host " [PID: $flutterPid]"
        }
    }
    if (-not $flutterRunning) {
        Write-Host "$([char]0x25CB) " -ForegroundColor Red -NoNewline
        Write-Host "Flutter UI: " -NoNewline
        Write-Host "STOPPED" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Logs:" -ForegroundColor Green
    Write-Host "  mimikactl.ps1 logs backend   - Backend logs"
    Write-Host "  mimikactl.ps1 logs mcp       - MCP server logs"
    Write-Host "  mimikactl.ps1 logs flutter   - Flutter logs"
    Write-Host "  mimikactl.ps1 logs all       - Tail all logs"
}

function Invoke-Restart {
    param([string[]]$Args)
    Invoke-Down
    Start-Sleep -Seconds 2
    Invoke-Up -Args $Args
}

function Invoke-Logs {
    param([string]$Target = "backend")

    $logFile = $null

    switch ($Target) {
        "backend" { $logFile = Join-Path $LogDir "backend.log" }
        "mcp"     { $logFile = Join-Path $RunsLogDir "mcp_server.log" }
        "flutter" { $logFile = Join-Path $LogDir "flutter.log" }
        "all" {
            Write-Host "Tailing all logs (Ctrl+C to exit)..."
            $allLogs = @()
            if (Test-Path $LogDir) {
                $allLogs += Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue
            }
            if (Test-Path $RunsLogDir) {
                $allLogs += Get-ChildItem -Path $RunsLogDir -Filter "*.log" -ErrorAction SilentlyContinue
            }
            if ($allLogs.Count -eq 0) {
                Write-Host "No log files found."
                return
            }
            foreach ($lf in $allLogs) {
                Write-Host "==> $($lf.FullName) <==" -ForegroundColor Cyan
                if (Test-Path $lf.FullName) {
                    Get-Content $lf.FullName -Tail 20
                }
                Write-Host ""
            }
            return
        }
        default {
            $logFile = Join-Path $LogDir "$Target.log"
            if (-not (Test-Path $logFile)) {
                $logFile = Join-Path $RunsLogDir "$Target.log"
            }
        }
    }

    if ($logFile -and (Test-Path $logFile)) {
        Write-Host "Tailing $logFile (Ctrl+C to exit)..."
        Get-Content $logFile -Tail 50 -Wait
    } else {
        Write-Host "Log file not found: $logFile"
        Write-Host "Available logs:"
        $found = $false
        foreach ($dir in @($LogDir, $RunsLogDir)) {
            if (Test-Path $dir) {
                $logs = Get-ChildItem -Path $dir -Filter "*.log" -ErrorAction SilentlyContinue
                foreach ($l in $logs) {
                    Write-Host "  $($l.FullName)"
                    $found = $true
                }
            }
        }
        if (-not $found) {
            Write-Host "  (none)"
        }
    }
}

function Invoke-FlutterStart {
    param([string[]]$Args)

    $mode = "dev"

    foreach ($a in $Args) {
        switch ($a) {
            "--dev"     { $mode = "dev" }
            "--release" { $mode = "release" }
            default     { Write-Host "Unknown option: $a" -ForegroundColor Yellow }
        }
    }

    Start-Flutter -Mode $mode
}

function Show-Version {
    Write-Host "MimikaStudio - Text-to-Speech UI" -ForegroundColor Blue
    Write-Host "Version: 1.0.0"
    Write-Host "Root: $RootDir"
    Write-Host ""
    Write-Host "Components:"
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $pyVer = & python --version 2>&1
        Write-Host "  Python: $pyVer"
    }
    $flutter = Get-FlutterExe
    if ($flutter) {
        $flVer = & $flutter --version 2>&1 | Select-Object -First 1
        Write-Host "  Flutter: $flVer"
    }
}

function Show-Usage {
    Write-Host "MimikaStudio Control Script (Windows)" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\bin\mimikactl.ps1 <command> [options]"
    Write-Host ""
    Write-Host "Service Commands:" -ForegroundColor Green
    Write-Host "    up [options]                Start all services (Backend + MCP + Flutter)"
    Write-Host "        --no-flutter            Skip Flutter UI"
    Write-Host "        --no-mcp                Skip MCP server"
    Write-Host "        --flutter-release       Run Flutter in release mode (default: dev)"
    Write-Host "    down                        Stop all services"
    Write-Host "    restart                     Restart all services"
    Write-Host "    status                      Show service status"
    Write-Host ""
    Write-Host "Backend Commands:" -ForegroundColor Green
    Write-Host "    backend start               Start backend only"
    Write-Host "    backend stop                Stop backend"
    Write-Host ""
    Write-Host "Flutter Commands:" -ForegroundColor Green
    Write-Host "    flutter start [--dev|--release] Start Flutter UI (Windows desktop)"
    Write-Host "    flutter stop                    Stop Flutter UI"
    Write-Host "    flutter build                   Build Flutter Windows app"
    Write-Host ""
    Write-Host "MCP Server Commands:" -ForegroundColor Green
    Write-Host "    mcp start                   Start MCP server (for Codex CLI)"
    Write-Host "    mcp stop                    Stop MCP server"
    Write-Host "    mcp status                  Check MCP server status"
    Write-Host ""
    Write-Host "Model Commands:" -ForegroundColor Green
    Write-Host "    models download             Pre-download ML models"
    Write-Host ""
    Write-Host "Database Commands:" -ForegroundColor Green
    Write-Host "    db seed                     Seed database"
    Write-Host ""
    Write-Host "Utility Commands:" -ForegroundColor Green
    Write-Host "    logs [service]              Tail logs (backend|mcp|flutter|all)"
    Write-Host "    test                        Run API tests"
    Write-Host "    clean                       Clean logs and temp files"
    Write-Host "    version                     Show version info"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Green
    Write-Host "    .\bin\mimikactl.ps1 up                   # Start everything"
    Write-Host "    .\bin\mimikactl.ps1 up --no-flutter      # Backend + MCP only"
    Write-Host "    .\bin\mimikactl.ps1 status               # Check what's running"
    Write-Host "    .\bin\mimikactl.ps1 logs backend         # Tail backend logs"
    Write-Host "    .\bin\mimikactl.ps1 mcp start            # Start MCP for Codex CLI"
}

# ============== Main Dispatch ==============

# For commands without subcommands, fold $SubCommand into $ExtraArgs
$AllArgs = @()
if ($SubCommand) { $AllArgs += $SubCommand }
if ($ExtraArgs) { $AllArgs += $ExtraArgs }

switch ($Command) {
    "up" {
        Invoke-Up -Args $AllArgs
    }
    "down" {
        Invoke-Down
    }
    "restart" {
        Invoke-Restart -Args $AllArgs
    }
    "status" {
        Invoke-Status
    }
    "backend" {
        switch ($SubCommand) {
            "start" { Start-Backend }
            "stop"  { Stop-Backend }
            default { Write-Host "Usage: mimikactl.ps1 backend {start|stop}" }
        }
    }
    "flutter" {
        switch ($SubCommand) {
            "start" { Invoke-FlutterStart -Args $ExtraArgs }
            "stop"  { Stop-Flutter }
            "build" { Build-Flutter }
            default { Write-Host "Usage: mimikactl.ps1 flutter {start|stop|build}" }
        }
    }
    "mcp" {
        switch ($SubCommand) {
            "start" { Start-Mcp }
            "stop"  { Stop-Mcp }
            "status" {
                Write-Host "MCP Server Status:" -ForegroundColor Blue
                Write-Status "MCP Server" $McpPort
            }
            default { Write-Host "Usage: mimikactl.ps1 mcp {start|stop|status}" }
        }
    }
    "models" {
        switch ($SubCommand) {
            "download" { Invoke-DownloadModels }
            default    { Write-Host "Usage: mimikactl.ps1 models download" }
        }
    }
    "db" {
        switch ($SubCommand) {
            "seed"  { Invoke-SeedDb }
            default { Write-Host "Usage: mimikactl.ps1 db seed" }
        }
    }
    "logs" {
        $logTarget = if ($SubCommand) { $SubCommand } else { "backend" }
        Invoke-Logs -Target $logTarget
    }
    "test" {
        Invoke-RunTests
    }
    "clean" {
        Write-Host "Cleaning temporary files..." -ForegroundColor Blue
        foreach ($pattern in @(
            (Join-Path $LogDir "*.log"),
            (Join-Path $RunsLogDir "*.log"),
            (Join-Path $PidDir "*.pid")
        )) {
            Remove-Item $pattern -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Cleaned." -ForegroundColor Green
    }
    "version" {
        Show-Version
    }
    "generate" {
        switch ($SubCommand) {
            "emma-audio" {
                Write-Host "Generating Emma IPA audio..." -ForegroundColor Blue
                $python = Get-VenvPython
                & $python (Join-Path (Join-Path $BackendDir "scripts") "generate_emma_ipa_audio.py")
                Write-Host "Audio generated" -ForegroundColor Green
            }
            default { Write-Host "Usage: mimikactl.ps1 generate {emma-audio}" }
        }
    }
    { $_ -in "help", "-h", "--help", "" } {
        Show-Usage
    }
    default {
        Show-Usage
    }
}
