@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: MimikaStudio - Windows Installation Script
:: =============================================================================
:: Single script to install all dependencies and set up the project.
:: Run from the repository root:  install.bat
::
:: Requires: Python 3.10+, NVIDIA GPU with CUDA 12.8+ (RTX 5090 / Blackwell)
:: =============================================================================

set "ROOT_DIR=%~dp0"
:: Remove trailing backslash
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

set "BACKEND_DIR=%ROOT_DIR%\backend"
set "FLUTTER_DIR=%ROOT_DIR%\flutter_app"
set "VENV_DIR=%ROOT_DIR%\venv"
set "DICTA_MODEL_DIR=%BACKEND_DIR%\models\dicta-onnx"
set "DICTA_MODEL_PATH=%DICTA_MODEL_DIR%\dicta-1.0.onnx"
set "DICTA_MODEL_URL=https://github.com/thewh1teagle/dicta-onnx/releases/download/model-files-v1.0/dicta-1.0.onnx"

:: PyTorch CUDA 12.8 index (required for RTX 5090 / Blackwell sm_120)
set "PYTORCH_INDEX=https://download.pytorch.org/whl/cu128"

:: =============================================================================
:: 1. Prerequisites
:: =============================================================================
echo.
echo === MimikaStudio Installation (Windows) ===
echo.
echo Checking prerequisites...

:: Python
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.10+ from https://www.python.org/downloads/
    echo         Make sure to check "Add Python to PATH" during installation.
    exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do set "PYTHON_VERSION=%%v"
echo [OK] %PYTHON_VERSION%

:: Check Python version is 3.10+
python -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)" 2>nul
if errorlevel 1 (
    echo [ERROR] Python 3.10 or higher is required. Current: %PYTHON_VERSION%
    exit /b 1
)

:: NVIDIA GPU / CUDA
where nvidia-smi >nul 2>&1
if errorlevel 1 (
    echo [WARN] nvidia-smi not found. CUDA may not be available.
    echo        Install NVIDIA drivers from https://www.nvidia.com/drivers/
) else (
    echo [OK] NVIDIA driver found
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>nul
)

:: espeak-ng (required by Kokoro TTS)
where espeak-ng >nul 2>&1
if errorlevel 1 (
    echo [WARN] espeak-ng not found. Required by Kokoro TTS.
    echo        Install from: https://github.com/espeak-ng/espeak-ng/releases
    echo        Or via winget:  winget install espeak-ng.espeak-ng
)  else (
    echo [OK] espeak-ng
)

:: ffmpeg (required by pydub for MP3 conversion)
where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo [WARN] ffmpeg not found. Required for audio conversion.
    echo        Install via winget:  winget install Gyan.FFmpeg
) else (
    echo [OK] ffmpeg
)

:: =============================================================================
:: 2. Python Virtual Environment
:: =============================================================================
echo.
echo Setting up Python virtual environment...

if not exist "%VENV_DIR%\Scripts\python.exe" (
    python -m venv "%VENV_DIR%"
    echo [OK] Created venv at %VENV_DIR%
) else (
    echo [OK] venv already exists at %VENV_DIR%
)

set "PYTHON=%VENV_DIR%\Scripts\python.exe"
set "PIP=%VENV_DIR%\Scripts\pip.exe"

"%PIP%" install --upgrade pip --quiet
echo [OK] pip upgraded

:: =============================================================================
:: 3. Install PyTorch with CUDA 12.8 (RTX 5090 / Blackwell)
:: =============================================================================
echo.
echo Installing PyTorch with CUDA 12.8 support (for RTX 5090)...

"%PIP%" install --force-reinstall torch torchaudio --index-url %PYTORCH_INDEX%
if errorlevel 1 (
    echo [ERROR] Failed to install PyTorch with CUDA 12.8.
    echo         Falling back to default PyTorch install...
    "%PIP%" install torch torchaudio
)

:: Verify CUDA is available
"%PYTHON%" -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'; print(f'[OK] PyTorch {torch.__version__} with CUDA {torch.version.cuda} - {torch.cuda.get_device_name(0)}')"
if errorlevel 1 (
    echo [WARN] CUDA is NOT available in PyTorch. GPU acceleration will not work.
    echo        Make sure NVIDIA drivers and CUDA toolkit 12.8+ are installed.
    "%PYTHON%" -c "import torch; print(f'       PyTorch version: {torch.__version__}')"
)

:: =============================================================================
:: 4. Install Python Dependencies
:: =============================================================================
echo.
echo Installing Python dependencies from requirements.txt...

:: Install requirements but skip torch/torchaudio lines (already installed with CUDA)
set "FILTERED_REQ=%VENV_DIR%\_req_no_torch.txt"
"%PYTHON%" -c "f=open(r'%ROOT_DIR%\requirements.txt'); o=open(r'%FILTERED_REQ%','w'); [o.write(l) for l in f if not l.strip().lower().startswith(('torch>','torch=','torchaudio'))]; o.close(); f.close()"
"%PIP%" install -r "%FILTERED_REQ%"
del "%FILTERED_REQ%" 2>nul
echo [OK] Core dependencies installed

