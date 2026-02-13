# Suppress pkg_resources deprecation warning from third-party packages (perth, etc.)
# This must be done before any imports that might trigger the warning
import warnings
warnings.filterwarnings("ignore", message="pkg_resources is deprecated")

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional
import os
import re
import shutil
import threading
import tempfile
import urllib.request
import uuid
import soundfile as sf

from database import init_db, seed_db, get_connection
from version import VERSION, VERSION_NAME
from tts.kokoro_engine import get_kokoro_engine, BRITISH_VOICES, DEFAULT_VOICE
from tts.qwen3_engine import get_qwen3_engine, GenerationParams, QWEN_SPEAKERS, unload_all_engines
from tts.chatterbox_engine import get_chatterbox_engine, ChatterboxParams
from tts.text_chunking import smart_chunk_text
from tts.audio_utils import merge_audio_chunks, resample_audio
from models.registry import ModelRegistry
from settings_service import get_all_settings, get_setting, set_setting, get_output_folder, set_output_folder

# Request models
class KokoroRequest(BaseModel):
    text: str
    voice: str = DEFAULT_VOICE
    speed: float = 1.0
    smart_chunking: bool = True
    max_chars_per_chunk: int = 1500
    crossfade_ms: int = 40

class Qwen3Request(BaseModel):
    text: str
    mode: str = "clone"  # "clone" or "custom"
    voice_name: Optional[str] = None  # For clone mode
    speaker: Optional[str] = None  # For custom mode (preset speaker)
    language: str = "Auto"
    speed: float = 1.0
    model_size: str = "0.6B"  # "0.6B" or "1.7B"
    model_quantization: str = "bf16"  # "bf16" or "8bit"
    instruct: Optional[str] = None  # Style instruction for custom mode
    streaming_interval: float = 0.75  # Seconds between streamed chunks
    # Advanced parameters
    temperature: float = 0.9
    top_p: float = 0.9
    top_k: int = 50
    repetition_penalty: float = 1.0
    seed: int = -1
    unload_after: bool = False  # Unload model after generation

class Qwen3UploadRequest(BaseModel):
    name: str
    transcript: str

class ChatterboxRequest(BaseModel):
    text: str
    voice_name: str
    language: str = "en"
    speed: float = 1.0
    temperature: float = 0.8
    cfg_weight: float = 1.0
    exaggeration: float = 0.5
    seed: int = -1
    max_chars: int = 300
    crossfade_ms: int = 0
    unload_after: bool = False

class IndexTTS2Request(BaseModel):
    text: str
    voice_name: str
    speed: float = 1.0
    max_chars: int = 300
    crossfade_ms: int = 0
    unload_after: bool = False


class SettingsUpdateRequest(BaseModel):
    key: str
    value: str


# Lifespan context manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Initializing database...")
    init_db()
    seed_db()
    _sync_output_folder_runtime(get_output_folder())
    _migrate_legacy_voice_samples()
    print("Database ready.")
    yield
    # Shutdown
    print("Shutting down...")

app = FastAPI(
    title="MimikaStudio API",
    description="Local-first Voice Cloning with Qwen3-TTS and Kokoro",
    version=VERSION,
    lifespan=lifespan
)

# CORS origins are configurable for production hardening.
_default_local_origins = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:8000",
    "http://127.0.0.1",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:8000",
]
_cors_origins_env = os.getenv("MIMIKA_CORS_ORIGINS", "")
_configured_cors_origins = [origin.strip() for origin in _cors_origins_env.split(",") if origin.strip()]
ALLOWED_CORS_ORIGINS = _configured_cors_origins or _default_local_origins

# CORS for Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount outputs directory for serving audio files
outputs_dir = Path(__file__).parent / "outputs"
outputs_dir.mkdir(parents=True, exist_ok=True)
app.mount("/audio", StaticFiles(directory=str(outputs_dir)), name="audio")


def _sync_output_folder_runtime(path: str) -> Path:
    """Apply output-folder setting to runtime storage and /audio static mount."""
    global outputs_dir
    resolved = Path(path).expanduser()
    resolved.mkdir(parents=True, exist_ok=True)
    outputs_dir = resolved

    # Retarget the mounted /audio StaticFiles app without requiring restart.
    for route in app.router.routes:
        if getattr(route, "name", "") != "audio":
            continue
        static_app = getattr(route, "app", None)
        if static_app is None:
            break
        if hasattr(static_app, "directory"):
            static_app.directory = str(resolved)
        if hasattr(static_app, "all_directories"):
            static_app.all_directories = [str(resolved)]
        if hasattr(static_app, "config_checked"):
            static_app.config_checked = False
        break

    return resolved


def _normalize_pdf_text_for_tts(text: str) -> str:
    """Normalize extracted PDF text for sentence parsing and read-aloud."""
    if not text:
        return ""

    # Fix wrapped line breaks where a sentence continues on the next line.
    normalized = re.sub(r"(?<!\n)\n(?!\n)", " ", text)
    normalized = normalized.replace("\u00a0", " ")

    # Split sentence punctuation from glued next words.
    normalized = re.sub(r"([.!?;:,])(?=[A-Za-z])", r"\1 ", normalized)
    # Split simple camel-case joins from bad extractors (earthAnd -> earth And).
    normalized = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", normalized)

    # Collapse extra whitespace while preserving paragraph breaks.
    normalized = re.sub(r"[ \t]+", " ", normalized)
    normalized = re.sub(r"\n{3,}", "\n\n", normalized)
    return normalized.strip()

# Qwen3 voice storage locations
SHARED_SAMPLE_VOICES_DIR = Path(__file__).parent / "data" / "samples" / "voices"
QWEN3_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
QWEN3_USER_VOICES_DIR = Path(__file__).parent / "data" / "user_voices" / "qwen3"

# Chatterbox voice storage locations
CHATTERBOX_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
CHATTERBOX_USER_VOICES_DIR = Path(__file__).parent / "data" / "user_voices" / "chatterbox"

# IndexTTS-2 voice storage locations
INDEXTTS2_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
INDEXTTS2_USER_VOICES_DIR = QWEN3_USER_VOICES_DIR
DICTA_MODEL_DIR = Path(__file__).parent / "models" / "dicta-onnx"
DICTA_MODEL_PATH = DICTA_MODEL_DIR / "dicta-1.0.onnx"
DICTA_MODEL_URL = (
    "https://github.com/thewh1teagle/dicta-onnx/releases/download/model-files-v1.0/dicta-1.0.onnx"
)


def _get_indextts2_engine():
    """Lazy-load IndexTTS-2 to keep backend bootable without torch."""
    try:
        from tts.indextts2_engine import get_indextts2_engine as _factory
    except Exception as exc:
        raise ImportError(
            "IndexTTS-2 runtime unavailable. This build is configured for MLX-Audio engines only."
        ) from exc
    return _factory()


def _get_all_voices() -> list:
    """List all voice samples across all engines (shared pool)."""
    all_dirs = [
        ("shared", SHARED_SAMPLE_VOICES_DIR, "default"),
        ("qwen3", QWEN3_USER_VOICES_DIR, "user"),
        ("chatterbox", CHATTERBOX_USER_VOICES_DIR, "user"),
        ("indextts2", INDEXTTS2_SAMPLE_VOICES_DIR, "default"),
        ("indextts2", INDEXTTS2_USER_VOICES_DIR, "user"),
    ]
    voices: dict[str, dict] = {}
    for origin_engine, vdir, source in all_dirs:
        if not vdir.exists():
            continue
        for wav in vdir.glob("*.wav"):
            name = wav.stem
            if name not in voices:
                transcript = ""
                txt_file = wav.with_suffix(".txt")
                if txt_file.exists():
                    transcript = txt_file.read_text().strip()
                voices[name] = {
                    "name": name,
                    "source": source,
                    "origin_engine": origin_engine,
                    "transcript": transcript,
                    "audio_path": str(wav),
                }
    return list(voices.values())


def _find_voice_audio(name: str) -> Optional[Path]:
    """Search all voice directories for a voice file by name."""
    all_dirs = [
        SHARED_SAMPLE_VOICES_DIR,
        QWEN3_USER_VOICES_DIR,
        CHATTERBOX_USER_VOICES_DIR,
        INDEXTTS2_USER_VOICES_DIR, INDEXTTS2_SAMPLE_VOICES_DIR,
    ]
    for vdir in all_dirs:
        audio_file = vdir / f"{name}.wav"
        if audio_file.exists():
            return audio_file
    return None


def _is_shared_default_voice(name: str) -> bool:
    """Default voices are determined by location, not hardcoded names."""
    if not name:
        return False
    target = name.lower()
    return any(wav.stem.lower() == target for wav in SHARED_SAMPLE_VOICES_DIR.glob("*.wav"))


