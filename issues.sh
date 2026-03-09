#!/usr/bin/env bash
# =============================================================================
# MimikaStudio - Installation & Usage Diagnostic Script
# =============================================================================
# Runs install.sh with full logging, captures system info, and tests the API.
# For users experiencing installation or runtime issues.
#
# Usage: ./issues.sh
# Output: issues_report_<timestamp>.log
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$ROOT_DIR/issues_report_$TIMESTAMP.log"
BACKEND_DIR="$ROOT_DIR/backend"
PRIMARY_VENV_DIR="$ROOT_DIR/venv"
FALLBACK_VENV_DIR="$BACKEND_DIR/venv"
BACKEND_HOST="${MIMIKA_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${MIMIKA_BACKEND_PORT:-7693}"
BACKEND_URL="http://$BACKEND_HOST:$BACKEND_PORT"
VENV_DIR=""
VENV_PYTHON=""

# --- Colors (for terminal) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging helpers ---
log() {
    echo -e "$*" | tee -a "$LOG_FILE"
}

section() {
    log ""
    log "============================================================================="
    log "  $*"
    log "============================================================================="
}

subsection() {
    log ""
    log "--- $* ---"
}

run_cmd() {
    local desc="$1"
    shift
    log "$ $*"
    if output=$("$@" 2>&1); then
        log "$output"
        return 0
    else
        local exit_code=$?
        log "$output"
        log "${RED}[FAILED]${NC} $desc (exit code: $exit_code)"
        return $exit_code
    fi
}

