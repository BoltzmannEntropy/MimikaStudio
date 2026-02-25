"""Comprehensive tests for every endpoint in the MimikaStudio backend API.

Tests API contract, validation, error handling, and response structure.
Tests do NOT require actual model loading -- they exercise the HTTP layer
with the FastAPI TestClient.

Grouped by endpoint category:
  - System
  - Kokoro
  - Qwen3
  - Chatterbox
  - Unified Voices
  - Audiobook
  - Audio Library (TTS + Voice Clone)
  - Samples
  - LLM Config
  - IPA
"""

import io
import struct
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
from fastapi.testclient import TestClient

from main import app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_minimal_wav(
    num_channels: int = 1,
    sample_rate: int = 16000,
    bits_per_sample: int = 16,
    num_samples: int = 16000,  # 1 second of audio
) -> io.BytesIO:
    """Create a minimal valid WAV file in memory."""
    data_size = num_samples * num_channels * (bits_per_sample // 8)
    buf = io.BytesIO()
    # RIFF header
    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + data_size))
    buf.write(b"WAVE")
    # fmt sub-chunk
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))                     # sub-chunk size
    buf.write(struct.pack("<H", 1))                      # PCM format
    buf.write(struct.pack("<H", num_channels))
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * num_channels * bits_per_sample // 8))
    buf.write(struct.pack("<H", num_channels * bits_per_sample // 8))
    buf.write(struct.pack("<H", bits_per_sample))
    # data sub-chunk
    buf.write(b"data")
    buf.write(struct.pack("<I", data_size))
    buf.write(b"\x00" * data_size)
    buf.seek(0)
    return buf


@pytest.fixture(scope="module")
def client():
    """Create a reusable TestClient for all tests in this module."""
    with TestClient(app) as c:
        yield c


# ===================================================================
# SYSTEM ENDPOINTS (3)
# ===================================================================

class TestSystemEndpoints:
    """GET /api/health, GET /api/system/info, GET /api/system/stats"""

    def test_health_returns_200(self, client):
        resp = client.get("/api/health")
        assert resp.status_code == 200

    def test_health_has_status_key(self, client):
        data = client.get("/api/health").json()
        assert "status" in data
        assert data["status"] == "ok"

    def test_health_has_service_key(self, client):
        data = client.get("/api/health").json()
        assert "service" in data
        assert data["service"] == "mimikastudio"

    def test_system_info_returns_200(self, client):
        resp = client.get("/api/system/info")
        assert resp.status_code == 200

    def test_system_info_has_required_fields(self, client):
        data = client.get("/api/system/info").json()
        for key in ("python_version", "device", "os", "arch", "torch_version", "models"):
            assert key in data, f"Missing key: {key}"

    def test_system_info_models_have_engines(self, client):
        data = client.get("/api/system/info").json()
        models = data["models"]
        assert "kokoro" in models
        assert "qwen3" in models
        assert "chatterbox" in models

    def test_system_stats_returns_200(self, client):
        resp = client.get("/api/system/stats")
        assert resp.status_code == 200

    def test_system_stats_has_required_fields(self, client):
        data = client.get("/api/system/stats").json()
        assert "cpu_percent" in data
        assert "ram_used_gb" in data
        assert "ram_total_gb" in data
        assert "ram_percent" in data
        assert "gpu" in data  # may be None

    def test_system_stats_values_are_numeric(self, client):
        data = client.get("/api/system/stats").json()
        assert isinstance(data["cpu_percent"], (int, float))
        assert isinstance(data["ram_used_gb"], (int, float))
        assert isinstance(data["ram_total_gb"], (int, float))

    def test_system_folders_returns_200(self, client):
        resp = client.get("/api/system/folders")
        assert resp.status_code == 200

    def test_system_folders_has_paths(self, client):
        data = client.get("/api/system/folders").json()
        assert "folders" in data
        assert isinstance(data["folders"], list)
        assert len(data["folders"]) > 0


# ===================================================================
# KOKORO ENDPOINTS (4)
# ===================================================================

class TestKokoroEndpoints:
    """Kokoro TTS voice listing, generation, and audio management."""

    # -- GET /api/kokoro/voices --
    def test_kokoro_voices_returns_200(self, client):
        resp = client.get("/api/kokoro/voices")
        assert resp.status_code == 200

    def test_kokoro_voices_has_voices_list(self, client):
        data = client.get("/api/kokoro/voices").json()
        assert "voices" in data
        assert isinstance(data["voices"], list)
        assert len(data["voices"]) > 0

    def test_kokoro_voices_has_default(self, client):
        data = client.get("/api/kokoro/voices").json()
        assert "default" in data

    def test_kokoro_voices_entry_structure(self, client):
        data = client.get("/api/kokoro/voices").json()
        voice = data["voices"][0]
        for key in ("code", "name", "gender", "grade", "is_default"):
            assert key in voice, f"Missing key: {key}"

    # -- POST /api/kokoro/generate --
    def test_kokoro_generate_missing_text_returns_422(self, client):
        resp = client.post("/api/kokoro/generate", json={})
        assert resp.status_code == 422

    def test_kokoro_generate_valid_body_shape(self, client):
        """Sending a valid body should at least not return 422.
        It may return 503 if kokoro is not installed, or 500/200 otherwise."""
        resp = client.post("/api/kokoro/generate", json={
            "text": "Hello world",
            "voice": "bf_emma",
            "speed": 1.0,
        })
        # Should not be a validation error
        assert resp.status_code != 422

    # -- GET /api/kokoro/audio/list --
    def test_kokoro_audio_list_returns_200(self, client):
        resp = client.get("/api/kokoro/audio/list")
        assert resp.status_code == 200

    def test_kokoro_audio_list_structure(self, client):
        data = client.get("/api/kokoro/audio/list").json()
        assert "audio_files" in data
        assert "total" in data
        assert isinstance(data["audio_files"], list)

    # -- DELETE /api/kokoro/audio/{filename} --
    def test_kokoro_audio_delete_nonexistent_returns_404(self, client):
        resp = client.delete("/api/kokoro/audio/kokoro-bf_emma-nonexistent.wav")
        assert resp.status_code == 404

    def test_kokoro_audio_delete_invalid_filename_returns_400(self, client):
        resp = client.delete("/api/kokoro/audio/badname.wav")
        assert resp.status_code == 400


# ===================================================================
# QWEN3 ENDPOINTS (12)
# ===================================================================

class TestQwen3Generation:
    """POST /api/qwen3/generate and POST /api/qwen3/generate/stream"""

    def test_generate_clone_requires_voice_name(self, client):
        resp = client.post("/api/qwen3/generate", json={
            "text": "hello",
            "mode": "clone",
        })
        assert resp.status_code == 400
        assert "voice_name" in resp.json()["detail"].lower()

    def test_generate_custom_requires_speaker(self, client):
        resp = client.post("/api/qwen3/generate", json={
            "text": "hello",
            "mode": "custom",
        })
        assert resp.status_code == 400
        assert "speaker" in resp.json()["detail"].lower()

    def test_generate_invalid_mode(self, client):
        resp = client.post("/api/qwen3/generate", json={
            "text": "hello",
            "mode": "invalid",
        })
        assert resp.status_code == 400

    def test_generate_missing_text_returns_422(self, client):
        resp = client.post("/api/qwen3/generate", json={"mode": "clone"})
        assert resp.status_code == 422

    def test_generate_stream_missing_text_returns_422(self, client):
        resp = client.post("/api/qwen3/generate/stream", json={"mode": "clone"})
        assert resp.status_code == 422

    def test_generate_clone_invalid_reference_audio_returns_400(self, client, tmp_path):
        bad_audio = tmp_path / "bad.wav"
        bad_audio.write_bytes(b"this-is-not-valid-audio")

        engine = MagicMock()
        engine.get_saved_voices.return_value = [
            {"name": "badvoice", "audio_path": str(bad_audio), "transcript": ""}
        ]

        with patch("main._ensure_qwen3_model_ready"), patch(
            "main.get_qwen3_engine", return_value=engine
        ):
            resp = client.post(
                "/api/qwen3/generate",
                json={
                    "text": "hello world",
                    "mode": "clone",
                    "voice_name": "badvoice",
                    "model_size": "0.6B",
                    "model_quantization": "bf16",
                },
            )
        assert resp.status_code == 400
        assert "cannot be decoded" in str(resp.json()).lower()


class TestQwen3Voices:
    """Voice CRUD: list, upload, delete, update, audio preview."""

    def test_list_voices_returns_200(self, client):
        resp = client.get("/api/qwen3/voices")
        assert resp.status_code == 200

    def test_list_voices_has_voices_key(self, client):
        data = client.get("/api/qwen3/voices").json()
        assert "voices" in data

    def test_upload_voice_with_form_data(self, client):
        """Upload a minimal WAV file as a new voice sample."""
        wav = _make_minimal_wav()
        resp = client.post(
            "/api/qwen3/voices",
            data={"name": "__test_upload_voice__", "transcript": "hello world"},
            files={"file": ("test.wav", wav, "audio/wav")},
        )
        # Should succeed (200) or engine not installed (503/500)
        assert resp.status_code in (200, 500, 503)

    def test_upload_voice_does_not_require_engine_load(self, client):
        """Uploading voices should work even if Qwen3 model runtime is unavailable."""
        wav = _make_minimal_wav()
        with patch("main.get_qwen3_engine", side_effect=ImportError("mlx unavailable")):
            resp = client.post(
                "/api/qwen3/voices",
                data={"name": "__test_upload_no_engine__", "transcript": "hello world"},
                files={"file": ("test.wav", wav, "audio/wav")},
            )
        assert resp.status_code == 200

    def test_upload_voice_without_transcript_is_allowed(self, client):
        """Transcript is optional for Qwen3 upload."""
        wav = _make_minimal_wav()
        resp = client.post(
            "/api/qwen3/voices",
            data={"name": "__test_upload_no_transcript__"},
            files={"file": ("test.wav", wav, "audio/wav")},
        )
        assert resp.status_code == 200

    def test_delete_voice_nonexistent_returns_404(self, client):
        resp = client.delete("/api/qwen3/voices/__surely_does_not_exist__")
        assert resp.status_code == 404

    def test_update_voice_nonexistent_returns_404(self, client):
        resp = client.put(
            "/api/qwen3/voices/__surely_does_not_exist__",
            data={"transcript": "updated"},
        )
        assert resp.status_code == 404

    def test_voice_audio_nonexistent_returns_404(self, client):
        resp = client.get("/api/qwen3/voices/__surely_does_not_exist__/audio")
        assert resp.status_code == 404

    def test_voice_audio_invalid_name_returns_400(self, client):
        resp = client.get("/api/qwen3/voices/../../etc/passwd/audio")
        assert resp.status_code in (400, 404, 422)


class TestQwen3VoiceUploadDeleteWorkflow:
    """Workflow test: upload a voice, verify in list, delete, verify gone."""

    VOICE_NAME = "__test_wf_qwen3__"

    def _cleanup(self, client):
        """Best-effort cleanup."""
        client.delete(f"/api/qwen3/voices/{self.VOICE_NAME}")

    def test_upload_list_delete_lifecycle(self, client):
        self._cleanup(client)

        # Upload
        wav = _make_minimal_wav()
        upload_resp = client.post(
            "/api/qwen3/voices",
            data={"name": self.VOICE_NAME, "transcript": "test transcript"},
            files={"file": ("test.wav", wav, "audio/wav")},
        )
        if upload_resp.status_code in (503, 500):
            pytest.skip("Qwen3 engine not installed; skipping workflow test")

        assert upload_resp.status_code == 200

        # Verify in list
        list_resp = client.get("/api/qwen3/voices")
        assert list_resp.status_code == 200
        names = [v["name"] for v in list_resp.json()["voices"]]
        assert self.VOICE_NAME in names

        # Delete
        del_resp = client.delete(f"/api/qwen3/voices/{self.VOICE_NAME}")
        assert del_resp.status_code == 200

        # Verify gone
        list_resp2 = client.get("/api/qwen3/voices")
        names2 = [v["name"] for v in list_resp2.json()["voices"]]
        assert self.VOICE_NAME not in names2


class TestQwen3Metadata:
    """Speakers, models, languages, info, clear-cache."""

    def test_speakers_returns_200(self, client):
        resp = client.get("/api/qwen3/speakers")
        assert resp.status_code == 200

    def test_speakers_has_9_entries(self, client):
        data = client.get("/api/qwen3/speakers").json()
        assert "speakers" in data
        assert len(data["speakers"]) == 9

    def test_speakers_known_names(self, client):
        data = client.get("/api/qwen3/speakers").json()
        assert "Ryan" in data["speakers"]
        assert "Aiden" in data["speakers"]
        assert "Sohee" in data["speakers"]

    def test_models_returns_200(self, client):
        resp = client.get("/api/qwen3/models")
        assert resp.status_code == 200

    def test_models_has_models_list(self, client):
        data = client.get("/api/qwen3/models").json()
        assert "models" in data
        assert isinstance(data["models"], list)
        assert len(data["models"]) > 0

    def test_models_entry_structure(self, client):
        data = client.get("/api/qwen3/models").json()
        model = data["models"][0]
        for key in ("name", "engine", "mode", "size_gb"):
            assert key in model, f"Missing key: {key}"

    def test_languages_returns_200(self, client):
        resp = client.get("/api/qwen3/languages")
        assert resp.status_code == 200

    def test_languages_has_list(self, client):
        data = client.get("/api/qwen3/languages").json()
        assert "languages" in data
        assert isinstance(data["languages"], list)
        assert len(data["languages"]) > 0

    def test_languages_contains_english(self, client):
        data = client.get("/api/qwen3/languages").json()
        assert "English" in data["languages"]

    def test_info_returns_200(self, client):
        resp = client.get("/api/qwen3/info")
        assert resp.status_code == 200

    def test_info_has_name(self, client):
        data = client.get("/api/qwen3/info").json()
        assert "name" in data

    def test_clear_cache_returns_200(self, client):
        resp = client.post("/api/qwen3/clear-cache")
        assert resp.status_code == 200

    def test_clear_cache_has_message(self, client):
        data = client.post("/api/qwen3/clear-cache").json()
        assert "message" in data


# ===================================================================
# CHATTERBOX ENDPOINTS (8)
# ===================================================================

class TestChatterboxGeneration:
    """POST /api/chatterbox/generate"""

    def test_generate_missing_text_returns_422(self, client):
        resp = client.post("/api/chatterbox/generate", json={})
        assert resp.status_code == 422

    def test_generate_missing_voice_name_returns_422(self, client):
        resp = client.post("/api/chatterbox/generate", json={"text": "hello"})
        assert resp.status_code == 422

    def test_generate_valid_body_not_422(self, client):
        """A valid body shape should not trigger 422."""
        resp = client.post("/api/chatterbox/generate", json={
            "text": "Hello world",
            "voice_name": "some_voice",
        })
        # Should not be a validation error; could be 404 (voice not found),
        # 503 (engine not installed), or 200
        assert resp.status_code != 422


class TestChatterboxVoices:
    """Voice CRUD: list, upload, delete, update, audio preview."""

    def test_list_voices_returns_200(self, client):
        resp = client.get("/api/chatterbox/voices")
        assert resp.status_code == 200

    def test_list_voices_has_voices_key(self, client):
        data = client.get("/api/chatterbox/voices").json()
        assert "voices" in data

    def test_upload_voice(self, client):
        wav = _make_minimal_wav()
        resp = client.post(
            "/api/chatterbox/voices",
            data={"name": "__test_cb_upload__", "transcript": "test"},
            files={"file": ("test.wav", wav, "audio/wav")},
        )
        # 200 on success, possibly 503/500 if engine not installed
        assert resp.status_code in (200, 500, 503)
        # Clean up
        client.delete("/api/chatterbox/voices/__test_cb_upload__")

    def test_delete_voice_nonexistent_returns_404(self, client):
        resp = client.delete("/api/chatterbox/voices/__surely_does_not_exist__")
        assert resp.status_code == 404

    def test_update_voice_nonexistent_returns_404(self, client):
        resp = client.put(
            "/api/chatterbox/voices/__surely_does_not_exist__",
            data={"transcript": "updated"},
        )
        assert resp.status_code == 404

    def test_voice_audio_nonexistent_returns_404(self, client):
        resp = client.get("/api/chatterbox/voices/__surely_does_not_exist__/audio")
        assert resp.status_code == 404

    def test_voice_audio_invalid_name_returns_400(self, client):
        resp = client.get("/api/chatterbox/voices/../etc/audio")
        assert resp.status_code in (400, 404, 422)


class TestChatterboxVoiceUploadDeleteWorkflow:
    """Workflow test: upload -> verify -> delete -> verify gone."""

    VOICE_NAME = "__test_wf_chatterbox__"

    def _cleanup(self, client):
        client.delete(f"/api/chatterbox/voices/{self.VOICE_NAME}")

    def test_upload_list_delete_lifecycle(self, client):
        self._cleanup(client)

        wav = _make_minimal_wav()
        upload_resp = client.post(
            "/api/chatterbox/voices",
            data={"name": self.VOICE_NAME, "transcript": "lifecycle test"},
            files={"file": ("test.wav", wav, "audio/wav")},
        )
        if upload_resp.status_code in (503, 500):
            pytest.skip("Chatterbox engine not installed; skipping workflow test")

        assert upload_resp.status_code == 200

        # Verify in list
        list_data = client.get("/api/chatterbox/voices").json()
        names = [v["name"] for v in list_data["voices"]]
        assert self.VOICE_NAME in names

        # Delete
        del_resp = client.delete(f"/api/chatterbox/voices/{self.VOICE_NAME}")
        assert del_resp.status_code == 200

        # Verify gone
        list_data2 = client.get("/api/chatterbox/voices").json()
        names2 = [v["name"] for v in list_data2["voices"]]
        assert self.VOICE_NAME not in names2


class TestChatterboxMetadata:
    """Languages and info."""

    def test_languages_returns_200(self, client):
        resp = client.get("/api/chatterbox/languages")
        assert resp.status_code == 200

    def test_languages_has_list(self, client):
        data = client.get("/api/chatterbox/languages").json()
        assert "languages" in data
        assert isinstance(data["languages"], list)

    def test_info_returns_200(self, client):
        resp = client.get("/api/chatterbox/info")
        assert resp.status_code == 200

    def test_info_has_name(self, client):
        data = client.get("/api/chatterbox/info").json()
        assert "name" in data


# ===================================================================
# UNIFIED VOICES (1)
# ===================================================================

class TestUnifiedVoices:
    """GET /api/voices/custom"""

    def test_custom_voices_returns_200(self, client):
        resp = client.get("/api/voices/custom")
        assert resp.status_code == 200

    def test_custom_voices_has_voices_list(self, client):
        data = client.get("/api/voices/custom").json()
        assert "voices" in data
        assert isinstance(data["voices"], list)

    def test_custom_voices_has_total(self, client):
        data = client.get("/api/voices/custom").json()
        assert "total" in data
        assert isinstance(data["total"], int)


# ===================================================================
# AUDIOBOOK ENDPOINTS (6)
# ===================================================================

class TestAudiobookGeneration:
    """POST /api/audiobook/generate and POST /api/audiobook/generate-from-file"""

    def test_generate_missing_text_returns_422(self, client):
        resp = client.post("/api/audiobook/generate", json={})
        assert resp.status_code == 422

    def test_generate_empty_text_returns_400(self, client):
        resp = client.post("/api/audiobook/generate", json={
            "text": "   ",
            "title": "Test",
        })
        assert resp.status_code == 400

    def test_generate_valid_body_not_422(self, client):
        """Valid body should not be a validation error."""
        resp = client.post("/api/audiobook/generate", json={
            "text": "Once upon a time there was a test.",
            "title": "Test Audiobook",
        })
        # May be 200 (job created) or 500/503 if engine not installed
        assert resp.status_code != 422

    def test_generate_from_file_without_file_returns_422(self, client):
        resp = client.post("/api/audiobook/generate-from-file")
        assert resp.status_code == 422

    def test_generate_from_file_with_txt(self, client):
        """Upload a minimal .txt file."""
        content = b"This is a test audiobook content for testing."
        resp = client.post(
            "/api/audiobook/generate-from-file",
            files={"file": ("test.txt", io.BytesIO(content), "text/plain")},
            data={"title": "Test Book", "voice": "bf_emma"},
        )
        # 200, 400, 500 or 503 are all acceptable; just not 422
        assert resp.status_code != 422


class TestAudiobookStatus:
    """GET /api/audiobook/status/{job_id}"""

    def test_status_nonexistent_returns_404(self, client):
        resp = client.get("/api/audiobook/status/nonexistent-job-id")
        assert resp.status_code == 404

    def test_status_404_has_detail(self, client):
        resp = client.get("/api/audiobook/status/nonexistent-job-id")
        assert "detail" in resp.json()


class TestAudiobookCancel:
    """POST /api/audiobook/cancel/{job_id}"""

    def test_cancel_nonexistent_returns_404(self, client):
        resp = client.post("/api/audiobook/cancel/nonexistent-job-id")
        assert resp.status_code == 404


class TestAudiobookList:
    """GET /api/audiobook/list"""

    def test_list_returns_200(self, client):
        resp = client.get("/api/audiobook/list")
        assert resp.status_code == 200

    def test_list_has_audiobooks_key(self, client):
        data = client.get("/api/audiobook/list").json()
        assert "audiobooks" in data
        assert isinstance(data["audiobooks"], list)

    def test_list_has_total(self, client):
        data = client.get("/api/audiobook/list").json()
        assert "total" in data


class TestAudiobookDelete:
    """DELETE /api/audiobook/{job_id}"""

    def test_delete_nonexistent_returns_404(self, client):
        resp = client.delete("/api/audiobook/nonexistent-job-id")
        assert resp.status_code == 404


# ===================================================================
# AUDIO LIBRARY - TTS (2)
# ===================================================================

class TestTTSAudioLibrary:
    """GET /api/tts/audio/list and DELETE /api/tts/audio/{filename}"""

    def test_list_returns_200(self, client):
        resp = client.get("/api/tts/audio/list")
        assert resp.status_code == 200

    def test_list_has_audio_files_key(self, client):
        data = client.get("/api/tts/audio/list").json()
        assert "audio_files" in data
        assert "total" in data

    def test_delete_nonexistent_returns_404(self, client):
        resp = client.delete("/api/tts/audio/kokoro-nonexistent.wav")
        assert resp.status_code == 404

    def test_delete_invalid_filename_returns_400(self, client):
        resp = client.delete("/api/tts/audio/badname.mp3")
        assert resp.status_code == 400


# ===================================================================
# AUDIO LIBRARY - VOICE CLONE (2)
# ===================================================================

class TestVoiceCloneAudioLibrary:
    """GET /api/voice-clone/audio/list and DELETE /api/voice-clone/audio/{filename}"""

    def test_list_returns_200(self, client):
        resp = client.get("/api/voice-clone/audio/list")
        assert resp.status_code == 200

    def test_list_has_audio_files_key(self, client):
        data = client.get("/api/voice-clone/audio/list").json()
        assert "audio_files" in data
        assert "total" in data

    def test_delete_nonexistent_returns_404(self, client):
        resp = client.delete("/api/voice-clone/audio/qwen3-nonexistent.wav")
        assert resp.status_code == 404

    def test_delete_invalid_filename_returns_400(self, client):
        resp = client.delete("/api/voice-clone/audio/badname.wav")
        assert resp.status_code == 400

    def test_delete_chatterbox_nonexistent_returns_404(self, client):
        resp = client.delete("/api/voice-clone/audio/chatterbox-nonexistent.wav")
        assert resp.status_code == 404


# ===================================================================
# SAMPLES ENDPOINTS (3)
# ===================================================================

class TestSamples:
    """GET /api/samples/{engine}, GET /api/pregenerated, GET /api/voice-samples"""

    def test_samples_kokoro_returns_200(self, client):
        resp = client.get("/api/samples/kokoro")
        assert resp.status_code == 200

    def test_samples_kokoro_has_samples(self, client):
        data = client.get("/api/samples/kokoro").json()
        assert "engine" in data
        assert data["engine"] == "kokoro"
        assert "samples" in data
        assert isinstance(data["samples"], list)

    def test_samples_invalid_engine_returns_400(self, client):
        resp = client.get("/api/samples/nonexistent_engine")
        assert resp.status_code == 400

    def test_pregenerated_returns_200(self, client):
        resp = client.get("/api/pregenerated")
        assert resp.status_code == 200

    def test_pregenerated_has_samples(self, client):
        data = client.get("/api/pregenerated").json()
        assert "samples" in data
        assert isinstance(data["samples"], list)

    def test_pregenerated_with_engine_filter(self, client):
        resp = client.get("/api/pregenerated?engine=kokoro")
        assert resp.status_code == 200
        data = resp.json()
        assert "samples" in data

    def test_voice_samples_returns_200(self, client):
        resp = client.get("/api/voice-samples")
        assert resp.status_code == 200

    def test_voice_samples_has_samples(self, client):
        data = client.get("/api/voice-samples").json()
        assert "samples" in data
        assert isinstance(data["samples"], list)
        assert "total" in data


# ===================================================================
# REMOVED LEGACY ENDPOINTS (LLM/IPA)
# ===================================================================

class TestRemovedLegacyEndpoints:
    """LLM/IPA endpoints were intentionally removed from production surface."""

    def test_llm_config_endpoints_return_404(self, client):
        assert client.get("/api/llm/config").status_code == 404
        assert client.post("/api/llm/config", json={}).status_code == 404
        assert client.get("/api/llm/ollama/models").status_code == 404

    def test_ipa_endpoints_return_404(self, client):
        assert client.get("/api/ipa/sample").status_code == 404
        assert client.get("/api/ipa/samples").status_code == 404
        assert client.post("/api/ipa/generate", json={"text": "hello"}).status_code == 404
        assert client.get("/api/ipa/pregenerated").status_code == 404
        assert client.post("/api/ipa/save-output").status_code == 404


# ===================================================================
# EDGE CASES & CROSS-CUTTING CONCERNS
# ===================================================================

class TestEdgeCases:
    """Miscellaneous edge cases and cross-cutting concerns."""

    def test_unknown_route_returns_404(self, client):
        resp = client.get("/api/this-does-not-exist")
        assert resp.status_code == 404

    def test_health_method_not_allowed(self, client):
        resp = client.post("/api/health")
        assert resp.status_code == 405

    def test_system_info_method_not_allowed(self, client):
        resp = client.post("/api/system/info")
        assert resp.status_code == 405

    def test_kokoro_generate_wrong_method(self, client):
        resp = client.get("/api/kokoro/generate")
        assert resp.status_code == 405

    def test_qwen3_generate_wrong_method(self, client):
        resp = client.get("/api/qwen3/generate")
        assert resp.status_code == 405

    def test_chatterbox_generate_wrong_method(self, client):
        resp = client.get("/api/chatterbox/generate")
        assert resp.status_code == 405

    def test_cors_headers_present(self, client):
        resp = client.options(
            "/api/health",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            },
        )
        # CORS middleware should add the header
        assert "access-control-allow-origin" in resp.headers

    def test_audiobook_generate_invalid_format(self, client):
        resp = client.post("/api/audiobook/generate", json={
            "text": "test text",
            "output_format": "ogg",
        })
        assert resp.status_code == 400

    def test_audiobook_generate_invalid_subtitle_format(self, client):
        resp = client.post("/api/audiobook/generate", json={
            "text": "test text",
            "subtitle_format": "ass",
        })
        assert resp.status_code == 400

    def test_audiobook_generate_negative_crossfade(self, client):
        resp = client.post("/api/audiobook/generate", json={
            "text": "test text",
            "crossfade_ms": -10,
        })
        assert resp.status_code == 400

    def test_audiobook_generate_zero_chunk_size(self, client):
        resp = client.post("/api/audiobook/generate", json={
            "text": "test text",
            "max_chars_per_chunk": 0,
        })
        assert resp.status_code == 400