def _migrate_legacy_voice_samples() -> None:
    """Consolidate legacy sample folders into the shared defaults folder."""
    samples_root = Path(__file__).parent / "data" / "samples"
    shared_dir = SHARED_SAMPLE_VOICES_DIR
    legacy_qwen3_dir = samples_root / "qwen3_voices"
    legacy_chatterbox_dir = samples_root / "chatterbox_voices"

    shared_dir.mkdir(parents=True, exist_ok=True)
    QWEN3_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    CHATTERBOX_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    INDEXTTS2_SAMPLE_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    INDEXTTS2_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

    def move_voice(src_dir: Path, name: str, dest_dir: Path) -> None:
        src_wav = src_dir / f"{name}.wav"
        src_txt = src_dir / f"{name}.txt"
        if src_wav.exists():
            dest_wav = dest_dir / src_wav.name
            if dest_wav.exists():
                src_wav.unlink()
            else:
                shutil.move(str(src_wav), str(dest_wav))
        if src_txt.exists():
            dest_txt = dest_dir / src_txt.name
            if dest_txt.exists():
                src_txt.unlink()
            else:
                shutil.move(str(src_txt), str(dest_txt))

    # Migrate deprecated engine-specific sample folders into shared defaults.
    for legacy_dir in (legacy_qwen3_dir, legacy_chatterbox_dir):
        if not legacy_dir.exists():
            continue
        for wav_file in legacy_dir.glob("*.wav"):
            move_voice(legacy_dir, wav_file.stem, shared_dir)


def _safe_tag(value: str, fallback: str = "model") -> str:
    tag = re.sub(r"[^a-zA-Z0-9_-]+", "", value.replace("/", "-").replace(" ", "-")).strip("-_")
    return tag[:32] if tag else fallback


def _generate_chunked_audio(
    text: str,
    max_chars_per_chunk: int,
    crossfade_ms: int,
    smart_chunking: bool,
    generate_fn,
) -> tuple:
    chunks = smart_chunk_text(text, max_chars=max_chars_per_chunk) if smart_chunking else [text]
    chunks = [c for c in chunks if c.strip()]
    if not chunks:
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    all_audio = []
    sample_rate = None

    for chunk in chunks:
        audio, sr = generate_fn(chunk)
        if audio is None or len(audio) == 0:
            continue
        if sample_rate is None:
            sample_rate = sr
        elif sr != sample_rate:
            audio = resample_audio(audio, sr, sample_rate)
        all_audio.append(audio)

    if not all_audio or sample_rate is None:
        raise HTTPException(status_code=500, detail="No audio generated")

    merged = merge_audio_chunks(all_audio, sample_rate, crossfade_ms=crossfade_ms)
    return merged, sample_rate, len(chunks)

# Health check
@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "mimikastudio"}

# System info
@app.get("/api/system/info")
async def system_info():
    """Get system information including Python version, device, and model versions."""
    import sys
    import platform
    from importlib import metadata

    try:
        import mlx.core as mx
        mlx_available = bool(mx.metal.is_available())
    except Exception:
        mlx_available = False

    device = "MLX (Apple Silicon)" if mlx_available else "CPU"
    try:
        mlx_audio_version = metadata.version("mlx-audio")
    except Exception:
        mlx_audio_version = "unknown"

    # Get model versions from each engine
    kokoro_info = {
        "model": "mlx-community/Kokoro-82M-bf16",
        "backend": "mlx-audio",
        "voice_pack": "British English",
    }
    qwen3_info = {
        "model": "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
        "backend": "mlx-audio",
        "features": "3-sec voice clone + custom speakers",
    }
    chatterbox_info = {
        "model": "mlx-community/chatterbox-fp16",
        "backend": "mlx-audio",
        "features": "voice clone",
    }

    return {
        "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "os": f"{platform.system()} {platform.release()}",
        "arch": platform.machine(),
        "device": device,
        "runtime": "mlx-audio",
        "mlx_audio_version": mlx_audio_version,
        "torch_version": None,
        "models": {
            "kokoro": kokoro_info,
            "qwen3": qwen3_info,
            "chatterbox": chatterbox_info,
        }
    }

# System monitoring
@app.get("/api/system/stats")
async def system_stats():
    """Get real-time system stats: CPU, RAM, GPU memory."""
    import psutil
    try:
        import mlx.core as mx
    except Exception:
        mx = None

    # CPU usage
    cpu_percent = psutil.cpu_percent(interval=0.1)

    # RAM usage
    memory = psutil.virtual_memory()
    ram_used_gb = memory.used / (1024 ** 3)
    ram_total_gb = memory.total / (1024 ** 3)
    ram_percent = memory.percent

    result = {
        "cpu_percent": round(cpu_percent, 1),
        "ram_used_gb": round(ram_used_gb, 1),
        "ram_total_gb": round(ram_total_gb, 1),
        "ram_percent": round(ram_percent, 1),
        "gpu": None,
    }

    # GPU memory (if available on MLX)
    if mx is not None and mx.metal.is_available():
        active_mem = mx.get_active_memory() / (1024 ** 3)
        peak_mem = mx.get_peak_memory() / (1024 ** 3)
        result["gpu"] = {
            "name": "Apple Silicon (MLX)",
            "memory_used_gb": round(active_mem, 2),
            "memory_total_gb": None,
            "memory_percent": None,
            "peak_memory_gb": round(peak_mem, 2),
            "note": "MLX memory is shared with system RAM",
        }

    return result


# ============== Unified Custom Voices Endpoint ==============

@app.get("/api/voices/custom")
async def list_all_custom_voices():
    """List all custom voice samples for unified voice cloning."""
    samples_root = Path(__file__).parent / "data" / "samples"

    def _audio_url_from_path(path: Path) -> Optional[str]:
        try:
            rel_path = path.relative_to(samples_root)
        except ValueError:
            return None
        return f"/samples/{rel_path.as_posix()}"

    voices_by_name: dict[str, dict] = {}

    def add_voice(source_engine: str, voice: dict) -> None:
        name = voice.get("name")
        if not name:
            return
        audio_path = Path(voice.get("audio_path", ""))
        audio_url = _audio_url_from_path(audio_path) if audio_path and audio_path.exists() else None
        existing = voices_by_name.get(name)
        if existing:
            if source_engine not in existing["engines"]:
                existing["engines"].append(source_engine)
            # Prefer transcript from any source if current one is empty.
            if not existing.get("transcript") and voice.get("transcript"):
                existing["transcript"] = voice.get("transcript")
            if not existing.get("audio_url") and audio_url:
                existing["audio_url"] = audio_url
            return

        voices_by_name[name] = {
            "name": name,
            "source": source_engine,
            "engines": [source_engine],
            "transcript": voice.get("transcript"),
            "has_audio": True,
            "audio_url": audio_url,
        }

    # Get Qwen3 voices
    try:
        engine = get_qwen3_engine()
        qwen3_voices = engine.get_saved_voices()
        for voice in qwen3_voices:
            add_voice("qwen3", voice)
    except ImportError:
        pass  # Qwen3 not installed

    # Get Chatterbox voices
    try:
        engine = get_chatterbox_engine()
        chatterbox_voices = engine.get_saved_voices()
        for voice in chatterbox_voices:
            add_voice("chatterbox", voice)
    except ImportError:
        pass  # Chatterbox not installed

    voices = list(voices_by_name.values())
    voices.sort(key=lambda v: v["name"].lower())
    return {"voices": voices, "total": len(voices)}


# ============== Kokoro Endpoints ==============

@app.post("/api/kokoro/generate")
async def kokoro_generate(request: KokoroRequest):
    """Generate speech using Kokoro with predefined British voice."""
    try:
        engine = get_kokoro_engine()
        voice = request.voice if request.voice in BRITISH_VOICES else DEFAULT_VOICE

        audio, sample_rate, _ = _generate_chunked_audio(
            text=request.text,
            max_chars_per_chunk=request.max_chars_per_chunk,
            crossfade_ms=request.crossfade_ms,
            smart_chunking=request.smart_chunking,
            generate_fn=lambda chunk: engine.generate_audio(chunk, voice=voice, speed=request.speed),
        )

        short_uuid = str(uuid.uuid4())[:8]
        output_path = outputs_dir / f"kokoro-{voice}-{short_uuid}.wav"
        sf.write(str(output_path), audio, sample_rate)

        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Kokoro backend unavailable. Run: pip install -U mlx-audio. Error: {e}",
        )

@app.get("/api/kokoro/voices")
async def kokoro_list_voices():
    """List available British Kokoro voices."""
    voices = []
    for code, info in BRITISH_VOICES.items():
        voices.append({
            "code": code,
            "name": info["name"],
            "gender": info["gender"],
            "grade": info["grade"],
            "is_default": code == DEFAULT_VOICE
        })
    # Sort by grade (best first)
    voices.sort(key=lambda v: v["grade"])
    return {"voices": voices, "default": DEFAULT_VOICE}

