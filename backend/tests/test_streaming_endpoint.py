"""Test streaming generation endpoint."""
from fastapi.testclient import TestClient

import main

app = main.app


def test_streaming_endpoint_requires_params():
    """Test that streaming endpoint validates parameters."""
    client = TestClient(app)
    # Custom mode without speaker should fail
    response = client.post("/api/qwen3/generate/stream", json={
        "text": "hi",
        "mode": "custom",
    })
    assert response.status_code == 400


def test_streaming_endpoint_returns_pcm_chunks(monkeypatch):
    """Streaming endpoint should return PCM chunked audio when generation succeeds."""
    client = TestClient(app)

    class _FakeEngine:
        def __init__(self):
            self.unloaded = False

        def get_saved_voices(self):
            return [{
                "name": "Natasha",
                "audio_path": "/tmp/natasha.wav",
                "transcript": "hello world",
            }]

        def stream_voice_clone_pcm(self, **_kwargs):
            yield b"\x00\x00" * 64
            yield b"\x01\x00" * 64

        def unload(self):
            self.unloaded = True

    fake_engine = _FakeEngine()
    monkeypatch.setattr(main, "get_qwen3_engine", lambda **_kwargs: fake_engine)

    response = client.post("/api/qwen3/generate/stream", json={
        "text": "hello",
        "mode": "clone",
        "voice_name": "Natasha",
    })

    assert response.status_code == 200
    assert "audio/L16" in response.headers.get("content-type", "")
    assert response.headers.get("x-audio-format") == "pcm_s16le"
    assert response.headers.get("x-audio-sample-rate") == "24000"
    assert len(response.content) > 0
