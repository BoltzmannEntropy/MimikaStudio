"""Test configuration for MimikaStudio backend tests."""

import os
import shutil
import sys
import tempfile
from pathlib import Path


def _configure_test_runtime() -> Path:
    """Keep backend tests isolated from the real app runtime on disk."""
    runtime_root = Path(tempfile.mkdtemp(prefix="mimika-backend-tests-")).resolve()
    runtime_home = runtime_root / "runtime-home"
    data_dir = runtime_home / "data"
    log_dir = runtime_home / "logs"
    output_dir = runtime_home / "outputs"
    cache_root = runtime_root / "cache"

    for path in (runtime_home, data_dir, log_dir, output_dir, cache_root):
        path.mkdir(parents=True, exist_ok=True)

    os.environ["MIMIKA_RUNTIME_HOME"] = str(runtime_home)
    os.environ["MIMIKA_DATA_DIR"] = str(data_dir)
    os.environ["MIMIKA_LOG_DIR"] = str(log_dir)
    os.environ["MIMIKA_OUTPUT_DIR"] = str(output_dir)
    os.environ["MIMIKA_PARENT_PID"] = "0"
    os.environ["HF_HOME"] = str(cache_root / "hf-home")
    os.environ["HUGGINGFACE_HUB_CACHE"] = str(cache_root / "huggingface-hub")
    os.environ["TRANSFORMERS_CACHE"] = str(cache_root / "transformers")
    os.environ["XDG_CACHE_HOME"] = str(cache_root / "xdg")
    return runtime_root


_TEST_RUNTIME_ROOT = _configure_test_runtime()

# Add backend root to path for imports after the test runtime is isolated.
backend_root = Path(__file__).resolve().parents[1]
if str(backend_root) not in sys.path:
    sys.path.insert(0, str(backend_root))


def pytest_sessionfinish(session, exitstatus):
    shutil.rmtree(_TEST_RUNTIME_ROOT, ignore_errors=True)