# ============== Qwen3-TTS Endpoints (Voice Clone + Custom Voice) ==============

@app.post("/api/qwen3/generate")
async def qwen3_generate(request: Qwen3Request):
    """Generate speech using Qwen3-TTS.

    Supports two modes:
    - clone: Voice cloning from reference audio (requires voice_name)
    - custom: Preset speaker voices (requires speaker)
    """
    try:
        if request.model_quantization not in {"bf16", "8bit"}:
            raise HTTPException(
                status_code=400,
                detail="model_quantization must be 'bf16' or '8bit'",
            )

        # Build generation parameters
        params = GenerationParams(
            temperature=request.temperature,
            top_p=request.top_p,
            top_k=request.top_k,
            repetition_penalty=request.repetition_penalty,
            seed=request.seed,
        )

        if request.mode == "clone":
            # Voice Clone mode
            if not request.voice_name:
                raise HTTPException(
                    status_code=400,
                    detail="Clone mode requires voice_name"
                )

            engine = get_qwen3_engine(
                model_size=request.model_size,
                quantization=request.model_quantization,
                mode="clone"
            )
            engine.outputs_dir = outputs_dir
            engine.outputs_dir.mkdir(parents=True, exist_ok=True)
            voices = engine.get_saved_voices()

            # Find the voice (search own engine first, then all engines)
            voice = next((v for v in voices if v["name"] == request.voice_name), None)
            if voice is None:
                audio_file = _find_voice_audio(request.voice_name)
                if audio_file is None:
                    raise HTTPException(
                        status_code=404,
                        detail=f"Voice '{request.voice_name}' not found. Upload a voice first."
                    )
                transcript = ""
                txt_file = audio_file.with_suffix(".txt")
                if txt_file.exists():
                    transcript = txt_file.read_text().strip()
                voice = {"name": request.voice_name, "audio_path": str(audio_file), "transcript": transcript}

            output_path = engine.generate_voice_clone(
                text=request.text,
                ref_audio_path=voice["audio_path"],
                ref_text=voice["transcript"],
                language=request.language,
                speed=request.speed,
                params=params,
            )

            result = {
                "audio_url": f"/audio/{output_path.name}",
                "filename": output_path.name,
                "mode": "clone",
                "voice": request.voice_name,
            }

        elif request.mode == "custom":
            # Custom Voice mode (preset speakers)
            if not request.speaker:
                raise HTTPException(
                    status_code=400,
                    detail="Custom mode requires speaker"
                )

            if request.speaker not in QWEN_SPEAKERS:
                raise HTTPException(
                    status_code=400,
                    detail=f"Unknown speaker: {request.speaker}. Available: {list(QWEN_SPEAKERS)}"
                )

            engine = get_qwen3_engine(
                model_size=request.model_size,
                quantization=request.model_quantization,
                mode="custom"
            )
            engine.outputs_dir = outputs_dir
            engine.outputs_dir.mkdir(parents=True, exist_ok=True)

            output_path = engine.generate_custom_voice(
                text=request.text,
                speaker=request.speaker,
                language=request.language,
                instruct=request.instruct,
                speed=request.speed,
                params=params,
            )

            result = {
                "audio_url": f"/audio/{output_path.name}",
                "filename": output_path.name,
                "mode": "custom",
                "speaker": request.speaker,
            }

        else:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown mode: {request.mode}. Use 'clone' or 'custom'"
            )

        # Optionally unload model after generation
        if request.unload_after:
            engine.unload()

        return result

    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Qwen3-TTS backend unavailable. Run: pip install -U mlx-audio. Error: {e}"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/qwen3/generate/stream")
async def qwen3_generate_stream(request: Qwen3Request):
    """Generate speech and stream raw PCM chunks as they are synthesized."""
    from fastapi.responses import StreamingResponse

    try:
        if request.model_quantization not in {"bf16", "8bit"}:
            raise HTTPException(
                status_code=400,
                detail="model_quantization must be 'bf16' or '8bit'",
            )

        params = GenerationParams(
            temperature=request.temperature,
            top_p=request.top_p,
            top_k=request.top_k,
            repetition_penalty=request.repetition_penalty,
            seed=request.seed,
        )

        if request.mode == "clone":
            if not request.voice_name:
                raise HTTPException(
                    status_code=400,
                    detail="Clone mode requires voice_name"
                )

            engine = get_qwen3_engine(
                model_size=request.model_size,
                quantization=request.model_quantization,
                mode="clone",
            )
            engine.outputs_dir = outputs_dir
            engine.outputs_dir.mkdir(parents=True, exist_ok=True)
            voices = engine.get_saved_voices()
            voice = next((v for v in voices if v["name"] == request.voice_name), None)
            if voice is None:
                audio_file = _find_voice_audio(request.voice_name)
                if audio_file is None:
                    raise HTTPException(
                        status_code=404,
                        detail=f"Voice '{request.voice_name}' not found. Upload a voice first."
                    )
                transcript = ""
                txt_file = audio_file.with_suffix(".txt")
                if txt_file.exists():
                    transcript = txt_file.read_text().strip()
                voice = {
                    "name": request.voice_name,
                    "audio_path": str(audio_file),
                    "transcript": transcript,
                }

            chunk_iter = engine.stream_voice_clone_pcm(
                text=request.text,
                ref_audio_path=voice["audio_path"],
                ref_text=voice["transcript"],
                language=request.language,
                speed=request.speed,
                streaming_interval=request.streaming_interval,
                params=params,
            )

        elif request.mode == "custom":
            if not request.speaker:
                raise HTTPException(
                    status_code=400,
                    detail="Custom mode requires speaker"
                )

            if request.speaker not in QWEN_SPEAKERS:
                raise HTTPException(
                    status_code=400,
                    detail=f"Unknown speaker: {request.speaker}. Available: {list(QWEN_SPEAKERS)}"
                )

            engine = get_qwen3_engine(
                model_size=request.model_size,
                quantization=request.model_quantization,
                mode="custom",
            )
            engine.outputs_dir = outputs_dir
            engine.outputs_dir.mkdir(parents=True, exist_ok=True)
            chunk_iter = engine.stream_custom_voice_pcm(
                text=request.text,
                speaker=request.speaker,
                language=request.language,
                instruct=request.instruct,
                speed=request.speed,
                streaming_interval=request.streaming_interval,
                params=params,
            )
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown mode: {request.mode}. Use 'clone' or 'custom'"
            )

        def iterator():
            try:
                for chunk in chunk_iter:
                    if chunk:
                        yield chunk
            finally:
                if request.unload_after:
                    engine.unload()

        headers = {
            "X-Audio-Format": "pcm_s16le",
            "X-Audio-Sample-Rate": "24000",
            "X-Audio-Channels": "1",
        }
        return StreamingResponse(
            iterator(),
            media_type="audio/L16; rate=24000; channels=1",
            headers=headers,
        )

    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Qwen3-TTS backend unavailable. Run: pip install -U mlx-audio. Error: {e}"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/qwen3/voices")
async def qwen3_list_voices():
    """List all voice samples available for Qwen3 cloning (shared across engines)."""
    voices = _get_all_voices()
    for voice in voices:
        name = voice.get("name")
        if name:
            voice["audio_url"] = f"/api/qwen3/voices/{name}/audio"
    return {"voices": voices}


@app.get("/api/qwen3/voices/{name}/audio")
async def qwen3_voice_audio(name: str):
    """Serve a voice sample audio file for preview (searches all engines)."""
    if not re.match(r"^[A-Za-z0-9_-]+$", name):
        raise HTTPException(status_code=400, detail="Invalid voice name")

    audio_file = _find_voice_audio(name)
    if audio_file:
        return FileResponse(audio_file, media_type="audio/wav")

    raise HTTPException(status_code=404, detail="Voice audio not found")


@app.get("/api/qwen3/speakers")
async def qwen3_list_speakers():
    """List available preset speakers for CustomVoice mode."""
    return {
        "speakers": list(QWEN_SPEAKERS),
        "speaker_info": {
            "Ryan": {"language": "English", "description": "Dynamic male with strong rhythm"},
            "Aiden": {"language": "English", "description": "Sunny American male"},
            "Vivian": {"language": "Chinese", "description": "Bright young female"},
            "Serena": {"language": "Chinese", "description": "Warm gentle female"},
            "Uncle_Fu": {"language": "Chinese", "description": "Seasoned male, low mellow"},
            "Dylan": {"language": "Chinese", "description": "Beijing youthful male"},
            "Eric": {"language": "Chinese", "description": "Sichuan lively male"},
            "Ono_Anna": {"language": "Japanese", "description": "Playful female"},
            "Sohee": {"language": "Korean", "description": "Warm emotional female"},
        }
    }


