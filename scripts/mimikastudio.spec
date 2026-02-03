# -*- mode: python ; coding: utf-8 -*-
# =============================================================================
# MimikaStudio - PyInstaller Spec File
# =============================================================================
# Build with:
#   pyinstaller scripts/mimikastudio.spec --noconfirm
# =============================================================================

import os
import sys

block_cipher = None

# SPECPATH is the directory containing this .spec file (i.e., scripts/)
ROOT_DIR = os.path.dirname(os.path.abspath(SPECPATH))
BACKEND_DIR = os.path.join(ROOT_DIR, 'backend')

# Data files to bundle
datas = [
    (os.path.join(BACKEND_DIR, 'data'), 'data'),
    (os.path.join(BACKEND_DIR, 'tts'), 'tts'),
    (os.path.join(BACKEND_DIR, 'llm'), 'llm'),
    (os.path.join(BACKEND_DIR, 'models'), 'models'),
    (os.path.join(BACKEND_DIR, 'language'), 'language'),
    (os.path.join(BACKEND_DIR, 'database.py'), '.'),
]

# Hidden imports for dynamically loaded modules
hiddenimports = [
    # FastAPI / Uvicorn
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.http.h11_impl',
    'uvicorn.protocols.http.httptools_impl',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.protocols.websockets.wsproto_impl',
    'uvicorn.lifespan',
    'uvicorn.lifespan.on',
    'fastapi',
    'pydantic',
    'starlette',
    'starlette.routing',
    'starlette.responses',
    'multipart',

    # TTS Engines
    'kokoro',
    'qwen_tts',
    'chatterbox',
    'chatterbox.mtl_tts',
    'indextts',
    'indextts.infer',

    # ML / Torch
    'torch',
    'torchaudio',
    'transformers',
    'accelerate',
    'safetensors',
    'tokenizers',

    # Audio
    'soundfile',
    'librosa',
    'scipy',
    'scipy.signal',
    'numpy',
    'resampy',
    'pydub',

    # NLP / Text
    'spacy',
    'omegaconf',
    'diffusers',
    'conformer',

    # Misc
    'psutil',
    'httpx',
    'aiosqlite',
    'sqlite3',
]

# Packages to exclude to reduce size
excludes = [
    'matplotlib',
    'tkinter',
    'PIL',
    'notebook',
    'jupyter',
    'IPython',
    'pytest',
    'setuptools',
    'pip',
]

a = Analysis(
    [os.path.join(BACKEND_DIR, 'main.py')],
    pathex=[BACKEND_DIR],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='MimikaStudio',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # Keep console for server output
    disable_windowed_traceback=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='MimikaStudio',
)
