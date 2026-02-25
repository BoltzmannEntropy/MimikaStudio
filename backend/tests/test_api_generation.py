"""Test Qwen3-TTS generation endpoints."""
import time
from unittest.mock import patch

from fastapi.testclient import TestClient

from main import app


def test_qwen3_generate_clone_requires_voice():
    """Test that clone mode requires voice_name."""
    client = TestClient(app)
    response = client.post("/api/qwen3/generate", json={
        "text": "hello",
        "mode": "clone",
    })
    assert response.status_code == 400
    assert "voice_name" in response.json()["detail"].lower()


def test_qwen3_generate_custom_requires_speaker():
    """Test that custom mode requires speaker."""
    client = TestClient(app)
    response = client.post("/api/qwen3/generate", json={
        "text": "hello",
        "mode": "custom",
    })
    assert response.status_code == 400
    assert "speaker" in response.json()["detail"].lower()


def test_qwen3_generate_invalid_mode():
    """Test that invalid mode returns error."""
    client = TestClient(app)
    response = client.post("/api/qwen3/generate", json={
        "text": "hello",
        "mode": "invalid",
    })
    assert response.status_code == 400


def test_qwen3_generate_enqueue_creates_trackable_job(tmp_path):
    """Queued Qwen3 generation should return job_id and finish in /api/jobs/{id}."""
    client = TestClient(app)
    output_file = tmp_path / "qwen3-test.wav"
    output_file.write_bytes(b"RIFF")

    with patch("main._ensure_qwen3_model_ready"), patch(
        "main._run_qwen3_generation",
        return_value=(
            {"audio_url": "/audio/qwen3-test.wav", "filename": "qwen3-test.wav"},
            output_file,
        ),
    ):
        start = client.post(
            "/api/qwen3/generate",
            json={
                "text": "hello queued world",
                "mode": "clone",
                "voice_name": "Natasha",
                "enqueue": True,
            },
        )

        assert start.status_code == 200
        body = start.json()
        assert body["status"] == "started"
        job_id = body["job_id"]
        assert isinstance(job_id, str) and job_id

        final_job = None
        for _ in range(50):
            probe = client.get(f"/api/jobs/{job_id}")
            if probe.status_code == 200:
                job = probe.json()["job"]
                if job["status"] in {"completed", "failed"}:
                    final_job = job
                    break
            time.sleep(0.02)

        assert final_job is not None
        assert final_job["status"] == "completed"
        assert final_job["audio_url"] == "/audio/qwen3-test.wav"