@app.get("/api/qwen3/models")
async def qwen3_list_models():
    """List available Qwen3-TTS models with their capabilities."""
    registry = ModelRegistry()
    models = registry.list_models()
    return {
        "models": [
            {
                "name": m.name,
                "engine": m.engine,
                "mode": m.mode,
                "quantization": m.quantization,
                "size_gb": m.size_gb,
                "speakers": list(m.speakers) if m.speakers else None,
            }
            for m in models
        ]
    }


@app.post("/api/qwen3/voices")
async def qwen3_upload_voice(
    file: UploadFile = File(...),
    name: str = Form(...),
    transcript: str = Form(...),
):
    """Upload a new voice sample for Qwen3 cloning.

    Requires:
    - Audio file (WAV, 3+ seconds recommended)
    - Transcript of what is said in the audio
    """
    if not transcript.strip():
        raise HTTPException(
            status_code=400,
            detail="Transcript is required for voice cloning"
        )
    if _is_shared_default_voice(name):
        raise HTTPException(
            status_code=400,
            detail="That name is reserved for default voices"
        )

    try:
        engine = get_qwen3_engine()

        # Save uploaded file temporarily
        outputs_dir.mkdir(parents=True, exist_ok=True)
        temp_path = outputs_dir / f"temp_{name}.wav"
        with open(temp_path, "wb") as f:
            shutil.copyfileobj(file.file, f)

        # Save as voice sample
        voice_info = engine.save_voice_sample(
            name=name,
            audio_path=str(temp_path),
            transcript=transcript.strip()
        )

        # Clean up temp file
        temp_path.unlink(missing_ok=True)

        return {
            "message": f"Voice '{name}' saved successfully",
            "voice": voice_info,
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Qwen3-TTS not installed: {e}"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/qwen3/voices/{name}")
async def qwen3_delete_voice(name: str):
    """Delete a Qwen3 voice sample."""
    # Prevent deleting shipped voices
    if _is_shared_default_voice(name):
        raise HTTPException(status_code=400, detail="Default voices cannot be deleted")

    audio_file = QWEN3_USER_VOICES_DIR / f"{name}.wav"
    transcript_file = QWEN3_USER_VOICES_DIR / f"{name}.txt"

    if audio_file.exists():
        audio_file.unlink()
        if transcript_file.exists():
            transcript_file.unlink()
        # Clear cache for this voice
        try:
            engine = get_qwen3_engine()
            engine.clear_cache()
        except ImportError:
            pass
        return {"message": f"Voice '{name}' deleted successfully"}

    raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")


@app.put("/api/qwen3/voices/{name}")
async def qwen3_update_voice(
    name: str,
    new_name: Optional[str] = Form(None),
    transcript: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    """Update a Qwen3 voice sample (rename, update transcript, or replace audio)."""
    # Prevent editing shipped voices
    if _is_shared_default_voice(name):
        raise HTTPException(status_code=400, detail="Default voices cannot be modified")

    old_audio = QWEN3_USER_VOICES_DIR / f"{name}.wav"
    old_transcript = QWEN3_USER_VOICES_DIR / f"{name}.txt"
    if not old_audio.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    final_name = new_name or name
    if _is_shared_default_voice(final_name):
        raise HTTPException(
            status_code=400,
            detail="That name is reserved for default voices"
        )
    QWEN3_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

    new_audio = QWEN3_USER_VOICES_DIR / f"{final_name}.wav"
    new_transcript = QWEN3_USER_VOICES_DIR / f"{final_name}.txt"

    # Update audio if provided
    if file:
        with open(new_audio, "wb") as f:
            shutil.copyfileobj(file.file, f)
        if old_audio.exists() and old_audio != new_audio:
            old_audio.unlink()
    elif old_audio != new_audio:
        # Rename file
        old_audio.rename(new_audio)

    # Update transcript
    if transcript is not None:
        new_transcript.write_text(transcript.strip())
    elif old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.rename(new_transcript)

    # Clean up old transcript if renaming
    if old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.unlink(missing_ok=True)

    # Clear cache
    try:
        engine = get_qwen3_engine()
        engine.clear_cache()
    except ImportError:
        pass

    return {
        "message": f"Voice updated successfully",
        "name": final_name,
        "transcript": transcript or (new_transcript.read_text() if new_transcript.exists() else ""),
    }


@app.get("/api/qwen3/languages")
async def qwen3_list_languages():
    """List supported languages for Qwen3-TTS."""
    try:
        engine = get_qwen3_engine()
        return {"languages": engine.get_languages()}
    except ImportError:
        # Return default list even if not installed
        return {
            "languages": [
                "Chinese", "English", "Japanese", "Korean", "German",
                "French", "Russian", "Portuguese", "Spanish", "Italian"
            ]
        }


@app.get("/api/qwen3/info")
async def qwen3_info():
    """Get Qwen3-TTS model information."""
    try:
        engine = get_qwen3_engine()
        return engine.get_model_info()
    except ImportError:
        return {
            "name": "Qwen3-TTS",
            "installed": False,
            "error": "Run: pip install -U mlx-audio",
        }


@app.post("/api/qwen3/clear-cache")
async def qwen3_clear_cache():
    """Clear Qwen3 voice prompt cache and free memory."""
    try:
        engine = get_qwen3_engine()
        engine.clear_cache()
        return {"message": "Cache cleared successfully"}
    except Exception as e:
        return {"message": f"Error clearing cache: {e}"}


# ============== Chatterbox Endpoints (Voice Clone) ==============

@app.post("/api/chatterbox/generate")
async def chatterbox_generate(request: ChatterboxRequest):
    """Generate speech using Chatterbox voice cloning."""
    try:
        engine = get_chatterbox_engine()
        engine.outputs_dir = outputs_dir
        engine.outputs_dir.mkdir(parents=True, exist_ok=True)
        voices = engine.get_saved_voices()
        voice = next((v for v in voices if v["name"] == request.voice_name), None)
        if voice is None:
            # Search across all engine voice directories
            audio_file = _find_voice_audio(request.voice_name)
            if audio_file is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Voice '{request.voice_name}' not found. Upload a voice first.",
                )
            voice = {"name": request.voice_name, "audio_path": str(audio_file)}

        params = ChatterboxParams(
            temperature=request.temperature,
            cfg_weight=request.cfg_weight,
            exaggeration=request.exaggeration,
            seed=request.seed,
        )

        output_path = engine.generate_voice_clone(
            text=request.text,
            voice_name=request.voice_name,
            ref_audio_path=voice["audio_path"],
            language=request.language,
            speed=request.speed,
            params=params,
            max_chars=request.max_chars,
            crossfade_ms=request.crossfade_ms,
        )

        if request.unload_after:
            engine.unload()

        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name,
            "mode": "clone",
            "voice": request.voice_name,
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Chatterbox backend unavailable. Run: pip install -U mlx-audio. Error: {e}",
        )


@app.get("/api/chatterbox/voices")
async def chatterbox_list_voices():
    """List all voice samples available for Chatterbox cloning (shared across engines)."""
    voices = _get_all_voices()
    for voice in voices:
        name = voice.get("name")
        if name:
            voice["audio_url"] = f"/api/chatterbox/voices/{name}/audio"
    return {"voices": voices}


@app.get("/api/chatterbox/voices/{name}/audio")
async def chatterbox_voice_audio(name: str):
    """Serve a voice sample audio file for preview (searches all engines)."""
    if not name or "/" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid voice name")

    audio_file = _find_voice_audio(name)
    if audio_file:
        return FileResponse(audio_file, media_type="audio/wav")

    raise HTTPException(status_code=404, detail="Voice sample not found")


@app.post("/api/chatterbox/voices")
async def chatterbox_upload_voice(
    name: str = Form(...),
    file: UploadFile = File(...),
    transcript: Optional[str] = Form(""),
):
    """Upload a new voice sample for Chatterbox cloning."""
    if not name or len(name.strip()) == 0:
        raise HTTPException(status_code=400, detail="Voice name is required")

    if _is_shared_default_voice(name):
        raise HTTPException(status_code=400, detail="That name is reserved for default voices")

    CHATTERBOX_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    file_path = CHATTERBOX_USER_VOICES_DIR / f"{name}.wav"

    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    transcript_path = CHATTERBOX_USER_VOICES_DIR / f"{name}.txt"
    if transcript is not None:
        transcript_path.write_text(transcript.strip())

    try:
        engine = get_chatterbox_engine()
        return {
            "message": "Voice uploaded successfully",
            "voice": engine.get_saved_voices(),
        }
    except ImportError:
        return {"message": "Voice uploaded (engine not installed)", "name": name}


