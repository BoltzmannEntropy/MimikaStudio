"""Supertonic TTS engine wrapper."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import re
import threading
import uuid

import numpy as np
import soundfile as sf

try:
    from supertonic import TTS
except ImportError:
    TTS = None


DEFAULT_MODEL_NAME = "supertonic-2"
DEFAULT_VOICE_NAME = "F1"
SUPPORTED_LANGUAGES = ("en", "ko", "es", "pt", "fr")
DEFAULT_VOICE_NAMES = ("F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5")


@dataclass
class SupertonicParams:
    """Generation parameters for Supertonic."""

    speed: float = 1.05
    total_steps: int = 5
    max_chunk_length: Optional[int] = None
    silence_duration: float = 0.3
    language: str = "en"


class SupertonicEngine:
    def __init__(self) -> None:
        self.tts = None
        self.model_name = DEFAULT_MODEL_NAME
        self.model_dir: Optional[Path] = None
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        self._style_cache: dict[str, object] = {}
        self._generate_lock = threading.Lock()

    def _normalize_model_dir(self, model_dir: Optional[Path | str]) -> Optional[Path]:
        if model_dir is None:
            return None
        return Path(model_dir).expanduser().resolve()

    def load_model(
        self,
        model_name: str = DEFAULT_MODEL_NAME,
        model_dir: Optional[Path | str] = None,
    ):
        if TTS is None:
            raise ImportError("supertonic package not installed. Install with: pip install supertonic")

        normalized_dir = self._normalize_model_dir(model_dir)
        if (
            self.tts is not None
            and self.model_name == model_name
            and self.model_dir == normalized_dir
        ):
            return self.tts

        self.model_name = model_name
        self.model_dir = normalized_dir
        tts_kwargs: dict[str, object] = {
            "model": model_name,
            "auto_download": False,
        }
        if normalized_dir is not None:
            tts_kwargs["model_dir"] = str(normalized_dir)
        self.tts = TTS(**tts_kwargs)
        self._style_cache.clear()
        return self.tts

    def unload(self) -> None:
        self.tts = None
        self._style_cache.clear()

    def _voice_style_names(self) -> list[str]:
        if self.tts is None:
            return list(DEFAULT_VOICE_NAMES)
        names = [str(name) for name in getattr(self.tts, "voice_style_names", [])]
        return names or list(DEFAULT_VOICE_NAMES)

    def get_voices(self) -> list[dict]:
        voices = []
        for name in self._voice_style_names():
            gender = "female" if name.upper().startswith("F") else "male"
            voices.append(
                {
                    "code": name,
                    "name": name,
                    "gender": gender,
                    "is_default": name == DEFAULT_VOICE_NAME,
                }
            )
        return voices

    def _voice_name_or_default(self, voice: str) -> str:
        available = self._voice_style_names()
        if voice in available:
            return voice
        if DEFAULT_VOICE_NAME in available:
            return DEFAULT_VOICE_NAME
        return available[0] if available else DEFAULT_VOICE_NAME

    def _normalize_language(self, language: str) -> str:
        lang = (language or "en").strip().lower()
        if lang not in SUPPORTED_LANGUAGES:
            return "en"
        return lang

    def _voice_slug(self, voice_name: str) -> str:
        slug = re.sub(r"[^A-Za-z0-9_-]+", "_", (voice_name or "").strip())
        slug = slug.strip("_")
        return slug or DEFAULT_VOICE_NAME

    def _get_voice_style(self, voice_name: str):
        if self.tts is None:
            raise RuntimeError("Supertonic model is not loaded")
        style = self._style_cache.get(voice_name)
        if style is None:
            style = self.tts.get_voice_style(voice_name)
            self._style_cache[voice_name] = style
        return style

    def generate_audio(
        self,
        text: str,
        voice: str = DEFAULT_VOICE_NAME,
        params: Optional[SupertonicParams] = None,
        model_name: str = DEFAULT_MODEL_NAME,
        model_dir: Optional[Path | str] = None,
    ) -> tuple[np.ndarray, int]:
        if params is None:
            params = SupertonicParams()

        if not text or not text.strip():
            raise ValueError("Text cannot be empty")

        tts = self.load_model(model_name=model_name, model_dir=model_dir)
        voice_name = self._voice_name_or_default(voice)
        lang = self._normalize_language(params.language)
        style = self._get_voice_style(voice_name)

        with self._generate_lock:
            wav, _ = tts.synthesize(
                text=text,
                voice_style=style,
                total_steps=params.total_steps,
                speed=params.speed,
                max_chunk_length=params.max_chunk_length,
                silence_duration=params.silence_duration,
                lang=lang,
            )

        audio = np.asarray(wav, dtype=np.float32).reshape(-1)
        sample_rate = int(getattr(tts, "sample_rate", 24000))
        return audio, sample_rate

    def generate(
        self,
        text: str,
        voice: str = DEFAULT_VOICE_NAME,
        params: Optional[SupertonicParams] = None,
        model_name: str = DEFAULT_MODEL_NAME,
        model_dir: Optional[Path | str] = None,
    ) -> Path:
        audio, sample_rate = self.generate_audio(
            text=text,
            voice=voice,
            params=params,
            model_name=model_name,
            model_dir=model_dir,
        )
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        voice_name = self._voice_name_or_default(voice)
        voice_slug = self._voice_slug(voice_name)
        output_file = self.outputs_dir / f"supertonic-{voice_slug}-{short_uuid}.wav"
        sf.write(str(output_file), audio, sample_rate)
        return output_file

    def get_model_info(self) -> dict:
        return {
            "name": "Supertonic-2",
            "repo": "Supertone/supertonic-2",
            "backend": "onnxruntime (supertonic)",
            "sample_rate": int(getattr(self.tts, "sample_rate", 24000)) if self.tts else 24000,
            "languages": list(SUPPORTED_LANGUAGES),
            "voices": self._voice_style_names(),
            "model_dir": str(self.model_dir) if self.model_dir else None,
            "loaded": self.tts is not None,
        }


_supertonic_engine: Optional[SupertonicEngine] = None


def get_supertonic_engine() -> SupertonicEngine:
    global _supertonic_engine
    if _supertonic_engine is None:
        _supertonic_engine = SupertonicEngine()
    return _supertonic_engine
