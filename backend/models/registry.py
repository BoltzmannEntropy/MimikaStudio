"""Model registry for Qwen3-TTS models.

Defines available models, their modes, and capabilities.
"""
from dataclasses import dataclass
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
    """Registry of available Qwen3-TTS models."""

    def __init__(self, models_dir: Optional[Path] = None):
        """Initialize the registry.

        Args:
            models_dir: Base directory for local model storage
        """
        if models_dir is None:
            models_dir = Path.home() / ".cache" / "huggingface" / "hub"
        self.models_dir = Path(models_dir)

    def list_models(self) -> List[ModelInfo]:
        """List all available models."""
        return [
            # VoiceClone models (Base) - clone from user audio
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-Base",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-0.6B-Base",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-0.6B-Base",
                size_gb=1.4,
                mode="clone",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-Base",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-1.7B-Base",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-1.7B-Base",
                size_gb=3.6,
                mode="clone",
            ),
            # CustomVoice models (preset speakers)
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-CustomVoice",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-0.6B-CustomVoice",
                size_gb=1.4,
                mode="custom",
                speakers=QWEN_SPEAKERS,
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-CustomVoice",
                engine="qwen3",
                hf_repo="Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
                local_dir=self.models_dir / "Qwen3-TTS-12Hz-1.7B-CustomVoice",
                size_gb=3.6,
                mode="custom",
                speakers=QWEN_SPEAKERS,
            ),
        ]

    def get_model(self, name: str) -> Optional[ModelInfo]:
        """Get a model by name."""
        for model in self.list_models():
            if model.name == name:
                return model
        return None

    def get_models_by_mode(self, mode: str) -> List[ModelInfo]:
        """Get models filtered by mode."""
        return [m for m in self.list_models() if m.mode == mode]
