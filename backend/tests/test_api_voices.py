"""Test voice management endpoints."""
from fastapi.testclient import TestClient

from main import app


def test_list_qwen3_voices():
    """Test listing Qwen3 voices."""
    client = TestClient(app)
    response = client.get("/api/qwen3/voices")
    assert response.status_code == 200
    assert "voices" in response.json()


def test_list_qwen3_speakers():
    """Test listing preset speakers."""
    client = TestClient(app)
    response = client.get("/api/qwen3/speakers")
    assert response.status_code == 200
    data = response.json()
    assert "speakers" in data
    assert len(data["speakers"]) == 9  # 9 preset speakers
    assert "Ryan" in data["speakers"]
    assert "Aiden" in data["speakers"]

