#!/bin/bash
set -euo pipefail

# MimikaStudio DMG Builder
# Usage: ./scripts/build_dmg.sh
#
# This script produces a self-contained macOS app bundle with:
# - Flutter desktop UI
# - Bundled Python runtime in Contents/Resources/python
# - Bundled backend code in Contents/Resources/backend
# - Bundled backend dependencies in Contents/Resources/backend/venv

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_NAME="MimikaStudio"
ARCH="$(uname -m)"
BUILD_DIR="${MIMIKA_BUILD_DIR:-$PROJECT_DIR/build}"
DIST_DIR="${MIMIKA_DIST_DIR:-$PROJECT_DIR/dist}"
DMG_STAGE_DIR="$BUILD_DIR/dmg-stage"
APP_BUNDLE="$DMG_STAGE_DIR/$APP_NAME.app"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
BUNDLED_BACKEND="$APP_RESOURCES/backend"
BUNDLED_PYTHON="$APP_RESOURCES/python"
MLX_ONLY_BUILD="${MLX_ONLY_BUILD:-1}"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

read_version_field() {
    local field="$1"
    python3 - <<PY
namespace = {}
with open("$PROJECT_DIR/backend/version.py", "r", encoding="utf-8") as f:
    exec(f.read(), namespace)
print(namespace["$field"])
PY
}

read_version_from_pubspec() {
    local pubspec="$PROJECT_DIR/flutter_app/pubspec.yaml"
    if [ -f "$pubspec" ]; then
        grep '^version:' "$pubspec" | head -1 | cut -d'+' -f1 | cut -d':' -f2 | xargs
    fi
}

read_build_from_pubspec() {
    local pubspec="$PROJECT_DIR/flutter_app/pubspec.yaml"
    if [ -f "$pubspec" ]; then
        grep '^version:' "$pubspec" | head -1 | cut -d'+' -f2 | xargs
    fi
}

resolve_source_venv() {
    if [ -d "$PROJECT_DIR/backend/venv" ]; then
        echo "$PROJECT_DIR/backend/venv"
        return
    fi
    if [ -d "$PROJECT_DIR/venv" ]; then
        echo "$PROJECT_DIR/venv"
        return
    fi
    die "No Python virtual environment found. Expected backend/venv or venv."
}

resolve_python_home() {
    local source_venv="$1"
    local cfg="$source_venv/pyvenv.cfg"
    local home=""

    if [ -f "$cfg" ]; then
        home="$(awk -F ' = ' '/^home = / { print $2; exit }' "$cfg" || true)"
    fi

    if [ -n "$home" ] && [ -d "$home" ]; then
        echo "${home%/bin}"
        return
    fi

    local py3_target
    py3_target="$(readlink "$source_venv/bin/python3" 2>/dev/null || true)"
    if [ -n "$py3_target" ] && [ -d "${py3_target%/bin/*}" ]; then
        echo "${py3_target%/bin/*}"
        return
    fi

    die "Unable to resolve base Python installation for $source_venv"
}

resolve_python_tag() {
    local source_venv="$1"
    local py_lib
    py_lib="$(find "$source_venv/lib" -maxdepth 1 -type d -name 'python*' | head -n 1 || true)"
    [ -n "$py_lib" ] || die "Unable to resolve Python lib directory under $source_venv/lib"
    basename "$py_lib"
}

VERSION="$(read_version_from_pubspec || true)"
BUILD_NUMBER="$(read_build_from_pubspec || true)"
[ -n "$VERSION" ] || VERSION="$(read_version_field VERSION)"
[ -n "$BUILD_NUMBER" ] || BUILD_NUMBER="$(read_version_field BUILD_NUMBER)"
SOURCE_VENV="$(resolve_source_venv)"
PYTHON_HOME="$(resolve_python_home "$SOURCE_VENV")"
PYTHON_TAG="$(resolve_python_tag "$SOURCE_VENV")"   # e.g. python3.11
PYTHON_SHORT="${PYTHON_TAG#python}"                 # e.g. 3.11