@app.delete("/api/chatterbox/voices/{name}")
async def chatterbox_delete_voice(name: str):
    """Delete a Chatterbox voice sample."""
    if _is_shared_default_voice(name):
        raise HTTPException(status_code=400, detail="Default voices cannot be deleted")

    audio_path = CHATTERBOX_USER_VOICES_DIR / f"{name}.wav"
    transcript_path = CHATTERBOX_USER_VOICES_DIR / f"{name}.txt"

    if not audio_path.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    audio_path.unlink()
    transcript_path.unlink(missing_ok=True)

    return {"message": f"Voice '{name}' deleted"}


@app.put("/api/chatterbox/voices/{name}")
async def chatterbox_update_voice(
    name: str,
    new_name: Optional[str] = Form(None),
    transcript: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    """Update a Chatterbox voice sample (rename, update transcript, or replace audio)."""
    if _is_shared_default_voice(name):
        raise HTTPException(status_code=400, detail="Default voices cannot be modified")

    old_audio = CHATTERBOX_USER_VOICES_DIR / f"{name}.wav"
    old_transcript = CHATTERBOX_USER_VOICES_DIR / f"{name}.txt"
    if not old_audio.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    final_name = new_name or name
    if _is_shared_default_voice(final_name):
        raise HTTPException(status_code=400, detail="That name is reserved for default voices")

    CHATTERBOX_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    new_audio = CHATTERBOX_USER_VOICES_DIR / f"{final_name}.wav"
    new_transcript = CHATTERBOX_USER_VOICES_DIR / f"{final_name}.txt"

    if file:
        with open(new_audio, "wb") as f:
            shutil.copyfileobj(file.file, f)
        if old_audio.exists() and old_audio != new_audio:
            old_audio.unlink()
    elif old_audio != new_audio:
        old_audio.rename(new_audio)

    if transcript is not None:
        new_transcript.write_text(transcript.strip())
    elif old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.rename(new_transcript)

    if old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.unlink(missing_ok=True)

    return {
        "message": "Voice updated successfully",
        "name": final_name,
        "transcript": transcript or (new_transcript.read_text() if new_transcript.exists() else ""),
    }


@app.get("/api/chatterbox/languages")
async def chatterbox_list_languages():
    """List supported languages for Chatterbox."""
    try:
        engine = get_chatterbox_engine()
        languages = list(engine.get_languages())
        if "he" not in languages:
            languages.append("he")
        return {"languages": languages}
    except ImportError:
        return {"languages": ["en", "he"]}


@app.get("/api/chatterbox/info")
async def chatterbox_info():
    """Get Chatterbox model information."""
    try:
        engine = get_chatterbox_engine()
        return engine.get_model_info()
    except ImportError:
        return {
            "name": "Chatterbox Multilingual TTS",
            "installed": False,
            "error": "Run: pip install -U mlx-audio",
        }


_dicta_download_status: dict[str, Optional[str]] = {"status": None, "error": None}
_dicta_status_lock = threading.Lock()


def _dicta_status_payload() -> dict:
    installed = DICTA_MODEL_PATH.exists()
    size_mb = None
    if installed:
        size_mb = round(DICTA_MODEL_PATH.stat().st_size / (1024 * 1024), 1)
    with _dicta_status_lock:
        status = _dicta_download_status.get("status")
        error = _dicta_download_status.get("error")
    return {
        "installed": installed,
        "path": str(DICTA_MODEL_PATH),
        "size_mb": size_mb,
        "download_status": status,
        "download_error": error,
    }


@app.get("/api/chatterbox/dicta/status")
async def chatterbox_dicta_status():
    """Get Dicta Hebrew model status for Chatterbox."""
    return _dicta_status_payload()


@app.post("/api/chatterbox/dicta/download")
async def chatterbox_dicta_download():
    """Download Dicta Hebrew ONNX model used by Chatterbox Hebrew mode."""
    if DICTA_MODEL_PATH.exists():
        with _dicta_status_lock:
            _dicta_download_status["status"] = "completed"
            _dicta_download_status["error"] = None
        payload = _dicta_status_payload()
        payload["message"] = "Dicta model already installed"
        return payload

    with _dicta_status_lock:
        in_progress = _dicta_download_status.get("status") == "downloading"
    if in_progress:
        payload = _dicta_status_payload()
        payload["message"] = "Dicta download already in progress"
        return payload

    with _dicta_status_lock:
        _dicta_download_status["status"] = "downloading"
        _dicta_download_status["error"] = None

    def _do_download() -> None:
        temp_path = DICTA_MODEL_PATH.with_suffix(".onnx.part")
        try:
            DICTA_MODEL_DIR.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(DICTA_MODEL_URL, timeout=120) as response, temp_path.open("wb") as out:
                shutil.copyfileobj(response, out)
            temp_path.replace(DICTA_MODEL_PATH)
            with _dicta_status_lock:
                _dicta_download_status["status"] = "completed"
                _dicta_download_status["error"] = None
        except Exception as exc:
            temp_path.unlink(missing_ok=True)
            with _dicta_status_lock:
                _dicta_download_status["status"] = "failed"
                _dicta_download_status["error"] = str(exc)

    thread = threading.Thread(target=_do_download, daemon=True)
    thread.start()

    payload = _dicta_status_payload()
    payload["message"] = "Dicta download started"
    payload["url"] = DICTA_MODEL_URL
    return payload


# ============== IndexTTS-2 Endpoints (Voice Clone) ==============

@app.post("/api/indextts2/generate")
async def indextts2_generate(request: IndexTTS2Request):
    """Generate speech using IndexTTS-2 voice cloning."""
    try:
        engine = _get_indextts2_engine()
        engine.outputs_dir = outputs_dir
        engine.outputs_dir.mkdir(parents=True, exist_ok=True)
        voices = engine.get_saved_voices()
        voice = next((v for v in voices if v["name"] == request.voice_name), None)
        if voice is None:
            # Search across all engine voice directories
            audio_file = _find_voice_audio(request.voice_name)
            if audio_file is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Voice '{request.voice_name}' not found. Upload a voice first.",
                )
            voice = {"name": request.voice_name, "audio_path": str(audio_file)}

        output_path = engine.generate(
            text=request.text,
            voice_name=request.voice_name,
            ref_audio_path=voice["audio_path"],
            speed=request.speed,
            max_chars=request.max_chars,
            crossfade_ms=request.crossfade_ms,
        )

        if request.unload_after:
            engine.unload()

        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name,
            "mode": "clone",
            "voice": request.voice_name,
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"IndexTTS not installed. Run: pip install indextts>=0.2.0. Error: {e}",
        )


@app.get("/api/indextts2/voices")
async def indextts2_list_voices():
    """List all voice samples available for IndexTTS-2 cloning (shared across engines)."""
    voices = _get_all_voices()
    for voice in voices:
        name = voice.get("name")
        if name:
            voice["audio_url"] = f"/api/indextts2/voices/{name}/audio"
    return {"voices": voices}


@app.get("/api/indextts2/voices/{name}/audio")
async def indextts2_voice_audio(name: str):
    """Serve a voice sample audio file for preview (searches all engines)."""
    if not name or "/" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid voice name")

    audio_file = _find_voice_audio(name)
    if audio_file:
        return FileResponse(audio_file, media_type="audio/wav")

    raise HTTPException(status_code=404, detail="Voice sample not found")


@app.post("/api/indextts2/voices")
async def indextts2_upload_voice(
    name: str = Form(...),
    file: UploadFile = File(...),
    transcript: Optional[str] = Form(""),
):
    """Upload a new voice sample for IndexTTS-2 cloning."""
    if not name or len(name.strip()) == 0:
        raise HTTPException(status_code=400, detail="Voice name is required")

    INDEXTTS2_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    file_path = INDEXTTS2_USER_VOICES_DIR / f"{name}.wav"

    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    transcript_path = INDEXTTS2_USER_VOICES_DIR / f"{name}.txt"
    if transcript is not None:
        transcript_path.write_text(transcript.strip())

    try:
        engine = _get_indextts2_engine()
        return {
            "message": "Voice uploaded successfully",
            "voice": engine.get_saved_voices(),
        }
    except ImportError:
        return {"message": "Voice uploaded (engine not installed)", "name": name}


