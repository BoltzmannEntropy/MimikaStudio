"""Test model registry."""
from models.registry import ModelRegistry, QWEN_SPEAKERS


def test_model_registry_defaults(tmp_path):
    """Test that registry has default Qwen3 models."""
    registry = ModelRegistry(models_dir=tmp_path)
    models = registry.list_models()
    assert len(models) == 8
    assert all(m.engine == "qwen3" for m in models)


def test_model_registry_clone_models(tmp_path):
    """Test clone mode models across all supported engines."""
    registry = ModelRegistry(models_dir=tmp_path)
    clone_models = registry.get_models_by_mode("clone")

    # Qwen clone models include bf16 + 8-bit Base variants.
    qwen_clone_models = [m for m in clone_models if m.engine == "qwen3"]
    assert len(qwen_clone_models) == 4
    assert all("Base" in m.name for m in qwen_clone_models)

    # Registry should also include Chatterbox clone engine.
    clone_engines = {m.engine for m in clone_models}
    assert "chatterbox" in clone_engines


def test_model_registry_custom_models(tmp_path):
    """Test custom mode models."""
    registry = ModelRegistry(models_dir=tmp_path)
    custom_models = registry.get_models_by_mode("custom")
    assert len(custom_models) == 4
    assert all("CustomVoice" in m.name for m in custom_models)
    for m in custom_models:
        assert m.speakers == QWEN_SPEAKERS


def test_qwen_speakers():
    """Test preset speakers list."""
    assert len(QWEN_SPEAKERS) == 9
    assert "Ryan" in QWEN_SPEAKERS
    assert "Aiden" in QWEN_SPEAKERS
    assert "Vivian" in QWEN_SPEAKERS
    assert "Sohee" in QWEN_SPEAKERS
