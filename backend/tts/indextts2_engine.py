"""IndexTTS-2 engine wrapper for voice cloning."""
from __future__ import annotations

import uuid
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import soundfile as sf
import torch
from scipy import signal

from .audio_utils import merge_audio_chunks
from .text_chunking import smart_chunk_text


class IndexTTS2Engine:
    """IndexTTS-2 voice cloning engine."""

    SAMPLE_RATE = 24000

    def __init__(self) -> None:
        self.model = None
        self.device: Optional[str] = None
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)

        self.sample_voices_dir = (
            Path(__file__).parent.parent / "data" / "samples" / "voices"
        )
        self.sample_voices_dir.mkdir(parents=True, exist_ok=True)

        self.user_voices_dir = (
            Path(__file__).parent.parent / "data" / "user_voices" / "qwen3"
        )
        self.user_voices_dir.mkdir(parents=True, exist_ok=True)

    def _get_device(self) -> str:
        if torch.cuda.is_available():
            return "cuda"
        return "cpu"

    def load_model(self):
        """Load the IndexTTS-2 model."""
        if self.model is not None:
            return self.model

        try:
            # Apply transformers compatibility patches before importing IndexTTS.
            # IndexTTS was built for transformers 4.52.x; several symbols were
            # removed in 4.57+ which Qwen3-TTS requires.
            from . import _indextts_compat
            _indextts_compat.apply()

            from indextts.infer import IndexTTS
        except ImportError as exc:
            raise ImportError(
                "indextts not installed. Install with: "
                "pip install --no-deps git+https://github.com/index-tts/index-tts.git"
            ) from exc

        self.device = self._get_device()
        self.model = IndexTTS(
            model_dir="IndexTeam/IndexTTS-v2",
            device=self.device,
        )
        return self.model

    def unload(self) -> None:
        """Free memory by unloading the model."""
        self.model = None
        if self.device and self.device.startswith("cuda"):
            torch.cuda.empty_cache()

    def _adjust_speed(self, audio: np.ndarray, speed: float) -> np.ndarray:
        if speed == 1.0:
            return audio
        speed = max(0.5, min(2.0, speed))
        original_length = len(audio)
        new_length = int(original_length / speed)
        if new_length == original_length:
            return audio
        return signal.resample(audio, new_length)

    def generate(
        self,
        text: str,
        voice_name: str,
        ref_audio_path: str,
        speed: float = 1.0,
        max_chars: int = 300,
        crossfade_ms: int = 0,
    ) -> Path:
        """Generate speech using IndexTTS-2 voice cloning."""
        self.load_model()

        chunks = (
            smart_chunk_text(text, max_chars=max_chars)
            if max_chars and len(text) > max_chars
            else [text]
        )
        chunks = [c for c in chunks if c.strip()]
        if not chunks:
            raise ValueError("Text cannot be empty")

        all_audio = []
        for chunk in chunks:
            # IndexTTS generates to a temp file, then we read it back
            temp_path = self.outputs_dir / f"_indextts2_temp_{uuid.uuid4().hex[:8]}.wav"
            try:
                self.model.infer(ref_audio_path, chunk, str(temp_path))
                audio, sr = sf.read(str(temp_path))
                audio = audio.astype(np.float32)
                if sr != self.SAMPLE_RATE:
                    audio = signal.resample(
                        audio, int(len(audio) * self.SAMPLE_RATE / sr)
                    )
                audio = self._adjust_speed(audio, speed)
                all_audio.append(audio)
            finally:
                temp_path.unlink(missing_ok=True)

        merged = merge_audio_chunks(all_audio, self.SAMPLE_RATE, crossfade_ms=crossfade_ms)
        short_uuid = str(uuid.uuid4())[:8]
        output_path = self.outputs_dir / f"indextts2-{voice_name}-{short_uuid}.wav"
        sf.write(output_path, merged, self.SAMPLE_RATE)
        return output_path

    def save_voice_sample(self, name: str, audio_path: str, transcript: str = "") -> dict:
        """Save a voice sample for later use."""
        import shutil

        src = Path(audio_path)
        dest = self.user_voices_dir / f"{name}.wav"
        shutil.copy2(src, dest)

        if transcript is not None:
            transcript_file = self.user_voices_dir / f"{name}.txt"
            transcript_file.write_text(transcript)

        return {
            "name": name,
            "audio_path": str(dest),
            "transcript": transcript or "",
            "source": "user",
        }

    def get_saved_voices(self) -> list:
        """Get list of saved voice samples."""
        voices = []
        merged = {}

        for wav_file in self.sample_voices_dir.glob("*.wav"):
            name = wav_file.stem
            transcript_file = self.sample_voices_dir / f"{name}.txt"
            transcript = transcript_file.read_text() if transcript_file.exists() else ""
            merged[name.lower()] = {
                "name": name,
                "audio_path": str(wav_file),
                "transcript": transcript,
                "source": "default",
            }

        for wav_file in self.user_voices_dir.glob("*.wav"):
            name = wav_file.stem
            transcript_file = self.user_voices_dir / f"{name}.txt"
            transcript = transcript_file.read_text() if transcript_file.exists() else ""
            merged[name.lower()] = {
                "name": name,
                "audio_path": str(wav_file),
                "transcript": transcript,
                "source": "user",
            }

        voices.extend(merged.values())
        return voices

    def get_model_info(self) -> dict:
        return {
            "name": "IndexTTS-2",
            "device": self.device or "not loaded",
            "sample_rate": self.SAMPLE_RATE,
            "features": ["voice_cloning"],
        }


_indextts2_engine: Optional[IndexTTS2Engine] = None


def get_indextts2_engine() -> IndexTTS2Engine:
    """Get or create the IndexTTS-2 engine."""
    global _indextts2_engine
    if _indextts2_engine is None:
        _indextts2_engine = IndexTTS2Engine()
    return _indextts2_engine