log "=== MimikaStudio DMG Builder ==="
log "Building version: $VERSION (build $BUILD_NUMBER)"
log "Architecture: $ARCH"
log "MLX-only packaging: $MLX_ONLY_BUILD"
log "Using source venv: $SOURCE_VENV"
log "Using Python home: $PYTHON_HOME"
log "Python tag: $PYTHON_TAG"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

log "Building Flutter app..."
cd "$PROJECT_DIR/flutter_app"
env TOOLCHAINS="com.apple.dt.toolchain.XcodeDefault" \
    flutter build macos --release --no-pub

RELEASE_DIR="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release"
FLUTTER_APP=""
for candidate in "mimika_studio.app" "$APP_NAME.app"; do
    if [ -d "$RELEASE_DIR/$candidate" ]; then
        FLUTTER_APP="$RELEASE_DIR/$candidate"
        break
    fi
done
if [ -z "$FLUTTER_APP" ]; then
    FLUTTER_APP="$(find "$RELEASE_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
fi
[ -n "$FLUTTER_APP" ] && [ -d "$FLUTTER_APP" ] || die "Flutter build succeeded but no .app bundle found in $RELEASE_DIR"
log "Using app bundle: $FLUTTER_APP"

log "Preparing DMG staging..."
rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$FLUTTER_APP" "$APP_BUNDLE"
# Add standard drag-to-install target.
ln -sfn /Applications "$DMG_STAGE_DIR/Applications"

log "Embedding license files..."
mkdir -p "$APP_RESOURCES"
for license_file in LICENSE BINARY-LICENSE.txt; do
    if [ -f "$PROJECT_DIR/$license_file" ]; then
        cp "$PROJECT_DIR/$license_file" "$APP_RESOURCES/$license_file"
        cp "$PROJECT_DIR/$license_file" "$DMG_STAGE_DIR/$license_file"
    fi
done

log "Bundling backend source..."
mkdir -p "$BUNDLED_BACKEND"
rsync -a \
    --delete \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    --exclude '*.pyc' \
    --exclude '*.pyo' \
    --exclude '.DS_Store' \
    --exclude 'data/pregenerated/_tmp*/' \
    --exclude 'data/pregenerated/tmp*/' \
    --exclude 'tests/' \
    --exclude 'venv/' \
    --exclude 'venv_broken*/' \
    --exclude 'models/' \
    --exclude 'outputs/' \
    --exclude '*.db' \
    "$PROJECT_DIR/backend/" \
    "$BUNDLED_BACKEND/"
# Preserve backend model registry source without bundling heavyweight model payloads.
mkdir -p "$BUNDLED_BACKEND/models" "$BUNDLED_BACKEND/outputs"
if [ -d "$PROJECT_DIR/backend/models" ]; then
    rsync -a \
        --exclude '__pycache__/' \
        --exclude '*.pyc' \
        --exclude '*.pyo' \
        --exclude '.DS_Store' \
        --include '*/' \
        --include '*.py' \
        --exclude '*' \
        "$PROJECT_DIR/backend/models/" \
        "$BUNDLED_BACKEND/models/"
fi

log "Bundling Python runtime..."
mkdir -p "$BUNDLED_PYTHON"
rsync -a \
    --delete \
    --exclude '__pycache__/' \
    --exclude '.DS_Store' \
    --exclude 'share/' \
    --exclude 'lib/python*/site-packages/' \
    --exclude 'lib/python*/test/' \
    "$PYTHON_HOME/" \
    "$BUNDLED_PYTHON/"

log "Bundling backend dependencies from venv site-packages..."
rm -rf "$BUNDLED_BACKEND/venv"
# Use rsync instead of cp to avoid macOS metadata/permission edge-cases
# when copying very large venv trees into app bundle staging.
mkdir -p "$BUNDLED_BACKEND/venv"
rsync -a \
    --delete \
    --no-perms \
    --no-owner \
    --no-group \
    "$SOURCE_VENV/" \
    "$BUNDLED_BACKEND/venv/"
