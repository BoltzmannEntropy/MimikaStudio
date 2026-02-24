"""Qwen3-TTS engine backed by mlx-audio.

Supports:
- clone mode: voice cloning from short reference audio
- custom mode: preset speakers (Ryan, Aiden, etc.)
"""
from __future__ import annotations

import random
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional, Tuple

import numpy as np
import soundfile as sf
from scipy import signal

# Keep MLX import lazy to avoid backend startup aborts on machines without a
# usable Metal device context.
mx = None

# Supported languages
LANGUAGES = {
    "Auto": "auto",
    "Chinese": "chinese",
    "English": "english",
    "Japanese": "japanese",
    "Korean": "korean",
    "German": "german",
    "French": "french",
    "Russian": "russian",
    "Portuguese": "portuguese",
    "Spanish": "spanish",
    "Italian": "italian",
}

# Preset speakers for CustomVoice models
QWEN_SPEAKERS = (
    "Ryan",      # English - Dynamic male with strong rhythm
    "Aiden",     # English - Sunny American male
    "Vivian",    # Chinese - Bright young female
    "Serena",    # Chinese - Warm gentle female
    "Uncle_Fu",  # Chinese - Seasoned male, low mellow
    "Dylan",     # Chinese - Beijing youthful male
    "Eric",      # Chinese - Sichuan lively male
    "Ono_Anna",  # Japanese - Playful female
    "Sohee",     # Korean - Warm emotional female
)


@dataclass
class GenerationParams:
    """Advanced generation parameters for Qwen3-TTS."""
    temperature: float = 0.9
    top_p: float = 0.9
    top_k: int = 50
    repetition_penalty: float = 1.0
    max_new_tokens: int = 2048
    do_sample: bool = True
    seed: int = -1  # -1 means random


