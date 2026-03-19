"""Tests for model cache validation and cleanup."""

from pathlib import Path

from fastapi.testclient import TestClient

import main
from models.registry import ModelRegistry


def test_registry_rejects_snapshot_with_broken_symlink(tmp_path: Path):
    registry = ModelRegistry(models_dir=tmp_path)
    model = registry.get_model("Kokoro")
    assert model is not None

    cache_dir = registry.get_model_cache_dir(model)
    snapshot_dir = cache_dir / "snapshots" / "abc123"
    snapshot_dir.mkdir(parents=True, exist_ok=True)

    (snapshot_dir / "config.json").write_text("{}", encoding="utf-8")
    (snapshot_dir / "model.safetensors").write_bytes(b"weights")
    (snapshot_dir / "tokenizer.json").symlink_to(cache_dir / "blobs" / "missing")

    assert registry.get_downloaded_snapshot_path(model) is None
    assert registry.is_model_downloaded(model) is False


def test_model_delete_removes_partial_cache(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("HUGGINGFACE_HUB_CACHE", str(tmp_path))

    registry = ModelRegistry()
    model = registry.get_model("Kokoro")
    assert model is not None

    cache_dir = registry.get_model_cache_dir(model)
    (cache_dir / "blobs").mkdir(parents=True, exist_ok=True)
    (cache_dir / "blobs" / "partial-file.incomplete").write_bytes(b"partial")

    client = TestClient(main.app)
    response = client.delete("/api/models/Kokoro")

    assert response.status_code == 200
    assert cache_dir.exists() is False
