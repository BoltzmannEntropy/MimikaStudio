"""Chatterbox Multilingual TTS engine wrapper for voice cloning."""
from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import soundfile as sf
from scipy import signal

from .audio_utils import merge_audio_chunks
from .text_chunking import smart_chunk_text

# Keep MLX import lazy to avoid backend startup aborts on machines without a
# usable Metal device context.
mx = None


_EVENT_TAG_PATTERN = re.compile(
    r"\[(clear\s+throat|sigh|shush|cough|groan|sniff|gasp|chuckle|laugh)\]",
    re.IGNORECASE,
)

_EVENT_TAG_EXAGGERATION_BOOST = {
    "clear throat": 0.15,
    "sigh": 0.25,
    "shush": 0.35,
    "cough": 0.30,
    "groan": 0.35,
    "sniff": 0.20,
    "gasp": 0.60,
    "chuckle": 0.45,
    "laugh": 0.65,
}


@dataclass
class ChatterboxParams:
    """Generation parameters for Chatterbox."""
    exaggeration: float = 0.5
    temperature: float = 0.8
    cfg_weight: float = 1.0
    seed: int = -1  # -1 = random


class ChatterboxEngine:
    """Chatterbox Multilingual TTS engine with voice cloning support."""

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
            Path(__file__).parent.parent / "data" / "user_voices" / "chatterbox"
        )
        self.user_voices_dir.mkdir(parents=True, exist_ok=True)

    def _get_device(self) -> str:
        if mx is not None and mx.metal.is_available():
            return "mlx"
        return "cpu"

    def load_model(self):
        """Load the Chatterbox model."""
        if self.model is not None:
            return self.model

        try:
            from mlx_audio.tts import load as load_tts_model
        except ImportError as exc:
            raise ImportError(
                "mlx-audio not installed. Install with: pip install -U mlx-audio"
            ) from exc

        self.device = self._get_device()
        self.model = load_tts_model("mlx-community/chatterbox-fp16")
        return self.model

    def unload(self) -> None:
        """Free memory by unloading the model."""
        self.model = None
        if mx is not None:
            mx.clear_cache()

    def _seed(self, seed: int) -> None:
        if seed >= 0:
            np.random.seed(seed)
            if mx is not None:
                mx.random.seed(seed)

    def _adjust_speed(self, audio: np.ndarray, speed: float) -> np.ndarray:
        if speed == 1.0:
            return audio
        speed = max(0.5, min(2.0, speed))
        original_length = len(audio)
        new_length = int(original_length / speed)
        if new_length == original_length:
            return audio
        return signal.resample(audio, new_length)

    @staticmethod
    def _clamp_exaggeration(value: float) -> float:
        return max(0.0, min(1.0, float(value)))

    def _build_expressive_segments(
        self,
        text: str,
        base_exaggeration: float,
        max_chars: int,
    ) -> list[tuple[str, float]]:
        """
        Interpret UI event tags as non-spoken control markers and apply
        boosted expressive delivery to following text segments.
        """
        raw_text = (text or "").strip()
        if not raw_text:
            return []

        base_exaggeration = self._clamp_exaggeration(base_exaggeration)
        matches = list(_EVENT_TAG_PATTERN.finditer(raw_text))
        if not matches:
            chunks = (
                smart_chunk_text(raw_text, max_chars=max_chars)
                if max_chars and len(raw_text) > max_chars
                else [raw_text]
            )
            return [(chunk, base_exaggeration) for chunk in chunks if chunk.strip()]

        segments: list[tuple[str, float]] = []
        cursor = 0
        current_exaggeration = base_exaggeration

        for match in matches:
            leading_text = raw_text[cursor:match.start()].strip()
            if leading_text:
                segments.append((leading_text, current_exaggeration))
                current_exaggeration = base_exaggeration

            tag = re.sub(r"\s+", " ", match.group(1).strip().lower())
            boosted_exaggeration = self._clamp_exaggeration(
                base_exaggeration + _EVENT_TAG_EXAGGERATION_BOOST.get(tag, 0.0)
            )
            current_exaggeration = boosted_exaggeration
            cursor = match.end()

        trailing_text = raw_text[cursor:].strip()
        if trailing_text:
            segments.append((trailing_text, current_exaggeration))

        expanded_segments: list[tuple[str, float]] = []
        for segment_text, segment_exaggeration in segments:
            chunks = (
                smart_chunk_text(segment_text, max_chars=max_chars)
                if max_chars and len(segment_text) > max_chars
                else [segment_text]
            )
            for chunk in chunks:
                chunk = chunk.strip()
                if chunk:
                    expanded_segments.append((chunk, segment_exaggeration))

        return expanded_segments

    def generate_voice_clone(
        self,
        text: str,
        voice_name: str,
        ref_audio_path: str,
        language: str = "en",
        speed: float = 1.0,
        params: Optional[ChatterboxParams] = None,
        max_chars: int = 300,
        crossfade_ms: int = 0,
    ) -> Path:
        """Generate speech using Chatterbox voice cloning."""
        self.load_model()
        if params is None:
            params = ChatterboxParams()
        params.exaggeration = self._clamp_exaggeration(params.exaggeration)

        chunks = self._build_expressive_segments(
            text=text,
            base_exaggeration=params.exaggeration,
            max_chars=max_chars,
        )
        if not chunks:
            raise ValueError("Text cannot be empty")

        language = (language or "en").lower()

        all_audio = []
        sample_rate = 24000
        for chunk, chunk_exaggeration in chunks:
            self._seed(params.seed)
            results = self.model.generate(  # type: ignore[call-arg]
                text=chunk,
                lang_code=language,
                ref_audio=ref_audio_path,
                exaggeration=chunk_exaggeration,
                temperature=params.temperature,
                cfg_weight=params.cfg_weight,
                verbose=False,
            )
            generated_chunks: list[np.ndarray] = []
            for result in results:
                sample_rate = int(getattr(result, "sample_rate", sample_rate))
                generated_chunks.append(np.asarray(result.audio, dtype=np.float32).reshape(-1))
            if not generated_chunks:
                continue
            audio = (
                generated_chunks[0]
                if len(generated_chunks) == 1
                else np.concatenate(generated_chunks)
            )
            audio = self._adjust_speed(audio, speed)
            all_audio.append(audio)

        if not all_audio:
            raise RuntimeError("No audio generated by Chatterbox")

        merged = merge_audio_chunks(all_audio, sample_rate, crossfade_ms=crossfade_ms)
        short_uuid = str(uuid.uuid4())[:8]
        output_path = self.outputs_dir / f"chatterbox-{voice_name}-{short_uuid}.wav"
        sf.write(output_path, merged, sample_rate)
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

    def get_languages(self) -> list[str]:
        return [
            "ar", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi",
            "it", "ja", "ko", "ms", "nl", "no", "pl", "pt", "ru", "sv",
            "sw", "tr", "zh",
        ]

    def get_model_info(self) -> dict:
        return {
            "name": "Chatterbox Multilingual TTS",
            "repo": "mlx-community/chatterbox-fp16",
            "backend": "mlx-audio",
            "device": self.device or "not loaded",
            "sample_rate": getattr(self.model, "sample_rate", None),
            "languages": self.get_languages(),
            "features": ["voice_cloning", "multilingual"],
        }


_chatterbox_engine: Optional[ChatterboxEngine] = None


def get_chatterbox_engine() -> ChatterboxEngine:
    """Get or create the Chatterbox engine."""
    global _chatterbox_engine
    if _chatterbox_engine is None:
        _chatterbox_engine = ChatterboxEngine()
    return _chatterbox_engine