rm -rf "$BUNDLED_BACKEND/venv/include" "$BUNDLED_BACKEND/venv/share"
find "$BUNDLED_BACKEND/venv" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$BUNDLED_BACKEND/venv" -type d -name 'tests' -prune -exec rm -rf {} + 2>/dev/null || true
find "$BUNDLED_BACKEND/venv" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
find "$BUNDLED_BACKEND/venv" -name '.DS_Store' -type f -delete 2>/dev/null || true

if [ "$MLX_ONLY_BUILD" = "1" ]; then
    log "Pruning non-MLX payloads from bundled venv for MLX-only build..."
    BUNDLED_SITE_PACKAGES="$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages"
    if [ -d "$BUNDLED_SITE_PACKAGES" ]; then
        for pattern in \
            "torch" \
            "torch-*.dist-info" \
            "torchaudio" \
            "torchaudio-*.dist-info" \
            "torchgen" \
            "functorch" \
            "indextts" \
            "indextts-*.dist-info" \
            "qwen_tts" \
            "qwen_tts-*.dist-info" \
            "kokoro" \
            "kokoro-*.dist-info" \
            "spacy_curated_transformers" \
            "spacy_curated_transformers-*.dist-info" \
            "curated_transformers" \
            "curated_transformers-*.dist-info" \
            "curated_tokenizers" \
            "curated_tokenizers-*.dist-info" \
            "chatterbox" \
            "chatterbox_tts-*.dist-info" \
            "gradio" \
            "gradio-*.dist-info" \
            "gradio_client" \
            "gradio_client-*.dist-info" \
            "pandas" \
            "pandas-*.dist-info" \
            "sklearn" \
            "scikit_learn-*.dist-info" \
            "matplotlib" \
            "matplotlib-*.dist-info" \
            "sympy" \
            "sympy-*.dist-info" \
            "onnx" \
            "onnx-*.dist-info" \
            "pip" \
            "pip-*.dist-info" \
            "setuptools" \
            "setuptools-*.dist-info" \
            "wheel" \
            "wheel-*.dist-info"; do
            find "$BUNDLED_SITE_PACKAGES" -maxdepth 1 -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
        done
    fi
    rm -f \
        "$BUNDLED_BACKEND/venv/bin/torchrun" \
        "$BUNDLED_BACKEND/venv/bin/torchaudio" \
        "$BUNDLED_BACKEND/venv/bin/gradio" \
        "$BUNDLED_BACKEND/venv/bin/pip" \
        "$BUNDLED_BACKEND/venv/bin/pip3" \
        "$BUNDLED_BACKEND/venv/bin/pip$PYTHON_SHORT" \
        2>/dev/null || true
fi

# Rewrite Python/runtime Mach-O links so the app is portable across machines.
# This vendors non-system dylibs (e.g., Homebrew OpenSSL) into Resources/python/lib
# and rewrites absolute loader paths to @loader_path-relative references.
is_macho_file() {
    local f="$1"
    [ -f "$f" ] || return 1
    file "$f" 2>/dev/null | grep -q "Mach-O"
}

