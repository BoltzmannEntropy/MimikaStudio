"""Tests for unified voice prompt management and generation metrics endpoints."""

import io
import json
import subprocess
import struct
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

import main
from main import app


def _make_minimal_wav_bytes(num_samples: int = 24000) -> bytes:
    """Create a small valid mono PCM WAV payload."""
    num_channels = 1
    sample_rate = 24000
    bits_per_sample = 16
    data_size = num_samples * num_channels * (bits_per_sample // 8)
    buf = io.BytesIO()
    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + data_size))
    buf.write(b"WAVE")
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))
    buf.write(struct.pack("<H", 1))
    buf.write(struct.pack("<H", num_channels))
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * num_channels * bits_per_sample // 8))
    buf.write(struct.pack("<H", num_channels * bits_per_sample // 8))
    buf.write(struct.pack("<H", bits_per_sample))
    buf.write(b"data")
    buf.write(struct.pack("<I", data_size))
    buf.write(b"\x00" * data_size)
    return buf.getvalue()


def test_voice_prompt_crud_roundtrip():
    client = TestClient(app)
    voice_name = f"VoicePrompt{uuid.uuid4().hex[:8]}"
    wav_bytes = _make_minimal_wav_bytes()

    upload = client.post(
        "/api/voice-prompts",
        files={"file": (f"{voice_name}.wav", wav_bytes, "audio/wav")},
        data={
            "name": voice_name,
            "transcript": "hello voice prompt",
            "gender": "female",
            "language": "English",
            "source": "local",
        },
    )
    assert upload.status_code == 200
    uploaded_voice = upload.json()["voice"]
    assert uploaded_voice["name"] == voice_name
    assert uploaded_voice["source"] == "local"

    listed = client.get(f"/api/voice-prompts?search={voice_name}")
    assert listed.status_code == 200
    names = {item["name"] for item in listed.json()["voices"]}
    assert voice_name in names

    update = client.put(
        f"/api/voice-prompts/{voice_name}",
        data={"gender": "neutral", "language": "Spanish", "source": "external"},
    )
    assert update.status_code == 200
    updated_voice = update.json()["voice"]
    assert updated_voice["gender"] == "neutral"
    assert updated_voice["language"] == "Spanish"
    assert updated_voice["source"] == "external"

    preview = client.get(f"/api/voice-prompts/{voice_name}/audio")
    assert preview.status_code == 200

    delete = client.delete(f"/api/voice-prompts/{voice_name}")
    assert delete.status_code == 200


def test_voice_prompt_upload_duplicate_name_returns_409():
    client = TestClient(app)
    voice_name = f"VoicePromptDup{uuid.uuid4().hex[:8]}"
    wav_bytes = _make_minimal_wav_bytes()

    first = client.post(
        "/api/voice-prompts",
        files={"file": (f"{voice_name}.wav", wav_bytes, "audio/wav")},
        data={"name": voice_name},
    )
    assert first.status_code == 200

    second = client.post(
        "/api/voice-prompts",
        files={"file": (f"{voice_name}.wav", wav_bytes, "audio/wav")},
        data={"name": voice_name},
    )
    assert second.status_code == 409

    client.delete(f"/api/voice-prompts/{voice_name}")


def test_voice_prompt_import_youtube_rejects_non_youtube_url():
    client = TestClient(app)
    response = client.post(
        "/api/voice-prompts/import/youtube",
        json={
            "url": "https://example.com/video.mp4",
            "name": f"VoicePromptBadUrl{uuid.uuid4().hex[:8]}",
        },
    )
    assert response.status_code == 400
    assert "youtube.com" in response.json().get("detail", "").lower()


def test_voice_prompt_upload_cleanup_on_transcript_write_failure(monkeypatch):
    client = TestClient(app)
    voice_name = f"VoicePromptCleanup{uuid.uuid4().hex[:8]}"
    wav_bytes = _make_minimal_wav_bytes()
    expected_transcript = main.CLONER_USER_VOICES_DIR / f"{voice_name}.txt"
    expected_audio = main.CLONER_USER_VOICES_DIR / f"{voice_name}.wav"
    expected_meta = expected_audio.with_suffix(".meta.json")
    original_write_text = Path.write_text

    def flaky_write_text(self: Path, data: str, *args, **kwargs):
        if self == expected_transcript:
            raise OSError("simulated write failure")
        return original_write_text(self, data, *args, **kwargs)

    monkeypatch.setattr(Path, "write_text", flaky_write_text)

    response = client.post(
        "/api/voice-prompts",
        files={"file": (f"{voice_name}.wav", wav_bytes, "audio/wav")},
        data={"name": voice_name},
    )
    assert response.status_code == 500
    assert not expected_audio.exists()
    assert not expected_transcript.exists()
    assert not expected_meta.exists()


def test_voice_prompt_import_youtube_uses_url_timestamp(monkeypatch):
    client = TestClient(app)
    voice_name = f"VoicePromptYT{uuid.uuid4().hex[:8]}"
    executed_cmds: list[list[str]] = []

    def fake_which(name: str):
        if name in {"yt-dlp", "yt_dlp"}:
            return "/usr/local/bin/yt-dlp"
        if name in {"ffmpeg", "avconv"}:
            return "/usr/local/bin/ffmpeg"
        return None

    def fake_run(cmd, capture_output, text, timeout, check):
        executed_cmds.append(list(cmd))
        binary = str(cmd[0])
        if "yt-dlp" in binary:
            output_index = cmd.index("-o") + 1
            template = str(cmd[output_index])
            download_path = Path(template.replace("%(ext)s", "mp3"))
            download_path.parent.mkdir(parents=True, exist_ok=True)
            download_path.write_bytes(b"fake-mp3")
            return subprocess.CompletedProcess(
                cmd,
                0,
                stdout=f"{download_path}\n",
                stderr="",
            )
        if "ffmpeg" in binary:
            output_path = Path(cmd[-1])
            output_path.write_bytes(_make_minimal_wav_bytes(num_samples=24_000 * 20))
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="unsupported")

    monkeypatch.setattr(main.shutil, "which", fake_which)
    monkeypatch.setattr(main.subprocess, "run", fake_run)

    response = client.post(
        "/api/voice-prompts/import/youtube",
        json={
            "url": "https://www.youtube.com/watch?v=xg5y6Ao7VE4&t=88s",
            "name": voice_name,
            "transcript": "sample transcript",
        },
    )
    assert response.status_code == 200
    payload = response.json()["voice"]
    assert payload["name"] == voice_name
    assert payload["source"] == "external"
    assert payload["duration_sec"] >= 19.5

    ffmpeg_cmd = next((cmd for cmd in executed_cmds if "ffmpeg" in cmd[0]), None)
    assert ffmpeg_cmd is not None
    assert "-ss" in ffmpeg_cmd
    ss_idx = ffmpeg_cmd.index("-ss")
    assert ss_idx + 1 < len(ffmpeg_cmd)
    assert ffmpeg_cmd[ss_idx + 1].startswith("88")

    client.delete(f"/api/voice-prompts/{voice_name}")


def test_voice_prompt_import_youtube_preview_then_commit(monkeypatch):
    client = TestClient(app)
    voice_name = f"VoicePromptYTP{uuid.uuid4().hex[:8]}"

    def fake_which(name: str):
        if name in {"yt-dlp", "yt_dlp"}:
            return "/usr/local/bin/yt-dlp"
        if name in {"ffmpeg", "avconv"}:
            return "/usr/local/bin/ffmpeg"
        return None

    def fake_run(cmd, capture_output, text, timeout, check):
        binary = str(cmd[0])
        if "yt-dlp" in binary:
            output_index = cmd.index("-o") + 1
            template = str(cmd[output_index])
            download_path = Path(template.replace("%(ext)s", "mp3"))
            download_path.parent.mkdir(parents=True, exist_ok=True)
            download_path.write_bytes(b"fake-mp3")
            return subprocess.CompletedProcess(
                cmd,
                0,
                stdout=f"{download_path}\n",
                stderr="",
            )
        if "ffmpeg" in binary:
            output_path = Path(cmd[-1])
            output_path.write_bytes(_make_minimal_wav_bytes(num_samples=24_000 * 20))
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="unsupported")

    monkeypatch.setattr(main.shutil, "which", fake_which)
    monkeypatch.setattr(main.subprocess, "run", fake_run)

    preview = client.post(
        "/api/voice-prompts/import/youtube/preview",
        json={
            "url": "https://www.youtube.com/watch?v=xg5y6Ao7VE4&t=88s",
        },
    )
    assert preview.status_code == 200
    preview_payload = preview.json()
    preview_id = preview_payload.get("preview_id")
    assert preview_id
    assert (preview_payload.get("audio_url") or "").startswith("/audio/")

    commit = client.post(
        "/api/voice-prompts/import/youtube/commit",
        json={
            "preview_id": preview_id,
            "name": voice_name,
            "transcript": "preview transcript",
        },
    )
    assert commit.status_code == 200
    voice_payload = commit.json().get("voice", {})
    assert voice_payload.get("name") == voice_name
    assert voice_payload.get("source") == "external"
    assert (voice_payload.get("duration_sec") or 0) >= 19.5

    client.delete(f"/api/voice-prompts/{voice_name}")