class Qwen3TTSEngine:
    """Qwen3-TTS engine with voice cloning and preset speakers on MLX."""

    MODEL_REPOS = {
        ("clone", "0.6B", "bf16"): "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
        ("clone", "1.7B", "bf16"): "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
        ("custom", "0.6B", "bf16"): "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16",
        ("custom", "1.7B", "bf16"): "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
        ("clone", "0.6B", "8bit"): "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        ("clone", "1.7B", "8bit"): "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
        ("custom", "0.6B", "8bit"): "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
        ("custom", "1.7B", "8bit"): "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
    }

    def __init__(
        self,
        model_size: str = "0.6B",
        mode: str = "clone",
        quantization: str = "bf16",
        attention: str = "auto",
    ):
        """Initialize the engine.

        Args:
            model_size: "0.6B" (faster, less memory) or "1.7B" (better quality)
            mode: "clone" (VoiceClone/Base) or "custom" (CustomVoice preset speakers)
            quantization: "bf16" (higher quality) or "8bit" (faster, lower memory)
            attention: Attention implementation ("auto", "sage_attn", "flash_attn", "sdpa", "eager")
        """
        self.model = None
        self.model_size = model_size
        self.mode = mode
        self.quantization = quantization
        self.attention = attention
        self.device = None
        self.dtype = None
        self._model_repo = self.MODEL_REPOS.get((mode, model_size, quantization))
        if self._model_repo is None:
            raise ValueError(
                "Unsupported Qwen3 config: "
                f"mode={mode}, model_size={model_size}, quantization={quantization}"
            )
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        self.sample_voices_dir = Path(__file__).parent.parent / "data" / "samples" / "voices"
        self.sample_voices_dir.mkdir(parents=True, exist_ok=True)
        self.user_voices_dir = Path(__file__).parent.parent / "data" / "user_voices" / "qwen3"
        self.user_voices_dir.mkdir(parents=True, exist_ok=True)
        self._voice_prompts = {}

    def _get_device_and_dtype(self) -> Tuple[str, str]:
        """Best-effort runtime info for diagnostics."""
        if mx is not None and mx.metal.is_available():
            return "mlx", "bfloat16/fp16"
        return "cpu", "float32"

    def _normalize_language(self, language: str) -> str:
        if not language:
            return "auto"
        if language in LANGUAGES:
            return LANGUAGES[language]
        normalized = language.strip().lower().replace("_", " ")
        if "auto" in normalized:
            return "auto"
        return normalized.replace(" ", "")

    def _build_gen_kwargs(self, params: Optional[GenerationParams] = None) -> dict:
        """Build generation kwargs from parameters."""
        if params is None:
            params = GenerationParams()

        kwargs = {
            "temperature": params.temperature,
            "top_p": params.top_p,
            "top_k": params.top_k,
            "repetition_penalty": params.repetition_penalty,
            "max_tokens": params.max_new_tokens,
        }

        # Handle deterministic generation where possible.
        if params.seed >= 0:
            random.seed(params.seed)
            np.random.seed(params.seed)
            if mx is not None:
                mx.random.seed(params.seed)

        return kwargs

    def _set_mode(self, mode: str):
        """Switch model mode while preserving size/quantization and reloading lazily."""
        if self.mode == mode:
            return
        self.mode = mode
        self._model_repo = self.MODEL_REPOS[(self.mode, self.model_size, self.quantization)]
        self.model = None

    def load_model(self):
        """Load the Qwen3-TTS model."""
        if self.model is not None:
            return self.model

        try:
            from mlx_audio.tts import load as load_tts_model
        except ImportError as exc:
            raise ImportError(
                "mlx-audio package not installed. Install with: pip install -U mlx-audio"
            ) from exc

        self.device, self.dtype = self._get_device_and_dtype()
        self.model = load_tts_model(self._model_repo)
        return self.model

    def unload(self):
        """Free memory by unloading the model."""
        self.model = None
        self._voice_prompts.clear()
        if mx is not None:
            mx.clear_cache()

    @staticmethod
    def _to_pcm16le_bytes(audio: np.ndarray) -> bytes:
        clipped = np.clip(audio, -1.0, 1.0)
        return (clipped * 32767.0).astype(np.int16).tobytes()

    def _collect_audio(self, results) -> tuple[np.ndarray, int]:
        """Collect mlx-audio generation results into a single waveform."""
        chunks: list[np.ndarray] = []
        sample_rate = 24000
        for item in results:
            sample_rate = int(getattr(item, "sample_rate", sample_rate))
            chunks.append(np.asarray(item.audio, dtype=np.float32).reshape(-1))
        if not chunks:
            raise RuntimeError("No audio generated by Qwen3")
        if len(chunks) == 1:
            return chunks[0], sample_rate
        return np.concatenate(chunks), sample_rate

    def _iter_audio_chunks(self, results) -> Iterator[tuple[np.ndarray, int]]:
        """Yield chunked audio from mlx-audio generation."""
        yielded = False
        for item in results:
            sample_rate = int(getattr(item, "sample_rate", 24000))
            chunk = np.asarray(item.audio, dtype=np.float32).reshape(-1)
            if chunk.size == 0:
                continue
            yielded = True
            yield chunk, sample_rate
        if not yielded:
            raise RuntimeError("No audio generated by Qwen3")

    def generate_voice_clone(
        self,
        text: str,
        ref_audio_path: str,
        ref_text: str,
        language: str = "English",
        speed: float = 1.0,
        params: Optional[GenerationParams] = None,
    ) -> Path:
        """Generate speech by cloning a reference voice.

        Args:
            text: Text to synthesize
            ref_audio_path: Path to reference audio (3+ seconds recommended)
            ref_text: Transcript of the reference audio (optional - if empty, uses x-vector mode)
            language: Target language
            speed: Speech speed multiplier
            params: Advanced generation parameters

        Returns:
            Path to the generated audio file
        """
        # Ensure Base clone model variant.
        self._set_mode("clone")
        self.load_model()

        lang = self._normalize_language(language)
        gen_kwargs = self._build_gen_kwargs(params)
        results = self.model.generate(
            text=text,
            ref_audio=ref_audio_path,
            ref_text=ref_text.strip() if ref_text and ref_text.strip() else None,
            lang_code=lang,
            verbose=False,
            **gen_kwargs,
        )
        audio_data, sr = self._collect_audio(results)
        if speed != 1.0:
            audio_data = self._adjust_speed(audio_data, sr, speed)

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"qwen3-clone-{short_uuid}.wav"
        sf.write(str(output_file), audio_data, sr)

        return output_file

    def generate_custom_voice(
        self,
        text: str,
        speaker: str,
        language: str = "Auto",
        instruct: Optional[str] = None,
        speed: float = 1.0,
        params: Optional[GenerationParams] = None,
    ) -> Path:
        """Generate speech using a preset speaker voice.

        Args:
            text: Text to synthesize
            speaker: Preset speaker name (Ryan, Aiden, Vivian, etc.)
            language: Target language
            instruct: Style instruction for the voice (e.g., "Speak slowly and calmly")
            speed: Speech speed multiplier (0.5-2.0)
            params: Advanced generation parameters

        Returns:
            Path to the generated audio file
        """
        if speaker not in QWEN_SPEAKERS:
            raise ValueError(f"Unknown speaker: {speaker}. Available: {list(QWEN_SPEAKERS)}")

        # Ensure CustomVoice model variant.
        self._set_mode("custom")

        self.load_model()

        lang = self._normalize_language(language)
        gen_kwargs = self._build_gen_kwargs(params)
        results = self.model.generate_custom_voice(
            text=text,
            speaker=speaker,
            language=lang,
            instruct=instruct,
            verbose=False,
            **gen_kwargs,
        )
        audio_data, sr = self._collect_audio(results)
        if speed != 1.0:
            audio_data = self._adjust_speed(audio_data, sr, speed)

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"qwen3-custom-{short_uuid}.wav"
        sf.write(str(output_file), audio_data, sr)

        return output_file

    def stream_voice_clone_pcm(
        self,
        text: str,
        ref_audio_path: str,
        ref_text: str,
        language: str = "English",
        speed: float = 1.0,
        streaming_interval: float = 0.75,
        params: Optional[GenerationParams] = None,
    ) -> Iterator[bytes]:
        """Stream voice-cloned audio chunks as mono 16-bit PCM bytes."""
        self._set_mode("clone")
        self.load_model()

        lang = self._normalize_language(language)
        gen_kwargs = self._build_gen_kwargs(params)
        results = self.model.generate(
            text=text,
            ref_audio=ref_audio_path,
            ref_text=ref_text.strip() if ref_text and ref_text.strip() else None,
            lang_code=lang,
            verbose=False,
            stream=True,
            streaming_interval=streaming_interval,
            **gen_kwargs,
        )

        for chunk, sr in self._iter_audio_chunks(results):
            if speed != 1.0:
                chunk = self._adjust_speed(chunk, sr, speed)
            yield self._to_pcm16le_bytes(chunk)

    def stream_custom_voice_pcm(
        self,
        text: str,
        speaker: str,
        language: str = "Auto",
        instruct: Optional[str] = None,
        speed: float = 1.0,
        streaming_interval: float = 0.75,
        params: Optional[GenerationParams] = None,
    ) -> Iterator[bytes]:
        """Stream preset-speaker audio chunks as mono 16-bit PCM bytes."""
        if speaker not in QWEN_SPEAKERS:
            raise ValueError(f"Unknown speaker: {speaker}. Available: {list(QWEN_SPEAKERS)}")

        self._set_mode("custom")
        self.load_model()

        lang = self._normalize_language(language)
        gen_kwargs = self._build_gen_kwargs(params)
        results = self.model.generate_custom_voice(
            text=text,
            speaker=speaker,
            language=lang,
            instruct=instruct,
            verbose=False,
            stream=True,
            streaming_interval=streaming_interval,
            **gen_kwargs,
        )

        for chunk, sr in self._iter_audio_chunks(results):
            if speed != 1.0:
                chunk = self._adjust_speed(chunk, sr, speed)
            yield self._to_pcm16le_bytes(chunk)

    def generate_with_voice_design(
        self,
        text: str,
        voice_description: str,
        language: str = "English",
    ) -> Path:
        """Generate speech using a voice description (no reference audio needed).

        This uses the VoiceDesign model variant.

        Args:
            text: Text to synthesize
            voice_description: Natural language description of the voice
                               e.g., "A young female with a calm, warm voice"
            language: Target language

        Returns:
            Path to the generated audio file
        """
        # Note: VoiceDesign requires a different model variant
        # For now, this is a placeholder - implement if needed
        raise NotImplementedError(
            "VoiceDesign requires Qwen3-TTS-VoiceDesign model. "
            "Use generate_voice_clone() with reference audio instead."
        )

    def save_voice_sample(self, name: str, audio_path: str, transcript: str) -> dict:
        """Save a voice sample for later use.

        Args:
            name: Name for the voice
            audio_path: Path to the audio file
            transcript: Transcript of the audio

        Returns:
            Voice sample info dict
        """
        import shutil

        # Copy audio to user voices directory
        src = Path(audio_path)
        dest = self.user_voices_dir / f"{name}.wav"
        shutil.copy2(src, dest)

        # Save transcript
        transcript_file = self.user_voices_dir / f"{name}.txt"
        transcript_file.write_text(transcript)

        return {
            "name": name,
            "audio_path": str(dest),
            "transcript": transcript,
            "source": "user",
        }

    def get_saved_voices(self) -> list:
        """Get list of saved voice samples."""
        voices = []

        merged = {}

        # Shipped sample voices
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

        # User voices (override defaults on name conflict)
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

    def get_languages(self) -> list:
        """Get supported languages."""
        return list(LANGUAGES.keys())

    def clear_cache(self):
        """Clear the voice prompt cache and free memory."""
        self._voice_prompts.clear()
        if mx is not None:
            mx.clear_cache()

    def _adjust_speed(self, audio: np.ndarray, sr: int, speed: float) -> np.ndarray:
        """Adjust audio playback speed using resampling.

        Args:
            audio: Audio samples
            sr: Sample rate
            speed: Speed multiplier (>1 = faster, <1 = slower)

        Returns:
            Speed-adjusted audio samples
        """
        if speed == 1.0:
            return audio

        # Clamp speed to reasonable range
        speed = max(0.5, min(2.0, speed))

        # Resample to adjust speed while maintaining pitch
        # To speed up: use fewer samples (resample to shorter length)
        # To slow down: use more samples (resample to longer length)
        original_length = len(audio)
        new_length = int(original_length / speed)

        if new_length == original_length:
            return audio

        # Use scipy's resample for high-quality resampling
        return signal.resample(audio, new_length)

    def get_speakers(self) -> list:
        """Get available preset speakers for CustomVoice mode."""
        return list(QWEN_SPEAKERS)

    def get_model_info(self) -> dict:
        """Get information about the loaded model."""
        variant = "Base" if self.mode == "clone" else "CustomVoice"
        return {
            "name": "Qwen3-TTS",
            "version": f"12Hz-{self.model_size}-{variant}-{self.quantization}",
            "repo": self._model_repo,
            "backend": "mlx-audio",
            "mode": self.mode,
            "quantization": self.quantization,
            "device": self.device or "not loaded",
            "dtype": str(self.dtype) if self.dtype else "not loaded",
            "loaded": self.model is not None,
            "languages": self.get_languages(),
            "speakers": self.get_speakers() if self.mode == "custom" else None,
            "features": ["voice_cloning", "custom_voice", "3_second_samples", "streaming", "advanced_params"],
        }


