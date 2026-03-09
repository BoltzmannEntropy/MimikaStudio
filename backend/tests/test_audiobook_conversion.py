import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

from tts import audiobook


def _write_test_wav(path: Path) -> None:
    samples = np.zeros(1600, dtype=np.float32)
    sf.write(str(path), samples, 16000)


def test_resolve_audio_converter_binary_supports_env_override(tmp_path, monkeypatch):
    fake_ffmpeg = tmp_path / "ffmpeg"
    fake_ffmpeg.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    fake_ffmpeg.chmod(0o755)

    monkeypatch.setenv("MIMIKA_FFMPEG_PATH", str(fake_ffmpeg))
    assert audiobook._resolve_audio_converter_binary() == str(fake_ffmpeg)


def test_convert_to_mp3_keeps_wav_when_no_converter(tmp_path, monkeypatch):
    wav_path = tmp_path / "sample.wav"
    mp3_path = tmp_path / "sample.mp3"
    _write_test_wav(wav_path)

    monkeypatch.setattr(audiobook, "_resolve_audio_converter_binary", lambda: None)
    output_path = audiobook._convert_to_mp3(wav_path, mp3_path)

    assert output_path == wav_path
    assert wav_path.exists()
    assert not mp3_path.exists()


def test_convert_to_mp3_keeps_wav_when_subprocess_fails(tmp_path, monkeypatch):
    wav_path = tmp_path / "sample.wav"
    mp3_path = tmp_path / "sample.mp3"
    _write_test_wav(wav_path)

    monkeypatch.setattr(audiobook, "_resolve_audio_converter_binary", lambda: "/tmp/ffmpeg")

    def _raise(*_args, **_kwargs):
        raise subprocess.CalledProcessError(
            returncode=1,
            cmd=["ffmpeg", "-i", str(wav_path)],
            stderr=b"conversion failed",
        )

    monkeypatch.setattr(audiobook.subprocess, "run", _raise)
    output_path = audiobook._convert_to_mp3(wav_path, mp3_path)

    assert output_path == wav_path
    assert wav_path.exists()
    assert not mp3_path.exists()
