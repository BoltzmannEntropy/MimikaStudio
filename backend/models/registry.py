"""Model registry for all TTS models.

Defines available models, their modes, capabilities, and download status.
"""
import os
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
    quantization: str = "bf16"  # "bf16" or "8bit"
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
            env_hub_cache = os.environ.get("HUGGINGFACE_HUB_CACHE")
            env_hf_home = os.environ.get("HF_HOME")
            env_xdg_cache = os.environ.get("XDG_CACHE_HOME")

            if env_hub_cache:
                models_dir = Path(env_hub_cache)
            elif env_hf_home:
                models_dir = Path(env_hf_home) / "hub"
            elif env_xdg_cache:
                models_dir = Path(env_xdg_cache) / "huggingface" / "hub"
            else:
                models_dir = Path.home() / ".cache" / "huggingface" / "hub"
        self.models_dir = Path(models_dir)

    def list_models(self) -> List[ModelInfo]:
        """List all available Qwen3 models (for backward compatibility)."""
        return [m for m in self.list_all_models() if m.engine == "qwen3"]

    def list_all_models(self) -> List[ModelInfo]:
        """List all available models across all engines."""
        return [
            # Kokoro (MLX)
            ModelInfo(
                name="Kokoro",
                engine="kokoro",
                hf_repo="mlx-community/Kokoro-82M-bf16",
                local_dir=self.models_dir / "models--mlx-community--Kokoro-82M-bf16",
                size_gb=0.3,
                mode="tts",
                model_type="huggingface",
                description="Fast British English TTS on Apple Silicon via MLX-Audio",
            ),
            # Qwen3 VoiceClone models (Base) - clone from user audio (MLX)
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-Base",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-0.6B-Base-bf16",
                size_gb=1.4,
                mode="clone",
                quantization="bf16",
                description="Voice cloning (smaller, faster) on MLX",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-Base",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-1.7B-Base-bf16",
                size_gb=3.6,
                mode="clone",
                quantization="bf16",
                description="Voice cloning (larger, higher quality) on MLX",
            ),
            # Qwen3 CustomVoice models (preset speakers, MLX)
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-CustomVoice",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16",
                size_gb=1.4,
                mode="custom",
                quantization="bf16",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (smaller, faster) on MLX",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-CustomVoice",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
                size_gb=3.6,
                mode="custom",
                quantization="bf16",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (larger, higher quality) on MLX",
            ),
            # Qwen3 8-bit variants (lower memory, faster startup)
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-Base-8bit",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-0.6B-Base-8bit",
                size_gb=0.8,
                mode="clone",
                quantization="8bit",
                description="Voice cloning (smaller, faster, 8-bit) on MLX",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-Base-8bit",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-1.7B-Base-8bit",
                size_gb=2.0,
                mode="clone",
                quantization="8bit",
                description="Voice cloning (larger, 8-bit) on MLX",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
                size_gb=0.8,
                mode="custom",
                quantization="8bit",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (smaller, 8-bit) on MLX",
            ),
            ModelInfo(
                name="Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
                engine="qwen3",
                hf_repo="mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
                local_dir=self.models_dir / "models--mlx-community--Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
                size_gb=2.0,
                mode="custom",
                quantization="8bit",
                speakers=QWEN_SPEAKERS,
                description="Preset speakers (larger, 8-bit) on MLX",
            ),
            # Chatterbox (MLX)
            ModelInfo(
                name="Chatterbox Multilingual",
                engine="chatterbox",
                hf_repo="mlx-community/chatterbox-fp16",
                local_dir=self.models_dir / "models--mlx-community--chatterbox-fp16",
                size_gb=2.0,
                mode="clone",
                description="Multilingual voice cloning on MLX",
            ),
            # Supertonic-2 (ONNX Runtime)
            ModelInfo(
                name="Supertonic-2",
                engine="supertonic",
                hf_repo="Supertone/supertonic-2",
                local_dir=self.models_dir / "models--Supertone--supertonic-2",
                size_gb=0.3,
                mode="tts",
                model_type="huggingface",
                description="Lightning-fast multilingual ONNX TTS",
            ),
            # CosyVoice3 standalone ONNX model pack
            ModelInfo(
                name="CosyVoice3",
                engine="cosyvoice3",
                hf_repo="ayousanz/cosy-voice3-onnx",
                local_dir=self.models_dir / "models--ayousanz--cosy-voice3-onnx",
                size_gb=3.8,
                mode="tts",
                model_type="huggingface",
                description="CosyVoice3 standalone ONNX runtime (preset expressive voices, no PyTorch)",
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

    def get_model_cache_dir(self, model: ModelInfo) -> Path:
        """Return cache directory for a model repo."""
        return self.models_dir / f"models--{model.hf_repo.replace('/', '--')}"

    def _snapshot_dirs(self, model: ModelInfo) -> list[Path]:
        cache_dir = self.get_model_cache_dir(model)
        snapshots_dir = cache_dir / "snapshots"
        if not snapshots_dir.exists():
            return []
        return [p for p in snapshots_dir.iterdir() if p.is_dir()]

    def _snapshot_has_required_payload(self, snapshot_dir: Path) -> bool:
        """Best-effort check that a snapshot contains usable model files.

        We require at least one model weight file and prefer at least one
        metadata json, preventing false positives from empty/partial snapshots.
        """
        weight_suffixes = (".safetensors", ".bin", ".gguf", ".onnx")
        has_weight = False
        has_metadata = False

        metadata_names = {
            "config.json",
            "generation_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "preprocessor_config.json",
        }

        for entry in snapshot_dir.rglob("*"):
            if not entry.is_file():
                continue
            lowered = entry.name.lower()
            if lowered in metadata_names or lowered.endswith(".json"):
                has_metadata = True
            if lowered.endswith(weight_suffixes):
                has_weight = True
            if has_weight and has_metadata:
                return True

        # Keep compatibility with minimal model snapshots that only expose
        # weights but no obvious metadata.
        return has_weight

    def get_downloaded_snapshot_path(self, model: ModelInfo) -> Optional[Path]:
        """Return a usable snapshot path if present."""
        snapshots = self._snapshot_dirs(model)
        if not snapshots:
            return None
        snapshots.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        for snapshot in snapshots:
            if self._snapshot_has_required_payload(snapshot):
                return snapshot
        return None

    def is_model_downloaded(self, model: ModelInfo) -> bool:
        """Check if a model is downloaded."""
        if model.model_type == "huggingface":
            if not model.hf_repo:
                return False
            return self.get_downloaded_snapshot_path(model) is not None
        return False