resolve_venv_python() {
    local candidate
    for candidate in "$PRIMARY_VENV_DIR" "$FALLBACK_VENV_DIR"; do
        if [ -x "$candidate/bin/python" ] && "$candidate/bin/python" -c "import sys" >/dev/null 2>&1; then
            echo "$candidate/bin/python"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Start Report
# =============================================================================
echo "" > "$LOG_FILE"
log "${CYAN}MimikaStudio Installation & Usage Diagnostic Report${NC}"
log "Generated: $(date)"
log "Log file: $LOG_FILE"

if VENV_PYTHON="$(resolve_venv_python)"; then
    VENV_DIR="$(cd "$(dirname "$VENV_PYTHON")/.." && pwd)"
else
    VENV_DIR="$PRIMARY_VENV_DIR"
fi

# =============================================================================
# 1. System Information
# =============================================================================
section "SYSTEM INFORMATION"

subsection "macOS Version"
run_cmd "macOS version" sw_vers 2>/dev/null || log "Not macOS or sw_vers unavailable"

subsection "Kernel / OS"
run_cmd "Kernel" uname -a

subsection "Architecture"
run_cmd "Architecture" uname -m

subsection "Hardware Info"
if command -v system_profiler &> /dev/null; then
    log "$(system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Model|Chip|Memory|Cores' || echo 'Unable to get hardware info')"
else
    log "system_profiler not available"
fi

subsection "Disk Space"
run_cmd "Disk space" df -h "$ROOT_DIR"

subsection "Available Memory"
if command -v vm_stat &> /dev/null; then
    log "$(vm_stat 2>/dev/null | head -10 || echo 'Unable to get memory info')"
elif [ -f /proc/meminfo ]; then
    log "$(head -5 /proc/meminfo)"
else
    log "Memory info not available"
fi

# =============================================================================
# 2. Development Tools
# =============================================================================
section "DEVELOPMENT TOOLS"

subsection "Homebrew"
if command -v brew &> /dev/null; then
    run_cmd "Homebrew version" brew --version
    log ""
    log "Homebrew prefix: $(brew --prefix)"
else
    log "${RED}Homebrew NOT installed${NC}"
fi

subsection "Python (system)"
if command -v python3 &> /dev/null; then
    run_cmd "Python3 version" python3 --version
    run_cmd "Python3 path" which python3
else
    log "${RED}Python3 NOT found${NC}"
fi

subsection "pip (system)"
if command -v pip3 &> /dev/null; then
    run_cmd "pip3 version" pip3 --version
else
    log "pip3 not found in PATH"
fi

subsection "espeak-ng"
if command -v espeak-ng &> /dev/null; then
    run_cmd "espeak-ng version" espeak-ng --version
else
    log "${YELLOW}espeak-ng NOT installed (required by Kokoro TTS)${NC}"
fi

subsection "ffmpeg"
if command -v ffmpeg &> /dev/null; then
    log "$(ffmpeg -version 2>&1 | head -1)"
else
    log "${YELLOW}ffmpeg NOT installed (required for audio conversion)${NC}"
fi

subsection "Git"
if command -v git &> /dev/null; then
    run_cmd "Git version" git --version
else
    log "${RED}Git NOT found${NC}"
fi

subsection "Flutter"
if command -v flutter &> /dev/null; then
    run_cmd "Flutter version" flutter --version
else
    log "${YELLOW}Flutter NOT installed (optional, for desktop GUI)${NC}"
fi

# =============================================================================
# 3. Python Virtual Environment
# =============================================================================
section "PYTHON VIRTUAL ENVIRONMENT"

if [ -n "$VENV_PYTHON" ] && [ -d "$VENV_DIR" ]; then
    log "${GREEN}venv exists at $VENV_DIR${NC}"

    subsection "venv Python"
    run_cmd "venv Python version" "$VENV_PYTHON" --version
    run_cmd "venv Python path" "$VENV_PYTHON" -c "import sys; print(sys.executable)"

    subsection "venv pip"
    run_cmd "venv pip version" "$VENV_PYTHON" -m pip --version

    subsection "Installed Packages"
    log "Key packages:"
    for pkg in fastapi uvicorn torch torchaudio transformers kokoro qwen-tts chatterbox-tts indextts soundfile librosa spacy; do
        version=$("$VENV_PYTHON" -m pip show "$pkg" 2>/dev/null | grep "^Version:" | cut -d' ' -f2)
        if [ -n "$version" ]; then
            log "  ${GREEN}$pkg${NC}: $version"
        else
            log "  ${YELLOW}$pkg${NC}: NOT INSTALLED"
        fi
    done

    subsection "Import Tests"
    log "Testing critical Python imports..."
    "$VENV_PYTHON" -c "
import sys

modules = [
    ('fastapi', 'FastAPI web framework'),
    ('uvicorn', 'ASGI server'),
    ('torch', 'PyTorch'),
    ('torchaudio', 'Torch Audio'),
    ('transformers', 'HuggingFace Transformers'),
    ('kokoro', 'Kokoro TTS'),
    ('qwen_tts', 'Qwen TTS'),
    ('chatterbox', 'Chatterbox TTS'),
    ('indextts', 'IndexTTS-2'),
    ('soundfile', 'Sound file I/O'),
    ('librosa', 'Audio analysis'),
    ('spacy', 'NLP library'),
    ('dicta_onnx', 'Dicta Hebrew diacritizer'),
]

print('')
for mod, desc in modules:
    try:
        __import__(mod)
        print(f'  [OK] {mod} ({desc})')
    except ImportError as e:
        print(f'  [FAIL] {mod} ({desc}): {e}')
    except Exception as e:
        print(f'  [ERROR] {mod} ({desc}): {type(e).__name__}: {e}')
" 2>&1 | tee -a "$LOG_FILE"

else
    log "${RED}No usable venv found at $PRIMARY_VENV_DIR or $FALLBACK_VENV_DIR${NC}"
    log "Run ./install.sh first to create/repair the virtual environment"
fi

# =============================================================================
# 4. Project Files & Models
# =============================================================================
section "PROJECT FILES & MODELS"

subsection "Repository Structure"
log "Key directories:"
for dir in backend flutter_app venv bin models; do
    if [ -d "$ROOT_DIR/$dir" ]; then
        log "  ${GREEN}$dir/${NC} exists"
    else
        log "  ${YELLOW}$dir/${NC} missing"
    fi
done

subsection "Backend Files"
for file in main.py database.py requirements.txt; do
    if [ -f "$BACKEND_DIR/$file" ]; then
        log "  ${GREEN}$file${NC} exists"
    else
        log "  ${RED}$file${NC} MISSING"
    fi
done

subsection "Database"
if [ -f "$BACKEND_DIR/mimika.db" ]; then
    log "${GREEN}Database exists${NC}: $BACKEND_DIR/mimika.db"
    log "Size: $(du -h "$BACKEND_DIR/mimika.db" | cut -f1)"
else
    log "${YELLOW}Database not found${NC} (will be created on first run)"
fi

subsection "Dicta ONNX Model"
DICTA_MODEL="$BACKEND_DIR/models/dicta-onnx/dicta-1.0.onnx"
if [ -f "$DICTA_MODEL" ]; then
    log "${GREEN}Dicta model exists${NC}"
    log "Size: $(du -h "$DICTA_MODEL" | cut -f1)"
else
    log "${YELLOW}Dicta model NOT downloaded${NC} (Hebrew TTS will be limited)"
fi

# =============================================================================
# 5. Run Installation Script
# =============================================================================
section "RUNNING INSTALL.SH"

log "Starting install.sh with full output capture..."
log ""

if [ -f "$ROOT_DIR/install.sh" ]; then
    # Run install.sh and capture output (without set -e to continue on errors)
    bash -x "$ROOT_DIR/install.sh" 2>&1 | while IFS= read -r line; do
        echo "$line" | tee -a "$LOG_FILE"
    done
    INSTALL_EXIT_CODE=${PIPESTATUS[0]}

    log ""
    if [ "$INSTALL_EXIT_CODE" -eq 0 ]; then
        log "${GREEN}install.sh completed successfully (exit code: 0)${NC}"
    else
        log "${RED}install.sh FAILED (exit code: $INSTALL_EXIT_CODE)${NC}"
    fi
else
    log "${RED}install.sh NOT FOUND at $ROOT_DIR/install.sh${NC}"
fi

# =============================================================================
# 6. API Tests
# =============================================================================
section "API TESTS"

TEST_BACKEND_PORT="$BACKEND_PORT"
TEST_BACKEND_URL="$BACKEND_URL"

# Check if Mimika backend is running
subsection "Checking for Running Backend"
health_probe=$(curl -s --connect-timeout 2 "$TEST_BACKEND_URL/api/health" 2>/dev/null || true)
if echo "$health_probe" | grep -q '"service":"mimikastudio"'; then
    log "${GREEN}Backend is already running on $TEST_BACKEND_URL${NC}"
    BACKEND_WAS_RUNNING=1
else
    if [ -n "$health_probe" ]; then
        log "${YELLOW}Port $BACKEND_PORT is occupied by a different service. Using fallback port 8769 for tests.${NC}"
        TEST_BACKEND_PORT=8769
        TEST_BACKEND_URL="http://127.0.0.1:$TEST_BACKEND_PORT"
    fi

    log "Backend not running. Starting backend for API tests on $TEST_BACKEND_URL..."
    BACKEND_WAS_RUNNING=0

    if [ -n "$VENV_PYTHON" ] && [ -f "$BACKEND_DIR/main.py" ]; then
        cd "$BACKEND_DIR"
        MIMIKA_BACKEND_HOST="127.0.0.1" \
        MIMIKA_BACKEND_PORT="$TEST_BACKEND_PORT" \
        "$VENV_PYTHON" -m uvicorn main:app --host 127.0.0.1 --port "$TEST_BACKEND_PORT" &
        BACKEND_PID=$!
        log "Started backend with PID: $BACKEND_PID"

        # Wait for backend to start
        log "Waiting for backend to be ready..."
        for i in {1..30}; do
            probe=$(curl -s --connect-timeout 1 "$TEST_BACKEND_URL/api/health" 2>/dev/null || true)
            if echo "$probe" | grep -q '"service":"mimikastudio"'; then
                log "${GREEN}Backend ready after ${i}s${NC}"
                break
            fi
            sleep 1
        done
    else
        log "${RED}Cannot start backend - missing usable venv or main.py${NC}"
    fi
fi

# Run API tests
subsection "Health Check"
log "$ curl $TEST_BACKEND_URL/api/health"
health_response=$(curl -s --connect-timeout 5 "$TEST_BACKEND_URL/api/health" 2>&1)
if [ $? -eq 0 ]; then
    log "${GREEN}Response:${NC} $health_response"
else
    log "${RED}FAILED:${NC} $health_response"
fi

subsection "System Info"
log "$ curl $TEST_BACKEND_URL/api/system/info"
sysinfo_response=$(curl -s --connect-timeout 5 "$TEST_BACKEND_URL/api/system/info" 2>&1)
if [ $? -eq 0 ]; then
    log "${GREEN}Response:${NC} $sysinfo_response"
else
    log "${RED}FAILED:${NC} $sysinfo_response"
fi

subsection "OpenAPI Docs"
log "$ curl $TEST_BACKEND_URL/openapi.json (checking availability)"
if curl -s --connect-timeout 5 "$TEST_BACKEND_URL/openapi.json" > /dev/null 2>&1; then
    log "${GREEN}OpenAPI docs available${NC}"
else
    log "${RED}OpenAPI docs NOT available${NC}"
fi

subsection "Kokoro TTS Voices"
log "$ curl $TEST_BACKEND_URL/api/kokoro/voices"
kokoro_response=$(curl -s --connect-timeout 10 "$TEST_BACKEND_URL/api/kokoro/voices" 2>&1)
if [ $? -eq 0 ]; then
    if [ ${#kokoro_response} -gt 500 ]; then
        log "${GREEN}Response (truncated):${NC} ${kokoro_response:0:500}..."
    else
        log "${GREEN}Response:${NC} $kokoro_response"
    fi
else
    log "${RED}FAILED:${NC} $kokoro_response"
fi

subsection "Qwen3 TTS Voices"
log "$ curl $TEST_BACKEND_URL/api/qwen3/voices"
qwen_response=$(curl -s --connect-timeout 10 "$TEST_BACKEND_URL/api/qwen3/voices" 2>&1)
if [ $? -eq 0 ]; then
    if [ ${#qwen_response} -gt 500 ]; then
        log "${GREEN}Response (truncated):${NC} ${qwen_response:0:500}..."
    else
        log "${GREEN}Response:${NC} $qwen_response"
    fi
else
    log "${RED}FAILED:${NC} $qwen_response"
fi

subsection "Chatterbox TTS Voices"
log "$ curl $TEST_BACKEND_URL/api/chatterbox/voices"
chatterbox_response=$(curl -s --connect-timeout 10 "$TEST_BACKEND_URL/api/chatterbox/voices" 2>&1)
if [ $? -eq 0 ]; then
    if [ ${#chatterbox_response} -gt 500 ]; then
        log "${GREEN}Response (truncated):${NC} ${chatterbox_response:0:500}..."
    else
        log "${GREEN}Response:${NC} $chatterbox_response"
    fi
else
    log "${RED}FAILED:${NC} $chatterbox_response"
fi

subsection "Custom Voices"
log "$ curl $TEST_BACKEND_URL/api/voices/custom"
custom_response=$(curl -s --connect-timeout 10 "$TEST_BACKEND_URL/api/voices/custom" 2>&1)
if [ $? -eq 0 ]; then
    if [ ${#custom_response} -gt 500 ]; then
        log "${GREEN}Response (truncated):${NC} ${custom_response:0:500}..."
    else
        log "${GREEN}Response:${NC} $custom_response"
    fi
else
    log "${RED}FAILED:${NC} $custom_response"
fi

# Stop backend if we started it
if [ "$BACKEND_WAS_RUNNING" -eq 0 ] && [ -n "${BACKEND_PID:-}" ]; then
    log ""
    log "Stopping test backend (PID: $BACKEND_PID)..."
    kill "$BACKEND_PID" 2>/dev/null || true
    wait "$BACKEND_PID" 2>/dev/null || true
    log "Backend stopped"
fi

# =============================================================================
# 7. Port Conflicts
# =============================================================================
section "PORT STATUS"

subsection "Port ${TEST_BACKEND_PORT:-$BACKEND_PORT} (Backend)"
if command -v lsof &> /dev/null; then
    port_backend=$(lsof -i :"${TEST_BACKEND_PORT:-$BACKEND_PORT}" 2>/dev/null | grep LISTEN || echo "Not in use")
    log "$port_backend"
else
    log "lsof not available"
fi

subsection "Port 5173 (Vite/Web UI)"
if command -v lsof &> /dev/null; then
    port_5173=$(lsof -i :5173 2>/dev/null | grep LISTEN || echo "Not in use")
    log "$port_5173"
fi

# =============================================================================
# 8. Runtime Logs
# =============================================================================
section "RUNTIME LOGS"

LOG_DIR="$ROOT_DIR/.logs"
RUNS_LOG_DIR="$ROOT_DIR/runs/logs"

subsection "Flutter Log"
FLUTTER_LOG="$LOG_DIR/flutter.log"
if [ -f "$FLUTTER_LOG" ]; then
    log "${GREEN}Flutter log exists${NC}: $FLUTTER_LOG"
    log "Last 50 lines:"
    log "----------------------------------------"
    tail -50 "$FLUTTER_LOG" 2>/dev/null | while IFS= read -r line; do
        log "$line"
    done
    log "----------------------------------------"
else
    log "${YELLOW}Flutter log not found${NC} (Flutter may not have been started yet)"
fi

subsection "Backend Log"
BACKEND_LOG="$LOG_DIR/backend.log"
if [ -f "$BACKEND_LOG" ]; then
    log "${GREEN}Backend log exists${NC}: $BACKEND_LOG"
    log "Last 50 lines:"
    log "----------------------------------------"
    tail -50 "$BACKEND_LOG" 2>/dev/null | while IFS= read -r line; do
        log "$line"
    done
    log "----------------------------------------"
else
    log "${YELLOW}Backend log not found${NC}"
fi

subsection "MCP Server Log"
MCP_LOG="$RUNS_LOG_DIR/mcp_server.log"
if [ -f "$MCP_LOG" ]; then
    log "${GREEN}MCP server log exists${NC}: $MCP_LOG"
    log "Last 50 lines:"
    log "----------------------------------------"
    tail -50 "$MCP_LOG" 2>/dev/null | while IFS= read -r line; do
        log "$line"
    done
    log "----------------------------------------"
else
    log "${YELLOW}MCP server log not found${NC}"
fi

# =============================================================================
# 9. Environment Variables
# =============================================================================
section "ENVIRONMENT VARIABLES"

log "Relevant environment variables:"
for var in PATH PYTHONPATH VIRTUAL_ENV HOMEBREW_PREFIX DYLD_LIBRARY_PATH; do
    val="${!var:-<not set>}"
    # Truncate long values
    if [ ${#val} -gt 200 ]; then
        log "  $var: ${val:0:200}..."
    else
        log "  $var: $val"
    fi
done

# =============================================================================
# 10. Summary
# =============================================================================
section "SUMMARY"

log ""
log "Diagnostic report saved to: ${CYAN}$LOG_FILE${NC}"
log ""
log "If you're experiencing issues, please:"
log "  1. Review the log file for ${RED}[FAILED]${NC} or ${RED}ERROR${NC} messages"
log "  2. Share this log file when reporting issues"
log "  3. Check https://github.com/anthropics/MimikaStudio/issues for known problems"
log ""
log "${GREEN}=== Diagnostic Complete ===${NC}"
