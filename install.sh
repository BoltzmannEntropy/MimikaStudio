#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# MimikaStudio - Installation Script
# =============================================================================
# Single script to install all dependencies and set up the project.
# Run from the repository root:  ./install.sh
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FLUTTER_DIR="$ROOT_DIR/flutter_app"
VENV_DIR="$ROOT_DIR/venv"
DICTA_MODEL_DIR="$BACKEND_DIR/models/dicta-onnx"
DICTA_MODEL_PATH="$DICTA_MODEL_DIR/dicta-1.0.onnx"
DICTA_MODEL_URL="https://github.com/thewh1teagle/dicta-onnx/releases/download/model-files-v1.0/dicta-1.0.onnx"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}$*${NC}"; }
ok()    { echo -e "${GREEN}✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}$*${NC}"; }
fail()  { echo -e "${RED}$*${NC}"; }

# =============================================================================
# 1. Prerequisites
# =============================================================================
info "=== MimikaStudio Installation ==="
echo ""
info "Checking prerequisites..."

# Homebrew
if ! command -v brew &> /dev/null; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
ok "Homebrew"

# Python 3
if ! command -v python3 &> /dev/null; then
    warn "Python3 not found. Installing via Homebrew..."
    brew install python@3.11
fi
PYTHON_VERSION=$(python3 --version)
ok "$PYTHON_VERSION"

# espeak-ng (required by Kokoro TTS)
if ! command -v espeak-ng &> /dev/null; then
    info "Installing espeak-ng (required by Kokoro TTS)..."
    brew install espeak-ng
fi
ok "espeak-ng"

# ffmpeg (required by pydub for MP3 conversion)
if ! command -v ffmpeg &> /dev/null; then
    info "Installing ffmpeg (required for audio conversion)..."
    brew install ffmpeg
fi
ok "ffmpeg"

# =============================================================================
# 2. Python Virtual Environment
# =============================================================================
echo ""
info "Setting up Python virtual environment..."

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    ok "Created venv at $VENV_DIR"
else
    ok "venv already exists at $VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
ok "Activated venv"

pip install --upgrade pip --quiet
ok "pip upgraded"

# =============================================================================
# 3. Install Python Dependencies
# =============================================================================
echo ""
info "Installing Python dependencies from requirements.txt..."
pip install -r "$ROOT_DIR/requirements.txt"
ok "Core dependencies installed"

# Chatterbox TTS must be installed with --no-deps because its pinned versions
# conflict with the rest of the stack. Its actual runtime dependencies
# (omegaconf, resemble-perth, conformer, etc.) are already in requirements.txt.
echo ""
info "Installing chatterbox-tts (with --no-deps to avoid version conflicts)..."
pip install --no-deps chatterbox-tts==0.1.6
ok "chatterbox-tts installed"

# Optional: Dicta Hebrew diacritizer model for Chatterbox (large download).
echo ""
if [ "${SKIP_DICTA:-0}" = "1" ]; then
    warn "Skipping Dicta model download (SKIP_DICTA=1)"
else
    if [ ! -f "$DICTA_MODEL_PATH" ]; then
        info "Downloading Dicta Hebrew diacritizer model (~1.1GB)..."
        mkdir -p "$DICTA_MODEL_DIR"
        curl -L -o "$DICTA_MODEL_PATH" "$DICTA_MODEL_URL"
        ok "Dicta model downloaded"
    else
        ok "Dicta model already present"
    fi
fi

# =============================================================================
# 4. Verify Key Imports
# =============================================================================
echo ""
info "Verifying critical imports..."
python3 -c "
import sys, importlib
modules = [
    'fastapi', 'uvicorn', 'kokoro', 'qwen_tts', 'chatterbox',
    'torch', 'torchaudio', 'transformers', 'omegaconf', 'perth', 'dicta_onnx',
    'soundfile', 'librosa', 'spacy', 'PyPDF2', 'fitz',
]
failed = []
for mod in modules:
    try:
        importlib.import_module(mod)
    except ImportError as e:
        failed.append((mod, str(e)))
if failed:
    print('ERROR: The following imports failed:')
    for mod, err in failed:
        print(f'  {mod}: {err}')
    sys.exit(1)
print('All critical imports OK')
"
ok "All critical imports verified"

# =============================================================================
# 5. Initialize Database
# =============================================================================
echo ""
info "Initializing database..."
cd "$BACKEND_DIR"
python3 database.py
ok "Database initialized and seeded"

# =============================================================================
# 6. Flutter (optional)
# =============================================================================
echo ""
if command -v flutter &> /dev/null; then
    info "Setting up Flutter..."
    cd "$FLUTTER_DIR"
    flutter pub get
    flutter config --enable-macos-desktop 2>/dev/null || true
    ok "Flutter ready"
else
    warn "Flutter not found - skipping Flutter setup."
    warn "Install Flutter for the desktop GUI: https://docs.flutter.dev/get-started/install/macos"
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "To start MimikaStudio (desktop):"
echo -e "  ${BLUE}source venv/bin/activate${NC}"
echo -e "  ${BLUE}./bin/mimikactl up${NC}"
echo ""
echo "To start MimikaStudio (web UI):"
echo -e "  ${BLUE}source venv/bin/activate${NC}"
echo -e "  ${BLUE}./bin/mimikactl up --web${NC}"
echo -e "  Then open ${BLUE}http://127.0.0.1:5173${NC}"
echo ""
echo "Or start backend only:"
echo -e "  ${BLUE}source venv/bin/activate${NC}"
echo -e "  ${BLUE}cd backend && uvicorn main:app --host 0.0.0.0 --port 8000${NC}"
echo ""
echo "API docs: http://localhost:8000/docs"
