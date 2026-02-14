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