@app.delete("/api/indextts2/voices/{name}")
async def indextts2_delete_voice(name: str):
    """Delete an IndexTTS-2 voice sample."""
    if (INDEXTTS2_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
        raise HTTPException(status_code=400, detail="Default voices cannot be deleted")

    audio_path = INDEXTTS2_USER_VOICES_DIR / f"{name}.wav"
    transcript_path = INDEXTTS2_USER_VOICES_DIR / f"{name}.txt"

    if not audio_path.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    audio_path.unlink()
    transcript_path.unlink(missing_ok=True)

    return {"message": f"Voice '{name}' deleted"}


@app.put("/api/indextts2/voices/{name}")
async def indextts2_update_voice(
    name: str,
    new_name: Optional[str] = Form(None),
    transcript: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    """Update an IndexTTS-2 voice sample (rename, update transcript, or replace audio)."""
    if (INDEXTTS2_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
        raise HTTPException(status_code=400, detail="Default voices cannot be modified")

    old_audio = INDEXTTS2_USER_VOICES_DIR / f"{name}.wav"
    old_transcript = INDEXTTS2_USER_VOICES_DIR / f"{name}.txt"
    if not old_audio.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    final_name = new_name or name

    INDEXTTS2_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    new_audio = INDEXTTS2_USER_VOICES_DIR / f"{final_name}.wav"
    new_transcript = INDEXTTS2_USER_VOICES_DIR / f"{final_name}.txt"

    if file:
        with open(new_audio, "wb") as f:
            shutil.copyfileobj(file.file, f)
        if old_audio.exists() and old_audio != new_audio:
            old_audio.unlink()
    elif old_audio != new_audio:
        old_audio.rename(new_audio)

    if transcript is not None:
        new_transcript.write_text(transcript.strip())
    elif old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.rename(new_transcript)

    if old_transcript.exists() and old_transcript != new_transcript:
        old_transcript.unlink(missing_ok=True)

    return {
        "message": "Voice updated successfully",
        "name": final_name,
        "transcript": transcript or (new_transcript.read_text() if new_transcript.exists() else ""),
    }


@app.get("/api/indextts2/info")
async def indextts2_info():
    """Get IndexTTS-2 model information."""
    try:
        engine = _get_indextts2_engine()
        return engine.get_model_info()
    except ImportError:
        return {
            "name": "IndexTTS-2",
            "installed": False,
            "error": "Run: pip install indextts>=0.2.0",
        }


# ============== Model Management Endpoints ==============

# Track active downloads: model_name -> {"status": "downloading"/"completed"/"failed", "error": str}
_download_status: dict[str, dict] = {}
_download_status_lock = threading.Lock()


@app.get("/api/models/status")
async def models_status():
    """Check which models are downloaded and their sizes."""
    registry = ModelRegistry()
    models = []
    for m in registry.list_all_models():
        downloaded = registry.is_model_downloaded(m)
        with _download_status_lock:
            status_info = _download_status.get(m.name)
        models.append({
            "name": m.name,
            "engine": m.engine,
            "hf_repo": m.hf_repo,
            "size_gb": m.size_gb,
            "mode": m.mode,
            "model_type": m.model_type,
            "description": m.description,
            "downloaded": downloaded,
            "download_status": status_info.get("status") if status_info else None,
            "download_error": status_info.get("error") if status_info else None,
        })
    return {"models": models}


@app.post("/api/models/{model_name}/download")
async def model_download(model_name: str):
    """Trigger download of a HuggingFace model."""
    registry = ModelRegistry()
    model = registry.get_model(model_name)
    if model is None:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' not found")

    if model.model_type == "pip":
        raise HTTPException(
            status_code=400,
            detail="Pip packages must be installed via pip install, not downloaded here.",
        )

    if not model.hf_repo:
        raise HTTPException(status_code=400, detail="Model has no HuggingFace repo")

    # Check if already downloading
    with _download_status_lock:
        current = _download_status.get(model_name)
    if current and current.get("status") == "downloading":
        return {"message": "Download already in progress", "model": model_name}

    with _download_status_lock:
        _download_status[model_name] = {"status": "downloading", "error": None}

    def _do_download():
        try:
            from huggingface_hub import snapshot_download
            snapshot_download(model.hf_repo)
            with _download_status_lock:
                _download_status[model_name] = {"status": "completed", "error": None}
        except Exception as e:
            with _download_status_lock:
                _download_status[model_name] = {"status": "failed", "error": str(e)}

    thread = threading.Thread(target=_do_download, daemon=True)
    thread.start()

    return {
        "message": f"Download started for {model_name}",
        "model": model_name,
        "hf_repo": model.hf_repo,
        "size_gb": model.size_gb,
    }


@app.delete("/api/models/{model_name}")
async def model_delete(model_name: str):
    """Delete a downloaded HuggingFace model to free disk space."""
    registry = ModelRegistry()
    model = registry.get_model(model_name)
    if model is None:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' not found")

    if model.model_type == "pip":
        raise HTTPException(
            status_code=400,
            detail="Pip packages must be uninstalled via pip uninstall, not deleted here.",
        )

    if not model.hf_repo:
        raise HTTPException(status_code=400, detail="Model has no HuggingFace repo")

    # Check if downloaded
    if not registry.is_model_downloaded(model):
        raise HTTPException(status_code=400, detail=f"Model '{model_name}' is not downloaded")

    # Delete the model cache directory
    cache_dir = registry.models_dir / f"models--{model.hf_repo.replace('/', '--')}"
    if cache_dir.exists():
        import shutil
        try:
            shutil.rmtree(cache_dir)
            # Clear download status if any
            with _download_status_lock:
                if model_name in _download_status:
                    del _download_status[model_name]
            return {
                "message": f"Model '{model_name}' deleted successfully",
                "model": model_name,
                "freed_gb": model.size_gb,
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to delete model: {str(e)}")
    else:
        raise HTTPException(status_code=404, detail=f"Model cache directory not found")


# ============== Audiobook Generation Endpoints ==============
# Enhanced with features inspired by audiblez, pdf-narrator, and abogen

class AudiobookRequest(BaseModel):
    text: str
    title: str = "Untitled"
    voice: str = "bf_emma"
    speed: float = 1.0
    output_format: str = "wav"  # "wav", "mp3", or "m4b"
    subtitle_format: str = "none"  # "none", "srt", or "vtt"
    smart_chunking: bool = True
    max_chars_per_chunk: int = 1500
    crossfade_ms: int = 40


@app.post("/api/audiobook/generate")
async def audiobook_generate(request: AudiobookRequest):
    """Start audiobook generation from text with optional timestamped subtitles.

    Returns a job_id that can be used to poll for status.
    The generation runs in the background.

    Performance: ~60 chars/sec on M2 MacBook Pro CPU (matching audiblez benchmark).

    Args:
        text: Document text to convert
        title: Audiobook title
        voice: Kokoro voice ID (default: bf_emma)
        speed: Playback speed (default: 1.0)
        output_format: "wav", "mp3", or "m4b" (default: wav)
            - m4b includes chapter markers if document has chapters
        subtitle_format: "none", "srt", or "vtt" (default: none)
            - srt: SubRip subtitle format (widely compatible)
            - vtt: WebVTT format (web-friendly)
    """
    from tts.audiobook import create_audiobook_job

    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    # Validate output format
    output_format = request.output_format.lower()
    if output_format not in ("wav", "mp3", "m4b"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid output_format: {request.output_format}. Use 'wav', 'mp3', or 'm4b'"
        )

    # Validate subtitle format
    subtitle_format = request.subtitle_format.lower()
    if subtitle_format not in ("none", "srt", "vtt"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid subtitle_format: {request.subtitle_format}. Use 'none', 'srt', or 'vtt'"
        )

    if request.max_chars_per_chunk <= 0:
        raise HTTPException(status_code=400, detail="max_chars_per_chunk must be > 0")

    if request.crossfade_ms < 0:
        raise HTTPException(status_code=400, detail="crossfade_ms must be >= 0")

    job = create_audiobook_job(
        text=request.text,
        title=request.title,
        voice=request.voice,
        speed=request.speed,
        output_format=output_format,
        subtitle_format=subtitle_format,
        smart_chunking=request.smart_chunking,
        max_chars_per_chunk=request.max_chars_per_chunk,
        crossfade_ms=request.crossfade_ms,
    )

    return {
        "job_id": job.job_id,
        "status": job.status.value,
        "total_chunks": job.total_chunks,
        "total_chars": job.total_chars,
        "output_format": output_format,
        "subtitle_format": subtitle_format,
    }


@app.post("/api/audiobook/generate-from-file")
async def audiobook_generate_from_file(
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    voice: str = Form("bf_emma"),
    speed: float = Form(1.0),
    output_format: str = Form("wav"),
    subtitle_format: str = Form("none"),
    smart_chunking: bool = Form(True),
    max_chars_per_chunk: int = Form(1500),
    crossfade_ms: int = Form(40),
):
    """Start audiobook generation from uploaded file with optional timestamped subtitles.

    Supports PDF, EPUB, TXT, MD, DOCX formats.
    Automatically extracts chapters from PDF TOC or EPUB structure.
    Skips headers/footers/page numbers in PDFs (like pdf-narrator).

    Args:
        file: Document file to convert
        title: Audiobook title (defaults to filename)
        voice: Kokoro voice ID (default: bf_emma)
        speed: Playback speed (default: 1.0)
        output_format: "wav", "mp3", or "m4b" (default: wav)
        subtitle_format: "none", "srt", or "vtt" (default: none)
    """
    from tts.audiobook import create_audiobook_from_file
    import tempfile

    # Validate output format
    output_format = output_format.lower()
    if output_format not in ("wav", "mp3", "m4b"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid output_format: {output_format}. Use 'wav', 'mp3', or 'm4b'"
        )

    # Validate subtitle format
    subtitle_format = subtitle_format.lower()
    if subtitle_format not in ("none", "srt", "vtt"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid subtitle_format: {subtitle_format}. Use 'none', 'srt', or 'vtt'"
        )

    # Save uploaded file temporarily
    suffix = Path(file.filename).suffix if file.filename else ".txt"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    if max_chars_per_chunk <= 0:
        raise HTTPException(status_code=400, detail="max_chars_per_chunk must be > 0")

    if crossfade_ms < 0:
        raise HTTPException(status_code=400, detail="crossfade_ms must be >= 0")

    try:
        job = create_audiobook_from_file(
            file_path=tmp_path,
            title=title or (Path(file.filename).stem if file.filename else "Untitled"),
            voice=voice,
            speed=speed,
            output_format=output_format,
            subtitle_format=subtitle_format,
            smart_chunking=smart_chunking,
            max_chars_per_chunk=max_chars_per_chunk,
            crossfade_ms=crossfade_ms,
        )

        return {
            "job_id": job.job_id,
            "status": job.status.value,
            "total_chunks": job.total_chunks,
            "total_chars": job.total_chars,
            "chapters": len(job.chapters),
            "output_format": output_format,
            "subtitle_format": subtitle_format,
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        # Clean up temp file
        Path(tmp_path).unlink(missing_ok=True)


@app.get("/api/audiobook/status/{job_id}")
async def audiobook_status(job_id: str):
    """Get the status of an audiobook generation job.

    Enhanced with character-based progress tracking (like audiblez):
    - chars_per_sec: Processing speed in characters per second
    - eta_seconds: Estimated time remaining
    - eta_formatted: Human-readable ETA (e.g., "5m 30s")
    """
    from tts.audiobook import get_job, JobStatus, format_eta

    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")

    result = {
        "job_id": job.job_id,
        "status": job.status.value,
        "current_chunk": job.current_chunk,
        "total_chunks": job.total_chunks,
        "percent": job.percent,
        "elapsed_seconds": round(job.elapsed_seconds, 1),
        "output_format": job.output_format,
        # Enhanced progress tracking (like audiblez)
        "total_chars": job.total_chars,
        "processed_chars": job.processed_chars,
        "chars_per_sec": round(job.chars_per_sec, 1),
        "eta_seconds": round(job.eta_seconds, 1),
        "eta_formatted": format_eta(job.eta_seconds),
        # Chapter info
        "current_chapter": job.current_chapter,
        "total_chapters": len(job.chapters),
    }

    if job.status == JobStatus.COMPLETED:
        result["audio_url"] = f"/audio/{job.audio_path.name}"
        result["duration_seconds"] = round(job.duration_seconds, 1)
        result["file_size_mb"] = round(job.file_size_mb, 2)
        result["final_chars_per_sec"] = round(job.chars_per_sec, 1)
        # Include subtitle URL if generated
        if job.subtitle_path:
            result["subtitle_url"] = f"/audio/{job.subtitle_path.name}"
            result["subtitle_format"] = job.subtitle_format

    if job.status == JobStatus.FAILED:
        result["error"] = job.error_message

    return result


@app.post("/api/audiobook/cancel/{job_id}")
async def audiobook_cancel(job_id: str):
    """Cancel an in-progress audiobook generation job."""
    from tts.audiobook import cancel_job, get_job

    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")

    success = cancel_job(job_id)
    if success:
        return {"message": "Cancellation requested", "job_id": job_id}
    else:
        return {"message": "Job cannot be cancelled (already completed or failed)", "job_id": job_id}


@app.get("/api/audiobook/list")
async def audiobook_list():
    """List all generated audiobooks (WAV, MP3, and M4B)."""
    from datetime import datetime

    audiobooks = []
    audiobook_pattern = "audiobook-"

    # Search for WAV, MP3, and M4B files
    for ext in ["wav", "mp3", "m4b"]:
        for file in outputs_dir.glob(f"{audiobook_pattern}*.{ext}"):
            stat = file.stat()
            # Parse job_id from filename: audiobook-{job_id}.wav/.mp3/.m4b
            job_id = file.stem.replace(audiobook_pattern, "")

            # Get audio duration
            duration_seconds = 0
            try:
                if ext == "wav":
                    import soundfile as sf
                    info = sf.info(str(file))
                    duration_seconds = info.duration
                elif ext == "mp3":
                    from pydub import AudioSegment
                    audio = AudioSegment.from_mp3(str(file))
                    duration_seconds = len(audio) / 1000.0
                elif ext == "m4b":
                    # For M4B, try pydub with ffmpeg
                    from pydub import AudioSegment
                    audio = AudioSegment.from_file(str(file), format="m4b")
                    duration_seconds = len(audio) / 1000.0
            except Exception:
                duration_seconds = 0

            audiobooks.append({
                "job_id": job_id,
                "filename": file.name,
                "audio_url": f"/audio/{file.name}",
                "format": ext,
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "duration_seconds": round(duration_seconds, 1),
                "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                "is_audiobook_format": ext == "m4b",
            })

    # Sort by creation time, newest first
    audiobooks.sort(key=lambda x: x["created_at"], reverse=True)

    return {"audiobooks": audiobooks, "total": len(audiobooks)}


@app.delete("/api/audiobook/{job_id}")
async def audiobook_delete(job_id: str):
    """Delete an audiobook file (WAV, MP3, or M4B)."""
    # Check for WAV, MP3, and M4B
    wav_path = outputs_dir / f"audiobook-{job_id}.wav"
    mp3_path = outputs_dir / f"audiobook-{job_id}.mp3"
    m4b_path = outputs_dir / f"audiobook-{job_id}.m4b"

    deleted = False
    for path in [wav_path, mp3_path, m4b_path]:
        if path.exists():
            path.unlink()
            deleted = True

    if not deleted:
        raise HTTPException(status_code=404, detail=f"Audiobook '{job_id}' not found")

    return {"message": "Audiobook deleted", "job_id": job_id}


# ============== Kokoro Audio Library Endpoints ==============

@app.get("/api/tts/audio/list")
async def tts_audio_list():
    """List all generated TTS audio files (Kokoro)."""
    from datetime import datetime

    audio_files = []
    patterns = [
        ("kokoro", "kokoro-*.wav"),
    ]

    for engine, pattern in patterns:
        for file in outputs_dir.glob(pattern):
            stat = file.stat()
            stem = file.stem
            parts = stem.split("-")

            label = engine
            voice = None

            if engine == "kokoro":
                voice = parts[1] if len(parts) > 2 else "unknown"
                label = BRITISH_VOICES.get(voice, {}).get("name", voice)
            # kokoro handled above

            try:
                info = sf.info(str(file))
                duration_seconds = info.duration
            except Exception:
                duration_seconds = 0

            audio_files.append({
                "id": stem,
                "filename": file.name,
                "engine": engine,
                "label": label,
                "voice": voice,
                "audio_url": f"/audio/{file.name}",
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "duration_seconds": round(duration_seconds, 1),
                "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
            })

    audio_files.sort(key=lambda x: x["created_at"], reverse=True)
    return {"audio_files": audio_files, "total": len(audio_files)}


@app.delete("/api/tts/audio/{filename}")
async def tts_audio_delete(filename: str):
    """Delete a TTS audio file (Kokoro)."""
    if not (filename.endswith(".wav") and filename.startswith("kokoro-")):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = outputs_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Audio file '{filename}' not found")

    file_path.unlink()
    return {"message": "Audio file deleted", "filename": filename}


@app.get("/api/kokoro/audio/list")
async def kokoro_audio_list():
    """List all generated Kokoro TTS audio files."""
    from datetime import datetime

    audio_files = []
    kokoro_pattern = "kokoro-"

    for file in outputs_dir.glob(f"{kokoro_pattern}*.wav"):
        stat = file.stat()
        # Parse voice from filename: kokoro-{voice}-{uuid}.wav
        parts = file.stem.split("-")
        voice = parts[1] if len(parts) > 1 else "unknown"
        file_id = parts[-1] if len(parts) > 2 else file.stem

        # Get audio duration using soundfile
        try:
            import soundfile as sf
            info = sf.info(str(file))
            duration_seconds = info.duration
        except Exception:
            duration_seconds = 0

        audio_files.append({
            "id": file_id,
            "filename": file.name,
            "voice": voice,
            "audio_url": f"/audio/{file.name}",
            "size_mb": round(stat.st_size / (1024 * 1024), 2),
            "duration_seconds": round(duration_seconds, 1),
            "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
        })

    # Sort by creation time, newest first
    audio_files.sort(key=lambda x: x["created_at"], reverse=True)

    return {"audio_files": audio_files, "total": len(audio_files)}


@app.delete("/api/kokoro/audio/{filename}")
async def kokoro_audio_delete(filename: str):
    """Delete a Kokoro audio file."""
    # Security: ensure filename starts with kokoro- and ends with .wav
    if not filename.startswith("kokoro-") or not filename.endswith(".wav"):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = outputs_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Audio file '{filename}' not found")

    file_path.unlink()
    return {"message": "Audio file deleted", "filename": filename}


# ============== Voice Clone Audio Library Endpoints ==============

@app.get("/api/voice-clone/audio/list")
async def voice_clone_audio_list():
    """List all generated voice clone audio files."""
    from datetime import datetime

    audio_files = []
    patterns = [
        ("qwen3", "qwen3-*.wav"),
        ("chatterbox", "chatterbox-*.wav"),
        ("indextts2", "indextts2-*.wav"),
    ]

    for engine, pattern in patterns:
        for file in outputs_dir.glob(pattern):
            stat = file.stat()
            stem = file.stem
            parts = stem.split("-")

            mode = "clone"
            voice = parts[1] if len(parts) > 2 else None

            if engine == "qwen3":
                label = f"Qwen3 {voice}" if voice else "Qwen3 Clone"
            elif engine == "indextts2":
                label = f"IndexTTS-2 {voice}" if voice else "IndexTTS-2 Clone"
            else:
                label = f"Chatterbox {voice}" if voice else "Chatterbox Clone"

            # Get audio duration using soundfile
            try:
                import soundfile as sf
                info = sf.info(str(file))
                duration_seconds = info.duration
            except Exception:
                duration_seconds = 0

            audio_files.append({
                "id": stem,
                "filename": file.name,
                "engine": engine,
                "voice": voice,
                "mode": mode,
                "label": label,
                "audio_url": f"/audio/{file.name}",
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "duration_seconds": round(duration_seconds, 1),
                "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
            })

    # Sort by creation time, newest first
    audio_files.sort(key=lambda x: x["created_at"], reverse=True)

    return {"audio_files": audio_files, "total": len(audio_files)}


@app.delete("/api/voice-clone/audio/{filename}")
async def voice_clone_audio_delete(filename: str):
    """Delete a voice clone audio file."""
    # Security: ensure filename starts with allowed prefixes and ends with .wav
    valid_prefixes = ("qwen3-", "chatterbox-", "indextts2-")
    if not (filename.endswith(".wav") and filename.startswith(valid_prefixes)):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = outputs_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Audio file '{filename}' not found")

    file_path.unlink()
    return {"message": "Audio file deleted", "filename": filename}


# ============== Sample Texts Endpoints ==============

@app.get("/api/samples/{engine}")
async def get_sample_texts(engine: str):
    """Get sample texts for a specific TTS engine."""
    valid_engines = ["kokoro"]
    if engine not in valid_engines:
        raise HTTPException(status_code=400, detail=f"Invalid engine. Use one of: {valid_engines}")

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT id, text, language, category FROM sample_texts WHERE engine = ?",
        (engine,)
    )
    rows = cursor.fetchall()
    conn.close()

    return {
        "engine": engine,
        "samples": [
            {"id": row[0], "text": row[1], "language": row[2], "category": row[3]}
            for row in rows
        ]
    }

# ============== Pregenerated Samples Endpoints ==============

@app.get("/api/pregenerated")
async def list_pregenerated_samples(engine: Optional[str] = None):
    """List pregenerated audio samples for instant playback."""
    conn = get_connection()
    cursor = conn.cursor()

    if engine:
        cursor.execute(
            "SELECT id, engine, voice, title, description, text, file_path FROM pregenerated_samples WHERE engine = ?",
            (engine,)
        )
    else:
        cursor.execute(
            "SELECT id, engine, voice, title, description, text, file_path FROM pregenerated_samples"
        )

    rows = cursor.fetchall()
    conn.close()

    samples = []
    for row in rows:
        file_path = Path(row[6])
        if file_path.exists():
            samples.append({
                "id": row[0],
                "engine": row[1],
                "voice": row[2],
                "title": row[3],
                "description": row[4],
                "text": row[5],
                "audio_url": f"/pregenerated/{file_path.name}"
            })

    return {"samples": samples}

# Mount pregenerated directory for serving audio files
pregen_dir = Path(__file__).parent / "data" / "pregenerated"
pregen_dir.mkdir(parents=True, exist_ok=True)
app.mount("/pregenerated", StaticFiles(directory=str(pregen_dir)), name="pregenerated")

# Mount samples directory for pre-recorded voice samples
samples_dir = Path(__file__).parent / "data" / "samples"
samples_dir.mkdir(parents=True, exist_ok=True)
app.mount("/samples", StaticFiles(directory=str(samples_dir)), name="samples")

# Mount PDF directory for serving documents
pdf_dir = Path(__file__).parent / "data" / "pdf"
pdf_dir.mkdir(parents=True, exist_ok=True)
app.mount("/pdf", StaticFiles(directory=str(pdf_dir)), name="pdf")


@app.get("/api/pdf/list")
async def list_pdfs():
    """List available PDF/TXT/MD documents in the documents directory."""
    docs = []
    for ext in ("*.pdf", "*.txt", "*.md"):
        for f in pdf_dir.glob(ext):
            docs.append({
                "name": f.name,
                "url": f"/pdf/{f.name}",
                "size_bytes": f.stat().st_size,
            })
    docs.sort(key=lambda d: d["name"])
    return {"documents": docs}


@app.post("/api/pdf/extract-text")
async def extract_pdf_text(file: UploadFile = File(...)):
    """Extract normalized text from an uploaded PDF for read-aloud."""
    filename = (file.filename or "").lower()
    if filename and not filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported")

    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=400, detail="Uploaded PDF is empty")

    temp_path: Optional[str] = None
    try:
        from tts.audiobook import extract_pdf_with_toc

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as temp_file:
            temp_file.write(payload)
            temp_path = temp_file.name

        text, _chapters = extract_pdf_with_toc(temp_path)
        normalized = _normalize_pdf_text_for_tts(text)
        return {
            "text": normalized,
            "chars": len(normalized),
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to extract PDF text: {exc}",
        ) from exc
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except OSError:
                pass

# ============== Voice Sample Sentences Endpoints ==============

@app.get("/api/voice-samples")
async def list_voice_samples():
    """List pre-generated voice sample sentences."""
    kokoro_samples_dir = Path(__file__).parent / "data" / "samples" / "kokoro"
    samples = []

    sentences = [
        ("This is not all that can be said, however. In so far as a specifically moral anthropology has to deal with the conditions that hinder or further the execution of the moral laws in human nature.", "bf_emma", "Emma"),
        ("Anthropology must be concerned with the sociological and even historical developments which are relevant to morality. In so far as pragmatic anthropology also deals with these questions, it is also relevant here.", "bm_george", "George"),
        ("The spread and strengthening of moral principles through the education in schools and in public, and also with the personal and public contexts of morality that are open to empirical observation.", "bf_lily", "Lily"),
    ]

    for i, (text, voice_code, voice_name) in enumerate(sentences):
        file_path = kokoro_samples_dir / f"sentence-{i+1:02d}-{voice_code}.wav"
        if file_path.exists():
            samples.append({
                "id": i + 1,
                "text": text,
                "voice_code": voice_code,
                "voice_name": voice_name,
                "audio_url": f"/samples/kokoro/sentence-{i+1:02d}-{voice_code}.wav"
            })

    return {"samples": samples, "total": len(samples)}

# ============== Settings ==============

@app.get("/api/settings")
async def api_get_settings():
    """Get all application settings."""
    return get_all_settings()

@app.get("/api/settings/output-folder")
async def api_get_output_folder():
    """Get the output folder path."""
    path = get_output_folder()
    active_path = str(_sync_output_folder_runtime(path))
    return {"path": active_path}

@app.put("/api/settings/output-folder")
async def api_set_output_folder(path: str):
    """Set the output folder path."""
    success = set_output_folder(path)
    active_path = str(_sync_output_folder_runtime(path))
    return {"success": success, "path": active_path}

@app.get("/api/settings/{key}")
async def api_get_setting(key: str):
    """Get a specific setting."""
    value = get_setting(key)
    if value is None:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return {"key": key, "value": value}

@app.put("/api/settings")
async def api_update_setting(request: SettingsUpdateRequest):
    """Update a setting."""
    set_setting(request.key, request.value)
    return {"key": request.key, "value": request.value}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
