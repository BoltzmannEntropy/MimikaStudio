"""Model registry for all TTS models.

Defines available models, their modes, capabilities, and download status.
"""
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass(frozen=True)
class ModelInfo:
    """Information about a TTS model."""
    name: str
    engine: str
    hf_repo: str
    local_dir: Path
    size_gb: Optional[float] = None
    mode: str = "clone"  # "clone", "custom", or "design"
    speakers: Optional[tuple[str, ...]] = None  # Available speakers for custom mode
    model_type: str = "huggingface"  # "huggingface" or "pip"
    description: str = ""


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


class ModelRegistry:
    """Registry of all available TTS models."""

    def __init__(self, models_dir: Optional[Path] = None):
        """Initialize the registry.

        Args:
            models_dir: Base directory for HuggingFace cache
        """
        if models_dir is None:
            models_dir = Path.home() / ".cache" / "huggingface" / "hub"
        self.models_dir = Path(models_dir)

    def list_models(self) -> List[ModelInfo]:
        """List all available Qwen3 models (for backward compatibility)."""
        return [m for m in self.list_all_models() if m.engine == "qwen3"]

    def list_all_models(self) -> List[ModelInfo]:
        """List all available models across all engines."""
        return [
            # Kokoro - pip package
            ModelInfo(
                name="Kokoro",
                engine="kokoro",
                hf_repo="",
                local_dir=Path(""),
                size_gb=0.3,
                mode="tts",
                model_type="pip",
                description="Fast British English TTS via pip package",
            ),
            # Qwen3 VoiceClone models (Base) - clone from user audio
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-Base",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-0.6B-Base",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-0.6B-Base",
                size_gb=1.4,
                mode="clone",
                description="Voice cloning (smaller, faster)",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-Base",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-1.7B-Base",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-1.7B-Base",
                size_gb=3.6,
                mode="clone",
                description="Voice cloning (larger, higher quality)",
            ),
            # Qwen3 CustomVoice models (preset speakers)
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-CustomVoice",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-0.6B-CustomVoice",
                size_gb=1.4,
                mode="custom",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (smaller, faster)",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-CustomVoice",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-1.7B-CustomVoice",
                size_gb=3.6,
                mode="custom",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (larger, higher quality)",
            ),
            # Chatterbox
            ModelInfo(
                name="Chatterbox Multilingual",
                engine="chatterbox",
                hf_repo="ResembleAI/chatterbox",
                local_dir=self.models_dir / "models--ResembleAI--chatterbox",
                size_gb=2.0,
                mode="clone",
                description="Multilingual voice cloning",
            ),
            # IndexTTS-2
            ModelInfo(
                name="IndexTTS-2",
                engine="indextts2",
                hf_repo="IndexTeam/IndexTTS-v2",
                local_dir=self.models_dir / "models--IndexTeam--IndexTTS-v2",
                size_gb=24.0,
                mode="clone",
                description="High-quality voice cloning (large model)",
            ),
        ]

    def get_model(self, name: str) -> Optional[ModelInfo]:
        """Get a model by name."""
        for model in self.list_all_models():
            if model.name == name:
                return model
        return None

    def get_models_by_mode(self, mode: str) -> List[ModelInfo]:
        """Get models filtered by mode."""
        return [m for m in self.list_all_models() if m.mode == mode]

    def get_models_by_engine(self, engine: str) -> List[ModelInfo]:
        """Get models filtered by engine."""
        return [m for m in self.list_all_models() if m.engine == engine]

    def is_model_downloaded(self, model: ModelInfo) -> bool:
        """Check if a model is downloaded."""
        if model.model_type == "pip":
            try:
                __import__(model.engine)
                return True
            except ImportError:
                return False
        elif model.model_type == "huggingface":
            if not model.hf_repo:
                return False
            cache_dir = self.models_dir / f"models--{model.hf_repo.replace('/', '--')}"
            if cache_dir.exists():
                snapshots = cache_dir / "snapshots"
                if snapshots.exists() and any(snapshots.iterdir()):
                    return True
            return False
        return False
