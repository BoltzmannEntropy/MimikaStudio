"""Qwen3-TTS Engine for voice cloning with 3-second audio samples.

Supports MPS (Apple Silicon) and CUDA. Voice cloning works with short
reference audio clips (3+ seconds) and requires a transcript of the reference.

Also supports CustomVoice mode with 9 preset speakers for instant TTS
without needing reference audio.
"""
import platform
import torch
import soundfile as sf
import uuid
import numpy as np
from pathlib import Path
from typing import Optional, Tuple
from dataclasses import dataclass
from scipy import signal

# Supported languages
LANGUAGES = {
    "Auto": "Auto",
    "Chinese": "Chinese",
    "English": "English",
    "Japanese": "Japanese",
    "Korean": "Korean",
    "German": "German",
    "French": "French",
    "Russian": "Russian",
    "Portuguese": "Portuguese",
    "Spanish": "Spanish",
    "Italian": "Italian",
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
    """Qwen3-TTS engine with voice cloning and CustomVoice support."""

    # Map frontend attention values to library values
    ATTENTION_MAP = {
        "auto": None,
        "sage_attn": "sage_attention",
        "flash_attn": "flash_attention_2",
        "sdpa": "sdpa",
        "eager": "eager",
    }

    def __init__(self, model_size: str = "0.6B", mode: str = "clone", attention: str = "auto"):
        """Initialize the engine.

        Args:
            model_size: "0.6B" (faster, less memory) or "1.7B" (better quality)
            mode: "clone" (VoiceClone/Base) or "custom" (CustomVoice preset speakers)
            attention: Attention implementation ("auto", "sage_attn", "flash_attn", "sdpa", "eager")
        """
        self.model = None
        self.model_size = model_size
        self.mode = mode
        self.attention = attention
        self.device = None
        self.dtype = None
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        self.sample_voices_dir = Path(__file__).parent.parent / "data" / "samples" / "qwen3_voices"
        self.sample_voices_dir.mkdir(parents=True, exist_ok=True)
        self.user_voices_dir = Path(__file__).parent.parent / "data" / "user_voices" / "qwen3"
        self.user_voices_dir.mkdir(parents=True, exist_ok=True)
        self._voice_prompts = {}  # Cache for voice clone prompts

    def _get_device_and_dtype(self) -> Tuple[str, torch.dtype]:
        """Get the appropriate device and dtype for the current platform.

        Note: MPS has a conv1d limitation (>65536 channels not supported) that
        affects the Qwen3-TTS tokenizer. We use CPU on Mac instead.
        """
        if torch.cuda.is_available():
            return "cuda:0", torch.bfloat16
        else:
            # Use CPU on Mac and other non-CUDA systems
            # MPS doesn't work due to conv1d channel limitations in the tokenizer
            return "cpu", torch.float32

    def _build_gen_kwargs(self, params: Optional[GenerationParams] = None) -> dict:
        """Build generation kwargs from parameters."""
        if params is None:
            params = GenerationParams()

        kwargs = {
            "temperature": params.temperature,
            "top_p": params.top_p,
            "top_k": params.top_k,
            "repetition_penalty": params.repetition_penalty,
            "max_new_tokens": params.max_new_tokens,
            "do_sample": params.do_sample,
        }

        # Handle seed
        if params.seed >= 0:
            torch.manual_seed(params.seed)
            if self.device and self.device.startswith("cuda"):
                torch.cuda.manual_seed(params.seed)

        return kwargs

    def load_model(self):
        """Load the Qwen3-TTS model."""
        if self.model is not None:
            return self.model

        try:
            from qwen_tts import Qwen3TTSModel
        except ImportError:
            raise ImportError(
                "qwen-tts package not installed. Install with: pip install -U qwen-tts soundfile"
            )

        self.device, self.dtype = self._get_device_and_dtype()

        # Select model variant based on mode
        variant = "Base" if self.mode == "clone" else "CustomVoice"
        model_name = f"Qwen/Qwen3-TTS-12Hz-{self.model_size}-{variant}"
        print(f"Loading Qwen3-TTS model: {model_name}")
        print(f"Device: {self.device}, dtype: {self.dtype}")

        # Load model - configure attention implementation
        load_kwargs = {
            "device_map": self.device,
            "dtype": self.dtype,
        }

        # Resolve attention implementation
        attn_impl = self.ATTENTION_MAP.get(self.attention)
        if attn_impl is not None:
            load_kwargs["attn_implementation"] = attn_impl
        elif self.device.startswith("cuda"):
            # Auto-select for CUDA: try flash_attention_2
            try:
                import flash_attn
                load_kwargs["attn_implementation"] = "flash_attention_2"
                print("Using FlashAttention 2")
            except ImportError:
                print("FlashAttention not available, using default attention")

        self.model = Qwen3TTSModel.from_pretrained(model_name, **load_kwargs)
        print(f"Qwen3-TTS model loaded successfully on {self.device}")

        return self.model

    def unload(self):
        """Free memory by unloading the model."""
        self.model = None
        self._voice_prompts.clear()
        if self.device == "mps":
            torch.mps.empty_cache()
        elif self.device and self.device.startswith("cuda"):
            torch.cuda.empty_cache()

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
        self.load_model()

        lang = LANGUAGES.get(language, language)
        if lang not in LANGUAGES.values():
            lang = "Auto"

        # Use x_vector_only_mode if no transcript provided (lower quality but works)
        use_x_vector_only = not ref_text or not ref_text.strip()

        # Build generation kwargs
        gen_kwargs = self._build_gen_kwargs(params)

        # Generate audio using direct API (no prompt caching for advanced params)
        wavs, sr = self.model.generate_voice_clone(
            text=text,
            language=lang,
            ref_audio=ref_audio_path,
            ref_text=ref_text if not use_x_vector_only else None,
            x_vector_only_mode=use_x_vector_only,
            **gen_kwargs,
        )

        # Apply speed adjustment if needed
        audio_data = np.asarray(wavs[0])
        if speed != 1.0:
            audio_data = self._adjust_speed(audio_data, sr, speed)

        # Save to file
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

        # Ensure we're using CustomVoice model
        if self.mode != "custom":
            print(f"Warning: Switching to CustomVoice mode for speaker generation")
            self.mode = "custom"
            self.model = None  # Force reload with correct variant

        self.load_model()

        lang = LANGUAGES.get(language, language)
        if lang not in LANGUAGES.values():
            lang = "Auto"

        # Build generation kwargs
        gen_kwargs = self._build_gen_kwargs(params)

        # Generate audio using CustomVoice API
        wavs, sr = self.model.generate_custom_voice(
            text=text,
            speaker=speaker,
            language=lang,
            instruct=instruct,
            **gen_kwargs,
        )

        # Apply speed adjustment if needed
        audio_data = np.asarray(wavs[0])
        if speed != 1.0:
            audio_data = self._adjust_speed(audio_data, sr, speed)

        # Save to file
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"qwen3-custom-{short_uuid}.wav"
        sf.write(str(output_file), audio_data, sr)

        return output_file

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
        if self.device == "mps":
            torch.mps.empty_cache()
        elif self.device and self.device.startswith("cuda"):
            torch.cuda.empty_cache()

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
            "version": f"12Hz-{self.model_size}-{variant}",
            "mode": self.mode,
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
    attention: str = "auto"
) -> Qwen3TTSEngine:
    """Get or create the Qwen3-TTS engine.

    Args:
        model_size: "0.6B" or "1.7B"
        mode: "clone" (Base) or "custom" (CustomVoice)
        attention: Attention implementation

    Returns:
        Qwen3TTSEngine instance
    """
    global _clone_engine, _custom_engine

    if mode == "clone":
        if _clone_engine is None or _clone_engine.model_size != model_size:
            _clone_engine = Qwen3TTSEngine(
                model_size=model_size, mode="clone", attention=attention
            )
        return _clone_engine
    else:
        if _custom_engine is None or _custom_engine.model_size != model_size:
            _custom_engine = Qwen3TTSEngine(
                model_size=model_size, mode="custom", attention=attention
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