:: Chatterbox TTS must be installed with --no-deps because its pinned versions
:: conflict with the rest of the stack.
echo.
echo Installing chatterbox-tts (with --no-deps to avoid version conflicts)...
"%PIP%" install --no-deps chatterbox-tts==0.1.6
echo [OK] chatterbox-tts installed

:: Optional: Dicta Hebrew diacritizer model for Chatterbox (large download).
echo.
if "%SKIP_DICTA%"=="1" (
    echo [WARN] Skipping Dicta model download (SKIP_DICTA=1)
) else (
    if not exist "%DICTA_MODEL_PATH%" (
        echo Downloading Dicta Hebrew diacritizer model (~1.1GB)...
        if not exist "%DICTA_MODEL_DIR%" mkdir "%DICTA_MODEL_DIR%"
        powershell -Command "Invoke-WebRequest -Uri '%DICTA_MODEL_URL%' -OutFile '%DICTA_MODEL_PATH%'"
        if errorlevel 1 (
            echo [WARN] Failed to download Dicta model. Hebrew diacritization will be unavailable.
        ) else (
            echo [OK] Dicta model downloaded
        )
    ) else (
        echo [OK] Dicta model already present
    )
)

:: IndexTTS-2: installed from git (not on PyPI), --no-deps to avoid conflicts
echo.
echo Installing IndexTTS-2 from git (not on PyPI)...
"%PIP%" install --no-deps git+https://github.com/index-tts/index-tts.git
if errorlevel 1 (
    echo [WARN] Failed to install IndexTTS-2. Voice cloning with IndexTTS-2 will be unavailable.
    echo        You can try manually: pip install --no-deps git+https://github.com/index-tts/index-tts.git
) else (
    echo [OK] IndexTTS-2 installed
)

:: IndexTTS-2 model weights are auto-downloaded from HuggingFace on first use (~24GB).
:: They cache under %USERPROFILE%\.cache\huggingface\
echo.
echo [INFO] IndexTTS-2 model weights will be auto-downloaded on first use (~24GB).

:: =============================================================================
:: 5. Verify Key Imports
:: =============================================================================
echo.
echo Verifying critical imports...

set "VERIFY_SCRIPT=%VENV_DIR%\_verify.py"
(
echo import sys, importlib
echo modules = [
echo     'fastapi', 'uvicorn', 'kokoro', 'qwen_tts', 'chatterbox', 'indextts',
echo     'torch', 'torchaudio', 'transformers', 'omegaconf', 'perth', 'dicta_onnx',
echo     'soundfile', 'librosa', 'spacy', 'PyPDF2', 'fitz',
echo ]
echo failed = []
echo for mod in modules:
echo     try:
echo         importlib.import_module(mod^)
echo         print(f'  {mod}: OK'^)
echo     except ImportError as e:
echo         failed.append((mod, str(e^)^)^)
echo         print(f'  {mod}: FAILED - {e}'^)
echo if failed:
echo     print(f'\nWARNING: {len(failed^)} import(s^) failed'^)
echo     sys.exit(1^)
echo print('\n[OK] All critical imports verified'^)
) > "%VERIFY_SCRIPT%"
"%PYTHON%" "%VERIFY_SCRIPT%"
if errorlevel 1 (
    echo [WARN] Some imports failed. The missing packages may be optional.
)
del "%VERIFY_SCRIPT%" 2>nul

:: =============================================================================
:: 6. Initialize Database
:: =============================================================================
echo.
echo Initializing database...

pushd "%BACKEND_DIR%"
"%PYTHON%" database.py
popd
echo [OK] Database initialized and seeded

:: =============================================================================
:: 7. Flutter (optional)
:: =============================================================================
echo.
where flutter >nul 2>&1
if not errorlevel 1 (
    echo Setting up Flutter...
    pushd "%FLUTTER_DIR%"
    flutter pub get
    flutter config --enable-web 2>nul
    popd
    echo [OK] Flutter ready
) else (
    echo [WARN] Flutter not found - skipping Flutter setup.
    echo        Install Flutter for the web UI: https://docs.flutter.dev/get-started/install/windows
)

:: =============================================================================
:: 8. Verify CUDA end-to-end
:: =============================================================================
echo.
echo Running CUDA verification...
"%PYTHON%" -c "import torch; print(f'PyTorch:    {torch.__version__}'); print(f'CUDA:       {torch.version.cuda}'); print(f'cuDNN:      {torch.backends.cudnn.version() if torch.backends.cudnn.is_available() else \"N/A\"}'); print(f'GPU:        {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}'); print(f'VRAM:       {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB' if torch.cuda.is_available() else '')"

:: =============================================================================
:: Done
:: =============================================================================
echo.
echo === Installation Complete ===
echo.
echo To start MimikaStudio (web UI):
echo   .\bin\mimikactl.ps1 up --web
echo   Then open http://127.0.0.1:5173
echo.
echo Or start backend only:
echo   .\bin\mimikactl.ps1 backend start
echo.
echo API docs: http://localhost:8000/docs
echo.

endlocal
