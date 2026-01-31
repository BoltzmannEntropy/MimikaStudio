"""Test voice storage functionality through Qwen3 engine."""
from tts.qwen3_engine import Qwen3TTSEngine


def test_qwen3_engine_voices_dir():
    """Test that Qwen3 engine creates voices directories."""
    engine = Qwen3TTSEngine(model_size="0.6B")
    assert engine.sample_voices_dir.exists()
    assert engine.user_voices_dir.exists()


def test_qwen3_engine_outputs_dir():
    """Test that Qwen3 engine creates outputs directory."""
    engine = Qwen3TTSEngine(model_size="0.6B")
    assert engine.outputs_dir.exists()


def test_qwen3_engine_get_saved_voices():
    """Test listing saved voices."""
    engine = Qwen3TTSEngine(model_size="0.6B")
    voices = engine.get_saved_voices()
    assert isinstance(voices, list)