def test_audio_metrics_endpoint_reads_sidecar(tmp_path):
    client = TestClient(app)
    filename = f"kokoro-metrics-{uuid.uuid4().hex[:6]}.wav"
    audio_path = main.outputs_dir / filename
    metrics_path = audio_path.with_suffix(".metrics.json")

    audio_path.write_bytes(_make_minimal_wav_bytes(num_samples=2400))
    metrics_payload = {
        "started_at": "2026-03-06T10:00:00Z",
        "completed_at": "2026-03-06T10:00:08Z",
        "total_time_seconds": 8.0,
        "total_chunks": 3,
        "chunk_durations_seconds": [2.1, 2.7, 3.2],
        "avg_chunk_time_seconds": 2.6667,
        "min_chunk_time_seconds": 2.1,
        "max_chunk_time_seconds": 3.2,
    }
    metrics_path.write_text(json.dumps(metrics_payload), encoding="utf-8")

    try:
        resp = client.get(f"/api/metrics/audio/{filename}")
        assert resp.status_code == 200
        body = resp.json()
        assert body["filename"] == filename
        assert body["metrics"]["total_chunks"] == 3
        assert body["metrics"]["chunk_durations_seconds"] == [2.1, 2.7, 3.2]
    finally:
        metrics_path.unlink(missing_ok=True)
        audio_path.unlink(missing_ok=True)