is_system_dep() {
    local dep="$1"
    case "$dep" in
        @*) return 0 ;;
        /usr/lib/*) return 0 ;;
        /System/Library/*) return 0 ;;
        /System/Volumes/Preboot/Cryptexes/OS/usr/lib/*) return 0 ;;
    esac
    return 1
}

loader_ref_to_python_lib() {
    local from_file="$1"
    local to_file="$2"
    python3 - <<PY
import os
from_dir = os.path.dirname(os.path.abspath("$from_file"))
to_file = os.path.abspath("$to_file")
rel = os.path.relpath(to_file, from_dir).replace("\\\\", "/")
print(f"@loader_path/{rel}")
PY
}

patch_macho_deps() {
    local bin="$1"
    is_macho_file "$bin" || return 0

    local dep
    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        if is_system_dep "$dep"; then
            continue
        fi
        local resolved_dep="$dep"
        local dep_name dep_pkg dep_pkg_candidate dep_local1 dep_local2
        dep_name="$(basename "$dep")"

        if [ ! -f "$resolved_dep" ]; then
            # Some wheels (numpy/scipy/Pillow) store deps under package-local .dylibs
            # but encode loader paths like /DLC/<pkg>/.dylibs/<lib>.
            if [[ "$dep" == */.dylibs/* ]]; then
                dep_pkg="$(echo "$dep" | sed -E 's#.*/([^/]+)/\.dylibs/.*#\1#')"
                dep_pkg_candidate="$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages/$dep_pkg/.dylibs/$dep_name"
                if [ -f "$dep_pkg_candidate" ]; then
                    resolved_dep="$dep_pkg_candidate"
                fi
            fi
        fi

        if [ ! -f "$resolved_dep" ]; then
            dep_local1="$(dirname "$bin")/.dylibs/$dep_name"
            dep_local2="$(dirname "$(dirname "$bin")")/.dylibs/$dep_name"
            if [ -f "$dep_local1" ]; then
                resolved_dep="$dep_local1"
            elif [ -f "$dep_local2" ]; then
                resolved_dep="$dep_local2"
            fi
        fi

        if [ ! -f "$resolved_dep" ]; then
            log "Warning: unresolved non-system dependency for $(basename "$bin"): $dep"
            continue
        fi

        local dep_dst dep_ref
        dep_dst="$BUNDLED_PYTHON/lib/$dep_name"

        if [ ! -f "$dep_dst" ]; then
            cp -f "$resolved_dep" "$dep_dst"
            chmod 755 "$dep_dst" 2>/dev/null || true
        fi

        dep_ref="$(loader_ref_to_python_lib "$bin" "$dep_dst")"
        install_name_tool -change "$dep" "$dep_ref" "$bin" 2>/dev/null || true
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}')

    # Normalize install-id for dylibs we vendor so transitive loads stay local.
    case "$bin" in
        *.dylib)
            install_name_tool -id "@loader_path/$(basename "$bin")" "$bin" 2>/dev/null || true
            ;;
    esac
}

vendor_python_runtime_deps() {
    local tmp_list pass
    tmp_list="$(mktemp)"

    # Seed with executables and extension modules that Python may load at runtime.
    find "$BUNDLED_PYTHON/bin" -maxdepth 1 -type f > "$tmp_list"
    find "$BUNDLED_PYTHON/lib" -type f \( -name "*.so" -o -name "*.dylib" \) >> "$tmp_list"
    find "$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages" -type f \( -name "*.so" -o -name "*.dylib" \) >> "$tmp_list" 2>/dev/null || true

    # Multiple passes to catch dependencies of newly-vendored dylibs.
    for pass in 1 2 3 4 5 6; do
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            patch_macho_deps "$candidate"
        done < "$tmp_list"

        # Refresh list to include any dylibs newly copied into Resources/python/lib.
        find "$BUNDLED_PYTHON/bin" -maxdepth 1 -type f > "$tmp_list"
        find "$BUNDLED_PYTHON/lib" -type f \( -name "*.so" -o -name "*.dylib" \) >> "$tmp_list"
        find "$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages" -type f \( -name "*.so" -o -name "*.dylib" \) >> "$tmp_list" 2>/dev/null || true
    done

    rm -f "$tmp_list"
}

codesign_with_retry() {
    local target="$1"
    local attempt
    local tmp_log
    tmp_log="$(mktemp)"
    for attempt in 1 2 3; do
        if codesign --force --sign - "$target" >"$tmp_log" 2>&1; then
            rm -f "$tmp_log"
            return 0
        fi
        echo "codesign attempt $attempt failed for $target" >&2
        cat "$tmp_log" >&2
        sleep 0.2
    done
    rm -f "$tmp_log"
    return 1
}

