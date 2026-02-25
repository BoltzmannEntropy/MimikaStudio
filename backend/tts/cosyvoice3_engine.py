"""CosyVoice3 ONNX engine wrapper."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import contextlib
import importlib.util
import io
import os
import re
import subprocess
import sys
import tempfile
import threading
import uuid

import soundfile as sf


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
    total_steps: int = 5


class CosyVoice3Engine:
    def __init__(self) -> None:
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        self._generate_lock = threading.Lock()
        self._model_dir_cache: dict[Path, Path] = {}
        self._inproc_engine_cache: dict[Path, object] = {}
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

    def _load_inprocess_engine(self, snapshot_dir: Path):
        snapshot_dir = snapshot_dir.expanduser().resolve()
        cached = self._inproc_engine_cache.get(snapshot_dir)
        if cached is not None:
            return cached

        model_dir = self._prepare_model_dir(snapshot_dir)
        script_path = snapshot_dir / "scripts" / "onnx_inference_pure.py"
        if not script_path.exists():
            raise RuntimeError(
                f"CosyVoice3 snapshot is missing scripts/onnx_inference_pure.py: {snapshot_dir}"
            )

        module_name = f"mimika_cosyvoice3_pure_{snapshot_dir.name}"
        spec = importlib.util.spec_from_file_location(module_name, str(script_path))
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Failed to load CosyVoice3 ONNX module from {script_path}")

        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        engine_cls = getattr(module, "PureOnnxCosyVoice3", None)
        if engine_cls is None:
            raise RuntimeError(
                "CosyVoice3 ONNX script does not expose PureOnnxCosyVoice3 class"
            )

        use_fp16 = os.getenv("MIMIKA_COSYVOICE3_FP32", "").strip().lower() not in {
            "1",
            "true",
            "yes",
        }
        engine = engine_cls(model_dir=str(model_dir), use_fp16=use_fp16)
        self._inproc_engine_cache[snapshot_dir] = engine
        return engine

    def _generate_via_subprocess(
        self,
        *,
        text: str,
        output_file: Path,
        script_path: Path,
        model_dir: Path,
        prompt_wav: Path,
        prompt_text: str,
    ) -> None:
        timeout_seconds = max(120, int(os.getenv("MIMIKA_COSYVOICE3_TIMEOUT_SEC", "900")))
        command = [
            sys.executable,
            str(script_path),
            "--model_dir",
            str(model_dir),
            "--text",
            text,
            "--prompt_wav",
            str(prompt_wav),
            "--prompt_text",
            prompt_text,
            "--output",
            str(output_file),
        ]
        if os.getenv("MIMIKA_COSYVOICE3_FP32", "").strip().lower() in {"1", "true", "yes"}:
            command.append("--fp32")

        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            detail = stderr or stdout or f"exit={result.returncode}"
            raise RuntimeError(f"CosyVoice3 ONNX inference failed: {detail[-1000:]}")

    def _generate_via_inprocess(
        self,
        *,
        inproc_engine,
        text: str,
        prompt_wav: Path,
        prompt_text: str,
        total_steps: int,
    ):
        text_clean = text.strip()
        approx_tokens = max(1, len(text_clean) // 4)
        max_factor = max(6, int(os.getenv("MIMIKA_COSYVOICE3_MAX_TOKEN_FACTOR", "12")))
        max_cap = max(60, int(os.getenv("MIMIKA_COSYVOICE3_MAX_TOKEN_CAP", "280")))
        min_floor = max(4, int(os.getenv("MIMIKA_COSYVOICE3_MIN_TOKEN_FLOOR", "8")))
        top_k = max(5, int(os.getenv("MIMIKA_COSYVOICE3_TOPK", "20")))

        max_len = max(min_floor * 3, min(max_cap, approx_tokens * max_factor))
        min_len = max(min_floor, min(max_len - 1, approx_tokens))

        step_count = max(3, min(int(total_steps), 12))
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            embedding = inproc_engine.extract_speaker_embedding(str(prompt_wav))
            prompt_tokens = inproc_engine.extract_speech_tokens(str(prompt_wav))
            prompt_mel = inproc_engine.extract_speech_mel(str(prompt_wav))

            speech_tokens = inproc_engine.llm_inference(
                text_clean,
                prompt_text=prompt_text,
                prompt_speech_tokens=prompt_tokens,
                sampling_k=top_k,
                max_len=max_len,
                min_len=min_len,
            )
            mel = inproc_engine.flow_inference(
                speech_tokens,
                embedding,
                prompt_tokens=prompt_tokens,
                prompt_mel=prompt_mel,
                n_timesteps=step_count,
            )
            return inproc_engine.hift_inference(mel)

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

        with self._generate_lock:
            try:
                # Fast path: keep ONNX sessions warm in-process across requests.
                inproc_engine = self._load_inprocess_engine(resolved_snapshot)
                audio = self._generate_via_inprocess(
                    inproc_engine=inproc_engine,
                    text=text.strip(),
                    prompt_wav=prompt_wav,
                    prompt_text=str(preset["prompt_text"]),
                    total_steps=params.total_steps,
                )
                sf.write(str(output_file), audio, SAMPLE_RATE)
            except Exception:
                # Fallback path preserves compatibility if in-process execution fails.
                self._generate_via_subprocess(
                    text=text.strip(),
                    output_file=output_file,
                    script_path=script_path,
                    model_dir=model_dir,
                    prompt_wav=prompt_wav,
                    prompt_text=str(preset["prompt_text"]),
                )

        self._last_snapshot_dir = resolved_snapshot
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
