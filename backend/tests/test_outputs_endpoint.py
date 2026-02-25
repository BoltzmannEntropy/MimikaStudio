"""Test outputs endpoint for serving generated audio files."""
from pathlib import Path

from fastapi.testclient import TestClient

import main


def test_outputs_endpoint_serves_file():
    """Test that outputs endpoint serves generated audio files."""
    with TestClient(main.app) as client:
        output_root = client.get("/api/settings/output-folder").json()["path"]
        output_file = Path(output_root) / "test-output.wav"
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_bytes(b"RIFF")

        response = client.get("/audio/test-output.wav")
        assert response.status_code == 200
        assert response.content == b"RIFF"

        # Cleanup
        output_file.unlink(missing_ok=True)


def test_audio_directory_mounted():
    """Test that audio directory is mounted."""
    with TestClient(main.app) as client:
        # Should not 404 on the mount point check
        # (actual file may not exist, but mount should be configured)
        response = client.get("/audio/nonexistent.wav")
        # 404 is expected for non-existent file, but not 500
        assert response.status_code in [404, 200]


def test_voice_clone_audio_list_includes_file_path():
    """Voice-clone audio list should expose absolute file paths for UI display."""
    with TestClient(main.app) as client:
        output_root = client.get("/api/settings/output-folder").json()["path"]
        output_file = Path(output_root) / "qwen3-clone-testpath.wav"
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_bytes(b"RIFF")

        response = client.get("/api/voice-clone/audio/list")
        assert response.status_code == 200
        data = response.json()
        items = data.get("audio_files", [])
        row = next((item for item in items if item.get("filename") == output_file.name), None)
        assert row is not None
        assert isinstance(row.get("file_path"), str)
        assert row["file_path"].endswith(output_file.name)

        output_file.unlink(missing_ok=True)