# Engine instances (separate for clone and custom modes)
_clone_engine: Optional[Qwen3TTSEngine] = None
_custom_engine: Optional[Qwen3TTSEngine] = None


def get_qwen3_engine(
    model_size: str = "0.6B",
    mode: str = "clone",
    quantization: str = "bf16",
    attention: str = "auto"
) -> Qwen3TTSEngine:
    """Get or create the Qwen3-TTS engine.

    Args:
        model_size: "0.6B" or "1.7B"
        mode: "clone" (Base) or "custom" (CustomVoice)
        quantization: "bf16" or "8bit"
        attention: Attention implementation

    Returns:
        Qwen3TTSEngine instance
    """
    global _clone_engine, _custom_engine

    if mode == "clone":
        if (
            _clone_engine is None
            or _clone_engine.model_size != model_size
            or _clone_engine.quantization != quantization
        ):
            _clone_engine = Qwen3TTSEngine(
                model_size=model_size,
                mode="clone",
                quantization=quantization,
                attention=attention,
            )
        return _clone_engine
    else:
        if (
            _custom_engine is None
            or _custom_engine.model_size != model_size
            or _custom_engine.quantization != quantization
        ):
            _custom_engine = Qwen3TTSEngine(
                model_size=model_size,
                mode="custom",
                quantization=quantization,
                attention=attention,
            )
        return _custom_engine


def unload_all_engines():
    """Unload all engine instances to free memory."""
    global _clone_engine, _custom_engine
    if _clone_engine is not None:
        _clone_engine.unload()
        _clone_engine = None
    if _custom_engine is not None:
        _custom_engine.unload()
        _custom_engine = None
