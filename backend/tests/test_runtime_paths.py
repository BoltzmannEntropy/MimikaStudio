"""Tests for runtime path utilities."""

from __future__ import annotations

import os
from pathlib import Path

from tts.runtime_paths import ensure_valid_cwd


def test_ensure_valid_cwd_recovers_from_missing_directory(tmp_path: Path):
    original_cwd = Path.cwd()
    missing_cwd = tmp_path / "missing-cwd"
    missing_cwd.mkdir(parents=True, exist_ok=True)
    fallback = tmp_path / "fallback-cwd"

    try:
        os.chdir(missing_cwd)
        missing_cwd.rmdir()

        resolved = ensure_valid_cwd(fallback)

        assert resolved == fallback.resolve()
        assert Path.cwd() == fallback.resolve()
        assert fallback.exists()
    finally:
        os.chdir(original_cwd)
