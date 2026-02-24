"""CosyVoice3 ONNX engine wrapper."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import os
import re
import subprocess
import sys
import tempfile
import threading
import uuid


DEFAULT_MODEL_NAME = "CosyVoice3"
DEFAULT_MODEL_REPO = "ayousanz/cosy-voice3-onnx"
DEFAULT_VOICE_NAME = "Eden"
SUPPORTED_LANGUAGES = (
    "Auto",
    "EN",
    "ZH",
    "JA",
    "KO",
    "DE",
    "ES",
    "FR",
    "IT",
    "RU",
)
SAMPLE_RATE = 24000

_FEMALE_PROMPT_TEXT = (
    "Hello, my name is Sarah. I'm excited to help you with your project today. "
    "Let me know if you have any questions."
)
_MALE_PROMPT_TEXT = (
    "Hello, my name is Michael. I'm ready to read your text naturally and clearly. "
    "Tell me what you want to synthesize."
)

_VOICE_PRESETS = {
    "Eden": {
        "gender": "female",
        "prompt_wav": "prompts/en_female_nova_greeting.wav",
        "prompt_text": _FEMALE_PROMPT_TEXT,
    },
    "Astra": {
        "gender": "female",
        "prompt_wav": "prompts/en_female_nova_greeting.wav",
        "prompt_text": _FEMALE_PROMPT_TEXT,
    },
    "Lyra": {
        "gender": "female",
        "prompt_wav": "prompts/en_female_nova_greeting.wav",
        "prompt_text": _FEMALE_PROMPT_TEXT,
    },
    "Nova": {
        "gender": "female",
        "prompt_wav": "prompts/en_female_nova_greeting.wav",
        "prompt_text": _FEMALE_PROMPT_TEXT,
    },
    "Iris": {
        "gender": "female",
        "prompt_wav": "prompts/en_female_nova_greeting.wav",
        "prompt_text": _FEMALE_PROMPT_TEXT,
    },
    "Orion": {
        "gender": "male",
        "prompt_wav": "prompts/en_male_onyx_greeting.wav",
        "prompt_text": _MALE_PROMPT_TEXT,
    },
    "Atlas": {
        "gender": "male",
        "prompt_wav": "prompts/en_male_onyx_greeting.wav",
        "prompt_text": _MALE_PROMPT_TEXT,
    },
    "Silas": {
        "gender": "male",
        "prompt_wav": "prompts/en_male_onyx_greeting.wav",
        "prompt_text": _MALE_PROMPT_TEXT,
    },
    "Kai": {
        "gender": "male",
        "prompt_wav": "prompts/en_male_onyx_greeting.wav",
        "prompt_text": _MALE_PROMPT_TEXT,
    },
    "Noah": {
        "gender": "male",
        "prompt_wav": "prompts/en_male_onyx_greeting.wav",
        "prompt_text": _MALE_PROMPT_TEXT,
    },
}


@dataclass
class CosyVoice3Params:
    speed: float = 1.0
    language: str = "Auto"


class CosyVoice3Engine:
    def __init__(self) -> None:
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        self._generate_lock = threading.Lock()
        self._model_dir_cache: dict[Path, Path] = {}
        self._last_snapshot_dir: Optional[Path] = None

    def is_runtime_available(self) -> bool:
        try:
            import onnxruntime  # noqa: F401
            import librosa  # noqa: F401
            import transformers  # noqa: F401
            return True
        except Exception:
            return False

    def _voice_name_or_default(self, voice: str) -> str:
        if voice in _VOICE_PRESETS:
            return voice
        return DEFAULT_VOICE_NAME

    def _voice_slug(self, voice_name: str) -> str:
        slug = re.sub(r"[^A-Za-z0-9_-]+", "_", (voice_name or "").strip())
        slug = slug.strip("_")
        return slug or DEFAULT_VOICE_NAME

    def _prepare_model_dir(self, snapshot_dir: Path) -> Path:
        snapshot_dir = snapshot_dir.expanduser().resolve()
        if snapshot_dir in self._model_dir_cache:
            return self._model_dir_cache[snapshot_dir]

        script_path = snapshot_dir / "scripts" / "onnx_inference_pure.py"
        if not script_path.exists():
            raise RuntimeError(
                f"CosyVoice3 snapshot is missing scripts/onnx_inference_pure.py: {snapshot_dir}"
            )

        adapter_root = Path(tempfile.gettempdir()) / "mimikastudio-cosyvoice3" / snapshot_dir.name
        model_dir = adapter_root / "Fun-CosyVoice3-0.5B"
        onnx_link = model_dir / "onnx"
        model_dir.mkdir(parents=True, exist_ok=True)

        if not onnx_link.exists():
            try:
                os.symlink(str(snapshot_dir), str(onnx_link), target_is_directory=True)
            except FileExistsError:
                pass
            except OSError as exc:
                raise RuntimeError(
                    f"Failed to prepare CosyVoice3 model directory (symlink): {exc}"
                ) from exc

        self._model_dir_cache[snapshot_dir] = model_dir
        return model_dir

    def get_voices(self) -> list[dict]:
        voices = []
        for voice_name, preset in _VOICE_PRESETS.items():
            voices.append(
                {
                    "code": voice_name,
                    "name": voice_name,
                    "gender": preset["gender"],
                    "is_default": voice_name == DEFAULT_VOICE_NAME,
                }
            )
        return voices

    def generate(
        self,
        text: str,
        voice: str = DEFAULT_VOICE_NAME,
        params: Optional[CosyVoice3Params] = None,
        snapshot_dir: Optional[Path | str] = None,
    ) -> Path:
        if not text or not text.strip():
            raise ValueError("Text cannot be empty")
        if snapshot_dir is None:
            raise ValueError("CosyVoice3 model snapshot path is required")
        if not self.is_runtime_available():
            raise ImportError(
                "CosyVoice3 ONNX runtime dependencies missing. "
                "Install: onnxruntime==1.18.0 librosa transformers soundfile scipy"
            )
        if params is None:
            params = CosyVoice3Params()

        resolved_snapshot = Path(snapshot_dir).expanduser().resolve()
        model_dir = self._prepare_model_dir(resolved_snapshot)
        script_path = resolved_snapshot / "scripts" / "onnx_inference_pure.py"

        voice_name = self._voice_name_or_default(voice)
        preset = _VOICE_PRESETS.get(voice_name, _VOICE_PRESETS[DEFAULT_VOICE_NAME])
        prompt_wav = resolved_snapshot / preset["prompt_wav"]
        if not prompt_wav.exists():
            raise RuntimeError(f"CosyVoice3 prompt audio not found: {prompt_wav}")

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"cosyvoice3-{self._voice_slug(voice_name)}-{short_uuid}.wav"
        timeout_seconds = max(120, int(os.getenv("MIMIKA_COSYVOICE3_TIMEOUT_SEC", "900")))

        command = [
            sys.executable,
            str(script_path),
            "--model_dir",
            str(model_dir),
            "--text",
            text.strip(),
            "--prompt_wav",
            str(prompt_wav),
            "--prompt_text",
            str(preset["prompt_text"]),
            "--output",
            str(output_file),
        ]
        if os.getenv("MIMIKA_COSYVOICE3_FP32", "").strip().lower() in {"1", "true", "yes"}:
            command.append("--fp32")

        with self._generate_lock:
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )

        self._last_snapshot_dir = resolved_snapshot
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            detail = stderr or stdout or f"exit={result.returncode}"
            raise RuntimeError(f"CosyVoice3 ONNX inference failed: {detail[-1000:]}")

        if not output_file.exists():
            raise RuntimeError("CosyVoice3 ONNX inference finished without output file")
        return output_file

    def get_model_info(self) -> dict:
        return {
            "name": DEFAULT_MODEL_NAME,
            "repo": DEFAULT_MODEL_REPO,
            "backend": "onnxruntime (pure ONNX, no PyTorch)",
            "sample_rate": SAMPLE_RATE,
            "languages": list(SUPPORTED_LANGUAGES),
            "voices": [voice["code"] for voice in self.get_voices()],
            "snapshot_dir": str(self._last_snapshot_dir) if self._last_snapshot_dir else None,
            "loaded": self._last_snapshot_dir is not None,
        }


_cosyvoice3_engine: Optional[CosyVoice3Engine] = None


def get_cosyvoice3_engine() -> CosyVoice3Engine:
    global _cosyvoice3_engine
    if _cosyvoice3_engine is None:
        _cosyvoice3_engine = CosyVoice3Engine()
    return _cosyvoice3_engine
