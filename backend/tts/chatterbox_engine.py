"""Chatterbox Multilingual TTS engine wrapper for voice cloning."""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import soundfile as sf
import torch
from scipy import signal

from .audio_utils import merge_audio_chunks
from .text_chunking import smart_chunk_text


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
            Path(__file__).parent.parent / "data" / "samples" / "chatterbox_voices"
        )
        self.sample_voices_dir.mkdir(parents=True, exist_ok=True)

        self.user_voices_dir = (
            Path(__file__).parent.parent / "data" / "user_voices" / "chatterbox"
        )
        self.user_voices_dir.mkdir(parents=True, exist_ok=True)

    def _get_device(self) -> str:
        if torch.cuda.is_available():
            return "cuda"
        return "cpu"

    def load_model(self):
        """Load the Chatterbox model."""
        if self.model is not None:
            return self.model

        try:
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        except ImportError as exc:
            raise ImportError(
                "chatterbox-tts not installed. Install with: pip install chatterbox-tts"
            ) from exc

        self.device = self._get_device()
        # Chatterbox checkpoints are saved on CUDA; force map to current device.
        original_torch_load = torch.load

        def _load_with_map(*args, **kwargs):
            if "map_location" not in kwargs:
                kwargs["map_location"] = torch.device(self.device)
            return original_torch_load(*args, **kwargs)

        torch.load = _load_with_map
        try:
            self.model = ChatterboxMultilingualTTS.from_pretrained(device=self.device)
        finally:
            torch.load = original_torch_load

        # Force eager attention to avoid SDPA/output_attentions conflict.
        try:
            cfg = getattr(self.model.t3, "cfg", None)
            if cfg is not None:
                for attr in ("_attn_implementation", "_attn_implementation_internal", "attn_implementation"):
                    try:
                        setattr(cfg, attr, "eager")
                    except Exception:
                        continue
        except Exception:
            pass
        return self.model

    def unload(self) -> None:
        """Free memory by unloading the model."""
        self.model = None
        if self.device == "mps":
            torch.mps.empty_cache()
        elif self.device and self.device.startswith("cuda"):
            torch.cuda.empty_cache()

    def _seed(self, seed: int) -> None:
        if seed >= 0:
            torch.manual_seed(seed)
            if torch.cuda.is_available():
                torch.cuda.manual_seed(seed)

    def _adjust_speed(self, audio: np.ndarray, speed: float) -> np.ndarray:
        if speed == 1.0:
            return audio
        speed = max(0.5, min(2.0, speed))
        original_length = len(audio)
        new_length = int(original_length / speed)
        if new_length == original_length:
            return audio
        return signal.resample(audio, new_length)

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

        chunks = (
            smart_chunk_text(text, max_chars=max_chars)
            if max_chars and len(text) > max_chars
            else [text]
        )
        chunks = [c for c in chunks if c.strip()]
        if not chunks:
            raise ValueError("Text cannot be empty")

        language = (language or "en").lower()

        all_audio = []
        for chunk in chunks:
            self._seed(params.seed)
            audio = self.model.generate(  # type: ignore[call-arg]
                text=chunk,
                language_id=language,
                audio_prompt_path=ref_audio_path,
                exaggeration=params.exaggeration,
                temperature=params.temperature,
                cfg_weight=params.cfg_weight,
            )
            audio = audio.squeeze().detach().cpu().numpy().astype(np.float32)
            audio = self._adjust_speed(audio, speed)
            all_audio.append(audio)

        merged = merge_audio_chunks(all_audio, self.model.sr, crossfade_ms=crossfade_ms)  # type: ignore[attr-defined]
        short_uuid = str(uuid.uuid4())[:8]
        output_path = self.outputs_dir / f"chatterbox-{voice_name}-{short_uuid}.wav"
        sf.write(output_path, merged, self.model.sr)  # type: ignore[arg-type]
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
        try:
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS
            return list(ChatterboxMultilingualTTS.get_supported_languages())
        except Exception:
            return ["en"]

    def get_model_info(self) -> dict:
        return {
            "name": "Chatterbox Multilingual TTS",
            "device": self.device or "not loaded",
            "sample_rate": getattr(self.model, "sr", None),
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
