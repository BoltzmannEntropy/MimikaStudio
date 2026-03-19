"""Regression tests for shipped clone voices in the shared samples folder."""
from fastapi.testclient import TestClient

from main import SHARED_SAMPLE_VOICES_DIR, app

SHIPPED_CLONE_VOICES = (
    "Yelena",
    "Svetlana",
    "Eleanor",
    "Harriet",
    "Beatrice",
    "Alistair",
)


def test_shared_clone_voice_assets_exist():
    """Shipped shared default clone voices must exist on disk."""
    for voice_name in SHIPPED_CLONE_VOICES:
        assert (SHARED_SAMPLE_VOICES_DIR / f"{voice_name}.wav").exists()


def test_qwen3_and_chatterbox_expose_shipped_clone_voices():
    """Both clone endpoints should expose the shipped default voices."""
    client = TestClient(app)

    qwen_response = client.get("/api/qwen3/voices")
    assert qwen_response.status_code == 200
    qwen_voices = qwen_response.json().get("voices", [])
    qwen_names = {voice.get("name") for voice in qwen_voices}

    chatter_response = client.get("/api/chatterbox/voices")
    assert chatter_response.status_code == 200
    chatter_voices = chatter_response.json().get("voices", [])
    chatter_names = {voice.get("name") for voice in chatter_voices}

    for voice_name in SHIPPED_CLONE_VOICES:
        assert voice_name in qwen_names
        assert voice_name in chatter_names

    default_sources = {voice.get("name"): voice.get("source") for voice in qwen_voices}
    for voice_name in SHIPPED_CLONE_VOICES:
        assert default_sources.get(voice_name) == "default"
