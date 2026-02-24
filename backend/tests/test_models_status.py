"""Tests for model manager status payloads."""

from fastapi.testclient import TestClient

import main


def test_models_status_includes_cosyvoice3():
    """CosyVoice3 should appear as its own model row."""
    client = TestClient(main.app)
    response = client.get("/api/models/status")
    assert response.status_code == 200

    models = response.json()["models"]
    names = {m["name"] for m in models}
    assert "Supertonic-2" in names
    assert "CosyVoice3" in names


def test_models_status_keeps_cosyvoice3_download_state_independent():
    """CosyVoice3 should not inherit Supertonic download state."""
    repo_key = "hf:Supertone/supertonic-2"
    with main._download_status_lock:
        main._download_status[repo_key] = {
            "status": "downloading",
            "error": None,
            "path": None,
        }

    try:
        client = TestClient(main.app)
        response = client.get("/api/models/status")
        assert response.status_code == 200
        models = response.json()["models"]
        by_name = {m["name"]: m for m in models}

        assert by_name["Supertonic-2"]["download_status"] == "downloading"
        assert by_name["CosyVoice3"]["download_status"] != "downloading"
    finally:
        with main._download_status_lock:
            main._download_status.pop(repo_key, None)