codesign_app_bundle_with_retry() {
    local bundle="$1"
    local attempt
    local tmp_log
    tmp_log="$(mktemp)"
    for attempt in 1 2 3; do
        if codesign --force --deep --sign - "$bundle" >"$tmp_log" 2>&1; then
            rm -f "$tmp_log"
            return 0
        fi
        echo "codesign attempt $attempt failed for app bundle $bundle" >&2
        cat "$tmp_log" >&2
        sleep 0.2
    done
    rm -f "$tmp_log"
    return 1
}

if [ -x "$BUNDLED_PYTHON/bin/python$PYTHON_SHORT" ]; then
    BUNDLED_PY_EXEC="python$PYTHON_SHORT"
else
    BUNDLED_PY_EXEC="python3"
fi

vendor_python_runtime_deps

rm -f "$BUNDLED_BACKEND/venv/bin/python" "$BUNDLED_BACKEND/venv/bin/python3" "$BUNDLED_BACKEND/venv/bin/python$PYTHON_SHORT"
# Keep a real interpreter binary inside backend/venv/bin to avoid dyld issues
# when launching via symlinked paths from app translocation.
cp -f "$BUNDLED_PYTHON/bin/$BUNDLED_PY_EXEC" "$BUNDLED_BACKEND/venv/bin/python3"
chmod 755 "$BUNDLED_BACKEND/venv/bin/python3"

# Point venv interpreter dependencies at the bundled python lib directory.
while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    case "$dep" in
        /usr/lib/*|/System/Library/*|/System/Volumes/Preboot/Cryptexes/OS/usr/lib/*)
            continue
            ;;
    esac
    dep_name="$(basename "$dep")"
    install_name_tool \
        -change "$dep" "@loader_path/../../../python/lib/$dep_name" \
        "$BUNDLED_BACKEND/venv/bin/python3" 2>/dev/null || true
done < <(otool -L "$BUNDLED_BACKEND/venv/bin/python3" 2>/dev/null | awk 'NR>1 {print $1}')

ln -sf "python3" "$BUNDLED_BACKEND/venv/bin/python"
ln -sf "python3" "$BUNDLED_BACKEND/venv/bin/python$PYTHON_SHORT"

log "Re-signing bundled runtime binaries..."
failed_sign_targets=()
while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    is_macho_file "$candidate" || continue
    if ! codesign_with_retry "$candidate"; then
        failed_sign_targets+=("$candidate")
    fi
done < <(
    {
        find "$BUNDLED_PYTHON/bin" -maxdepth 1 -type f 2>/dev/null
        find "$BUNDLED_PYTHON/lib" -type f \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null
        find "$BUNDLED_BACKEND/venv/bin" -maxdepth 1 -type f 2>/dev/null
        find "$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages" -type f \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null
    } | sort -u
)
if [ "${#failed_sign_targets[@]}" -gt 0 ]; then
    log "Retrying codesign for ${#failed_sign_targets[@]} binaries that failed initial signing..."
    for candidate in "${failed_sign_targets[@]}"; do
        codesign_with_retry "$candidate" || true
    done
fi

log "Verifying runtime signatures..."
invalid_signature_count=0
while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    is_macho_file "$candidate" || continue
    if ! codesign --verify --strict --verbose=1 "$candidate" >/dev/null 2>&1; then
        invalid_signature_count=$((invalid_signature_count + 1))
        echo "Invalid signature: $candidate" >&2
    fi
done < <(
    {
        find "$BUNDLED_PYTHON/bin" -maxdepth 1 -type f 2>/dev/null
        find "$BUNDLED_PYTHON/lib" -type f \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null
        find "$BUNDLED_BACKEND/venv/bin" -maxdepth 1 -type f 2>/dev/null
        find "$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages" -type f \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null
    } | sort -u
)
if [ "$invalid_signature_count" -ne 0 ]; then
    die "Runtime signature verification failed for $invalid_signature_count binaries"
fi

cat > "$BUNDLED_BACKEND/venv/pyvenv.cfg" <<CFG
home = ../python/bin
include-system-site-packages = false
version = ${PYTHON_SHORT}.0
executable = ../python/bin/$BUNDLED_PY_EXEC
CFG

log "Running bundled backend import smoke test..."
SMOKE_SITE_PACKAGES="$BUNDLED_BACKEND/venv/lib/$PYTHON_TAG/site-packages"
SMOKE_PYTHONPATH="$BUNDLED_BACKEND:$SMOKE_SITE_PACKAGES"
PYTHONPATH="$SMOKE_PYTHONPATH" "$BUNDLED_BACKEND/venv/bin/python3" - <<'PY'
import fastapi
import numpy
import soundfile
import main
from tts.kokoro_engine import _configure_espeak_runtime
from phonemizer.backend.espeak.wrapper import EspeakWrapper

_configure_espeak_runtime()
EspeakWrapper()
print("backend-smoke-ok")
PY

log "Writing backend launcher..."
cat > "$BUNDLED_BACKEND/run_backend.sh" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MimikaStudio"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/${APP_NAME}"
APP_CACHE_DIR="${HOME}/Library/Caches/${APP_NAME}"
APP_LOG_DIR="${HOME}/Library/Logs/${APP_NAME}"

mkdir -p "$APP_SUPPORT_DIR" "$APP_CACHE_DIR" "$APP_LOG_DIR"

LOG_FILE="$APP_LOG_DIR/backend.log"
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/mimikastudio-backend.log"
    touch "$LOG_FILE"
fi
BACKEND_PORT="${MIMIKA_BACKEND_PORT:-7693}"
PYTHON_BIN="$SCRIPT_DIR/venv/bin/python3"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "Bundled venv Python not found at $PYTHON_BIN" >&2
    exit 1
fi

# Resolve bundled site-packages dynamically.
SITE_PACKAGES_DIR=""
for candidate in "$SCRIPT_DIR"/venv/lib/python*/site-packages; do
    if [ -d "$candidate" ]; then
        SITE_PACKAGES_DIR="$candidate"
        break
    fi
