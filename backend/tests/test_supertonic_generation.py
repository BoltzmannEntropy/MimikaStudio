from pathlib import Path

from fastapi.testclient import TestClient

import main


class _StubSupertonicEngine:
    def __init__(self) -> None:
        self.outputs_dir = Path("/tmp/unused-supertonic")

    def generate(self, text, voice, params, model_name, model_dir):  # noqa: D401
        file_path = self.outputs_dir / "supertonic-F1-test.wav"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_bytes(b"RIFF")
        return file_path


def test_supertonic_generate_uses_runtime_outputs_dir(tmp_path, monkeypatch):
    client = TestClient(main.app)
    runtime_outputs = tmp_path / "runtime-outputs"
    runtime_outputs.mkdir(parents=True, exist_ok=True)

    engine = _StubSupertonicEngine()
    monkeypatch.setattr(main, "outputs_dir", runtime_outputs)
    monkeypatch.setattr(main, "get_supertonic_engine", lambda: engine)
    monkeypatch.setattr(main, "_ensure_named_model_ready", lambda *args, **kwargs: tmp_path / "model")

    response = client.post(
        "/api/supertonic/generate",
        json={"text": "hello world", "voice": "F1"},
    )
    assert response.status_code == 200

    payload = response.json()
    assert engine.outputs_dir == runtime_outputs
    assert payload["filename"] == "supertonic-F1-test.wav"
    assert payload["audio_url"] == "/audio/supertonic-F1-test.wav"
    assert (runtime_outputs / payload["filename"]).exists()
