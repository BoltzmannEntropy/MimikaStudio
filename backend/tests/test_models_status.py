"""Tests for model manager status payloads."""

from fastapi.testclient import TestClient

import main


def test_models_status_includes_supported_engines():
    """Status payload should list the shipped model families."""
    client = TestClient(main.app)
    response = client.get("/api/models/status")
    assert response.status_code == 200

    models = response.json()["models"]
    names = {m["name"] for m in models}
    assert "Kokoro" in names
    assert "Supertonic-2" in names
    assert "Chatterbox Multilingual" in names


def test_models_status_includes_download_progress_fields():
    repo_key = "hf:Supertone/supertonic-2"
    with main._download_status_lock:
        main._download_status[repo_key] = {
            "status": "downloading",
            "error": None,
            "path": None,
            "downloaded_bytes": 123456789,
            "expected_bytes": 300000000,
            "progress_fraction": 0.4115,
        }

    try:
        client = TestClient(main.app)
        response = client.get("/api/models/status")
        assert response.status_code == 200
        models = response.json()["models"]
        by_name = {m["name"]: m for m in models}

        status = by_name["Supertonic-2"]
        assert status["download_status"] == "downloading"
        assert status["downloaded_bytes"] == 123456789
        assert status["expected_bytes"] == 300000000
        assert status["download_progress"] == 0.4115
    finally:
        with main._download_status_lock:
            main._download_status.pop(repo_key, None)