done

if [ -z "$SITE_PACKAGES_DIR" ]; then
    echo "Bundled site-packages directory not found" >&2
    exit 1
fi

export PYTHONUNBUFFERED=1
export PYTHONPYCACHEPREFIX="$APP_CACHE_DIR/pycache"
export XDG_CACHE_HOME="$APP_CACHE_DIR"
export MIMIKA_RUNTIME_HOME="$APP_SUPPORT_DIR"
export MIMIKA_DATA_DIR="$APP_SUPPORT_DIR/data"
export MIMIKA_LOG_DIR="$APP_LOG_DIR"
export MIMIKA_OUTPUT_DIR="$APP_SUPPORT_DIR/outputs"
export HF_HOME="$APP_SUPPORT_DIR/huggingface"
export HUGGINGFACE_HUB_CACHE="$HF_HOME/hub"
export TRANSFORMERS_CACHE="$HUGGINGFACE_HUB_CACHE"
export PYTHONPATH="$SCRIPT_DIR:$SITE_PACKAGES_DIR${PYTHONPATH:+:$PYTHONPATH}"

mkdir -p "$MIMIKA_DATA_DIR" "$MIMIKA_OUTPUT_DIR" "$HUGGINGFACE_HUB_CACHE"

cd "$SCRIPT_DIR"
exec "$PYTHON_BIN" -m uvicorn main:app --host 127.0.0.1 --port "$BACKEND_PORT" >> "$LOG_FILE" 2>&1
LAUNCHER
chmod +x "$BUNDLED_BACKEND/run_backend.sh"

log "Running bundled backend runtime smoke test..."
SMOKE_LOG="$(mktemp)"
SMOKE_PDF_LIST="$(mktemp)"
SMOKE_PORT="$(python3 - <<'PY'
import random
print(random.randint(18000, 18999))
PY
)"
SMOKE_PID=""
cleanup_smoke() {
    if [ -n "$SMOKE_PID" ]; then
        kill "$SMOKE_PID" >/dev/null 2>&1 || true
        wait "$SMOKE_PID" >/dev/null 2>&1 || true
    fi
    rm -f "$SMOKE_LOG" "$SMOKE_PDF_LIST"
}

