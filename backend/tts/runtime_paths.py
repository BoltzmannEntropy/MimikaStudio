"""Runtime path helpers for writable engine directories."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional


def _env_path(name: str) -> Optional[Path]:
    raw = (os.getenv(name) or "").strip()
    return Path(raw).expanduser() if raw else None


def _ensure_dir_with_fallback(primary: Path, fallback: Path) -> Path:
    try:
        primary.mkdir(parents=True, exist_ok=True)
        return primary
    except OSError:
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def get_runtime_home() -> Path:
    return _ensure_dir_with_fallback(
        _env_path("MIMIKA_RUNTIME_HOME") or (Path.home() / "MimikaStudio"),
        Path("/tmp/mimikastudio"),
    )


def get_runtime_data_dir() -> Path:
    runtime_home = get_runtime_home()
    return _ensure_dir_with_fallback(
        _env_path("MIMIKA_DATA_DIR") or (runtime_home / "data"),
        runtime_home / "data",
    )


def get_runtime_output_dir() -> Path:
    runtime_home = get_runtime_home()
    return _ensure_dir_with_fallback(
        _env_path("MIMIKA_OUTPUT_DIR") or (runtime_home / "outputs"),
        Path("/tmp/mimikastudio-outputs"),
    )


def get_cloner_user_voices_dir() -> Path:
    data_dir = get_runtime_data_dir()
    return _ensure_dir_with_fallback(
        data_dir / "user_voices" / "cloners",
        Path("/tmp/mimikastudio/data/user_voices/cloners"),
    )


def ensure_valid_cwd(fallback: Optional[Path] = None) -> Path:
    """Guarantee the process CWD is readable.

    Some packaged app launch paths can disappear while the process is alive.
    Importing libraries that resolve relative paths (for example, transformers)
    can then fail with FileNotFoundError from os.getcwd()/Path.resolve().
    """
    try:
        return Path.cwd()
    except (FileNotFoundError, OSError):
        pass

    target = (fallback or get_runtime_home()).expanduser()
    try:
        target.mkdir(parents=True, exist_ok=True)
    except OSError:
        target = Path("/tmp/mimikastudio")
        target.mkdir(parents=True, exist_ok=True)

    os.chdir(target)
    return target
