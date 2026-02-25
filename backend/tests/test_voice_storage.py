"""Test voice storage functionality through Qwen3 engine."""
import pytest

from tts.chatterbox_engine import ChatterboxEngine
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


def test_all_cloners_share_one_user_voices_dir(tmp_path, monkeypatch):
    """Qwen3, Chatterbox, and IndexTTS2 must share one user voice folder."""
    pytest.importorskip("torch")
    from tts.indextts2_engine import IndexTTS2Engine

    monkeypatch.setenv("MIMIKA_DATA_DIR", str(tmp_path / "runtime-data"))

    qwen_engine = Qwen3TTSEngine(model_size="0.6B")
    chatterbox_engine = ChatterboxEngine()
    indextts2_engine = IndexTTS2Engine()

    assert qwen_engine.user_voices_dir == chatterbox_engine.user_voices_dir
    assert qwen_engine.user_voices_dir == indextts2_engine.user_voices_dir
    assert qwen_engine.user_voices_dir.as_posix().endswith("user_voices/cloners")