MIMIKA_BACKEND_PORT="$SMOKE_PORT" "$BUNDLED_BACKEND/run_backend.sh" >"$SMOKE_LOG" 2>&1 &
SMOKE_PID=$!

ready=0
for _ in $(seq 1 120); do
    if curl -sf "http://127.0.0.1:$SMOKE_PORT/api/health" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.5
done
if [ "$ready" -ne 1 ]; then
    cat "$SMOKE_LOG" >&2 || true
    cleanup_smoke
    die "Bundled backend runtime smoke test failed: /api/health did not become ready"
fi

if ! curl -sf "http://127.0.0.1:$SMOKE_PORT/api/pdf/list" >"$SMOKE_PDF_LIST"; then
    cat "$SMOKE_LOG" >&2 || true
    cleanup_smoke
    die "Bundled backend runtime smoke test failed: /api/pdf/list returned error"
fi

FIRST_BUNDLED_PDF="$(find "$BUNDLED_BACKEND/data/pdf" -maxdepth 1 -type f -name '*.pdf' | head -n 1 || true)"
if [ -n "$FIRST_BUNDLED_PDF" ]; then
    FIRST_PDF_NAME="$(basename "$FIRST_BUNDLED_PDF")"
    if ! curl -sf "http://127.0.0.1:$SMOKE_PORT/pdf/$FIRST_PDF_NAME" >/dev/null; then
        cat "$SMOKE_LOG" >&2 || true
        cleanup_smoke
        die "Bundled backend runtime smoke test failed: /pdf/$FIRST_PDF_NAME returned error"
    fi
fi

cleanup_smoke

if command -v xattr >/dev/null 2>&1; then
    log "Stripping copied extended attributes from app bundle..."
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true
fi

log "Signing final app bundle..."
codesign_app_bundle_with_retry "$APP_BUNDLE" || die "Failed to sign final app bundle"

log "Verifying final app bundle signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" \
    || die "Final app bundle signature verification failed"

DMG_NAME="$APP_NAME-$VERSION-$ARCH.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

log "Creating DMG: $DMG_NAME"
rm -f "$DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 700 430 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 180 200 \
        --app-drop-link 510 200 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$DMG_STAGE_DIR" || {
            log "create-dmg failed, falling back to hdiutil"
            hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DMG_PATH"
        }
else
    log "create-dmg not found, using hdiutil"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DMG_PATH"
fi

log "Generating SHA256..."
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
SHA256="$(awk '{print $1}' "$DMG_NAME.sha256")"

RELEASE_NOTES_SRC="$PROJECT_DIR/RELEASE_NOTES.md"
RELEASE_NOTES_NAME="$APP_NAME-$VERSION-RELEASE_NOTES.md"
if [ -f "$RELEASE_NOTES_SRC" ]; then
    cp "$RELEASE_NOTES_SRC" "$DIST_DIR/$RELEASE_NOTES_NAME"
    shasum -a 256 "$RELEASE_NOTES_NAME" > "$RELEASE_NOTES_NAME.sha256"
fi

SOURCE_ZIP_NAME="$APP_NAME-$VERSION-source.zip"
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PROJECT_DIR" archive \
        --format=zip \
        --prefix="$APP_NAME-$VERSION/" \
        -o "$DIST_DIR/$SOURCE_ZIP_NAME" \
        HEAD
    shasum -a 256 "$SOURCE_ZIP_NAME" > "$SOURCE_ZIP_NAME.sha256"
fi

log ""
log "=== Build Complete ==="
log "DMG: $DMG_PATH"
log "SHA256: $SHA256"
if [ -f "$DIST_DIR/$RELEASE_NOTES_NAME" ]; then
    log "Release notes: $DIST_DIR/$RELEASE_NOTES_NAME"
fi
if [ -f "$DIST_DIR/$SOURCE_ZIP_NAME" ]; then
    log "Source ZIP: $DIST_DIR/$SOURCE_ZIP_NAME"
fi
