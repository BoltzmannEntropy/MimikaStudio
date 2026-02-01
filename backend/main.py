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
import tempfile
import uuid
import soundfile as sf

from database import init_db, seed_db, get_connection
from tts.kokoro_engine import get_kokoro_engine, BRITISH_VOICES, DEFAULT_VOICE
from tts.qwen3_engine import get_qwen3_engine, GenerationParams, QWEN_SPEAKERS, unload_all_engines
from tts.chatterbox_engine import get_chatterbox_engine, ChatterboxParams
from tts.text_chunking import smart_chunk_text
from tts.audio_utils import merge_audio_chunks, resample_audio
from models.registry import ModelRegistry
from language.ipa_generator import generate_ipa_transcription, get_sample_text as get_ipa_sample_text
from llm.factory import load_config as load_llm_config, save_config as save_llm_config, get_available_providers

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
    instruct: Optional[str] = None  # Style instruction for custom mode
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

class LLMConfigRequest(BaseModel):
    provider: str
    model: str
    api_key: Optional[str] = None
    api_base: Optional[str] = None

class IPAGenerateRequest(BaseModel):
    text: str
    provider: Optional[str] = None
    model: Optional[str] = None


# Lifespan context manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Initializing database...")
    init_db()
    seed_db()
    _migrate_legacy_voice_samples()
    print("Database ready.")
    yield
    # Shutdown
    print("Shutting down...")

app = FastAPI(
    title="MimikaStudio API",
    description="Local-first Voice Cloning with Qwen3-TTS and Kokoro",
    version="1.0.0",
    lifespan=lifespan
)

# CORS for Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount outputs directory for serving audio files
outputs_dir = Path(__file__).parent / "outputs"
outputs_dir.mkdir(parents=True, exist_ok=True)
app.mount("/audio", StaticFiles(directory=str(outputs_dir)), name="audio")

# Qwen3 voice storage locations
QWEN3_SAMPLE_VOICES_DIR = Path(__file__).parent / "data" / "samples" / "qwen3_voices"
QWEN3_USER_VOICES_DIR = Path(__file__).parent / "data" / "user_voices" / "qwen3"
DEFAULT_QWEN3_VOICES = {"Natasha", "Suzan"}

# Chatterbox voice storage locations
CHATTERBOX_SAMPLE_VOICES_DIR = Path(__file__).parent / "data" / "samples" / "chatterbox_voices"
CHATTERBOX_USER_VOICES_DIR = Path(__file__).parent / "data" / "user_voices" / "chatterbox"
DEFAULT_CHATTERBOX_VOICES = {"Natasha", "Suzan"}


def _migrate_legacy_voice_samples() -> None:
    """Move legacy or user voices into the non-synced user voices folder."""
    legacy_dir = Path(__file__).parent / "data" / "samples" / "voices"
    QWEN3_SAMPLE_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    QWEN3_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    CHATTERBOX_SAMPLE_VOICES_DIR.mkdir(parents=True, exist_ok=True)
    CHATTERBOX_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

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

    # Migrate any legacy voices
    if legacy_dir.exists():
        for wav_file in legacy_dir.glob("*.wav"):
            name = wav_file.stem
            if name in DEFAULT_QWEN3_VOICES:
                dest_wav = QWEN3_SAMPLE_VOICES_DIR / wav_file.name
                if not dest_wav.exists():
                    shutil.copy2(wav_file, dest_wav)
                src_txt = wav_file.with_suffix(".txt")
                dest_txt = QWEN3_SAMPLE_VOICES_DIR / src_txt.name
                if src_txt.exists() and not dest_txt.exists():
                    shutil.copy2(src_txt, dest_txt)
            else:
                move_voice(legacy_dir, name, QWEN3_USER_VOICES_DIR)

    # Ensure only default voices remain in the sample folder
    for wav_file in QWEN3_SAMPLE_VOICES_DIR.glob("*.wav"):
        if wav_file.stem not in DEFAULT_QWEN3_VOICES:
            move_voice(QWEN3_SAMPLE_VOICES_DIR, wav_file.stem, QWEN3_USER_VOICES_DIR)

    # Seed Chatterbox defaults from Qwen3 samples if missing
    for name in DEFAULT_CHATTERBOX_VOICES:
        src_wav = QWEN3_SAMPLE_VOICES_DIR / f"{name}.wav"
        dest_wav = CHATTERBOX_SAMPLE_VOICES_DIR / f"{name}.wav"
        if src_wav.exists() and not dest_wav.exists():
            shutil.copy2(src_wav, dest_wav)
        src_txt = QWEN3_SAMPLE_VOICES_DIR / f"{name}.txt"
        dest_txt = CHATTERBOX_SAMPLE_VOICES_DIR / f"{name}.txt"
        if src_txt.exists() and not dest_txt.exists():
            shutil.copy2(src_txt, dest_txt)

    # Ensure only default voices remain in the chatterbox sample folder
    for wav_file in CHATTERBOX_SAMPLE_VOICES_DIR.glob("*.wav"):
        if wav_file.stem not in DEFAULT_CHATTERBOX_VOICES:
            move_voice(
                CHATTERBOX_SAMPLE_VOICES_DIR,
                wav_file.stem,
                CHATTERBOX_USER_VOICES_DIR,
            )


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
    import torch

    # Detect compute device
    if torch.backends.mps.is_available():
        device = "MPS (Apple Silicon)"
    elif torch.cuda.is_available():
        device = f"CUDA ({torch.cuda.get_device_name(0)})"
    else:
        device = "CPU"

    # Get model versions from each engine
    kokoro_info = {"model": "Kokoro v0.19", "voice_pack": "British English"}
    qwen3_info = {"model": "Qwen3-TTS-12Hz-0.6B-Base", "features": "3-sec voice clone"}
    chatterbox_info = {"model": "Chatterbox Multilingual TTS", "features": "voice clone"}

    return {
        "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "os": f"{platform.system()} {platform.release()}",
        "arch": platform.machine(),
        "device": device,
        "torch_version": torch.__version__,
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
    import torch

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

    # GPU memory (if available)
    if torch.cuda.is_available():
        gpu_mem_used = torch.cuda.memory_allocated() / (1024 ** 3)
        gpu_mem_total = torch.cuda.get_device_properties(0).total_memory / (1024 ** 3)
        result["gpu"] = {
            "name": torch.cuda.get_device_name(0),
            "memory_used_gb": round(gpu_mem_used, 1),
            "memory_total_gb": round(gpu_mem_total, 1),
            "memory_percent": round(gpu_mem_used / gpu_mem_total * 100, 1) if gpu_mem_total > 0 else 0,
        }
    elif torch.backends.mps.is_available():
        # MPS doesn't have detailed memory API, but we can show it's active
        result["gpu"] = {
            "name": "Apple Silicon (MPS)",
            "memory_used_gb": None,
            "memory_total_gb": None,
            "memory_percent": None,
            "note": "MPS active - memory shared with system RAM",
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

    voices = []

    # Get Qwen3 voices
    try:
        engine = get_qwen3_engine()
        qwen3_voices = engine.get_saved_voices()
        for voice in qwen3_voices:
            # Avoid duplicates by checking name
            if not any(v["name"] == voice["name"] and v["source"] == "qwen3" for v in voices):
                audio_path = Path(voice.get("audio_path", ""))
                audio_url = _audio_url_from_path(audio_path) if audio_path and audio_path.exists() else None
                voices.append({
                    "name": voice["name"],
                    "source": "qwen3",
                    "transcript": voice.get("transcript"),
                    "has_audio": True,
                    "audio_url": audio_url,
                })
    except ImportError:
        pass  # Qwen3 not installed

    # Get Chatterbox voices
    try:
        engine = get_chatterbox_engine()
        chatterbox_voices = engine.get_saved_voices()
        for voice in chatterbox_voices:
            if not any(v["name"] == voice["name"] and v["source"] == "chatterbox" for v in voices):
                audio_path = Path(voice.get("audio_path", ""))
                audio_url = _audio_url_from_path(audio_path) if audio_path and audio_path.exists() else None
                voices.append({
                    "name": voice["name"],
                    "source": "chatterbox",
                    "transcript": voice.get("transcript"),
                    "has_audio": True,
                    "audio_url": audio_url,
                })
    except ImportError:
        pass  # Chatterbox not installed

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
            detail=f"Kokoro not installed. Run: pip install kokoro. Error: {e}",
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
                mode="clone"
            )
            voices = engine.get_saved_voices()

            # Find the voice
            voice = next((v for v in voices if v["name"] == request.voice_name), None)
            if voice is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Voice '{request.voice_name}' not found. Upload a voice first."
                )

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
                mode="custom"
            )

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
            detail=f"Qwen3-TTS not installed. Run: pip install -U qwen-tts soundfile. Error: {e}"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/qwen3/generate/stream")
async def qwen3_generate_stream(request: Qwen3Request):
    """Generate speech with streaming response.

    Returns audio as a streaming response for real-time playback.
    """
    from fastapi.responses import StreamingResponse

    # First generate the audio
    result = await qwen3_generate(request)
    filename = result["filename"]
    output_path = outputs_dir / filename

    def iterator():
        with output_path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 256)  # 256KB chunks
                if not chunk:
                    break
                yield chunk

    return StreamingResponse(iterator(), media_type="audio/wav")


@app.get("/api/qwen3/voices")
async def qwen3_list_voices():
    """List saved voice samples for Qwen3 cloning."""
    try:
        engine = get_qwen3_engine()
        voices = engine.get_saved_voices()
        for voice in voices:
            name = voice.get("name")
            if name:
                voice["audio_url"] = f"/api/qwen3/voices/{name}/audio"
        return {"voices": voices}
    except ImportError:
        return {"voices": [], "error": "Qwen3-TTS not installed"}


@app.get("/api/qwen3/voices/{name}/audio")
async def qwen3_voice_audio(name: str):
    """Serve a voice sample audio file for preview."""
    if not re.match(r"^[A-Za-z0-9_-]+$", name):
        raise HTTPException(status_code=400, detail="Invalid voice name")

    for vdir in [QWEN3_USER_VOICES_DIR, QWEN3_SAMPLE_VOICES_DIR]:
        audio_file = vdir / f"{name}.wav"
        if audio_file.exists():
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
    if name in DEFAULT_QWEN3_VOICES:
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
    if (QWEN3_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
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
    if (QWEN3_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
        raise HTTPException(status_code=400, detail="Default voices cannot be modified")

    old_audio = QWEN3_USER_VOICES_DIR / f"{name}.wav"
    old_transcript = QWEN3_USER_VOICES_DIR / f"{name}.txt"
    if not old_audio.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    final_name = new_name or name
    if final_name in DEFAULT_QWEN3_VOICES:
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
            "error": "Run: pip install -U qwen-tts soundfile",
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
        voices = engine.get_saved_voices()
        voice = next((v for v in voices if v["name"] == request.voice_name), None)
        if voice is None:
            raise HTTPException(
                status_code=404,
                detail=f"Voice '{request.voice_name}' not found. Upload a voice first.",
            )

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
            detail=f"Chatterbox not installed. Run: pip install chatterbox-tts. Error: {e}",
        )


@app.get("/api/chatterbox/voices")
async def chatterbox_list_voices():
    """List saved voice samples for Chatterbox cloning."""
    try:
        engine = get_chatterbox_engine()
        voices = engine.get_saved_voices()
        for voice in voices:
            name = voice.get("name")
            if name:
                voice["audio_url"] = f"/api/chatterbox/voices/{name}/audio"
        return {"voices": voices}
    except ImportError:
        return {"voices": [], "error": "Chatterbox not installed"}


@app.get("/api/chatterbox/voices/{name}/audio")
async def chatterbox_voice_audio(name: str):
    """Serve a Chatterbox voice sample audio file for preview."""
    if not name or "/" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid voice name")

    for directory in (CHATTERBOX_USER_VOICES_DIR, CHATTERBOX_SAMPLE_VOICES_DIR):
        audio_path = directory / f"{name}.wav"
        if audio_path.exists():
            return FileResponse(audio_path)

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

    if name in DEFAULT_CHATTERBOX_VOICES:
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
    if (CHATTERBOX_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
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
    if (CHATTERBOX_SAMPLE_VOICES_DIR / f"{name}.wav").exists():
        raise HTTPException(status_code=400, detail="Default voices cannot be modified")

    old_audio = CHATTERBOX_USER_VOICES_DIR / f"{name}.wav"
    old_transcript = CHATTERBOX_USER_VOICES_DIR / f"{name}.txt"
    if not old_audio.exists():
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    final_name = new_name or name
    if final_name in DEFAULT_CHATTERBOX_VOICES:
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
        return {"languages": engine.get_languages()}
    except ImportError:
        return {"languages": ["en"]}


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
            "error": "Run: pip install chatterbox-tts",
        }


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
    valid_prefixes = ("qwen3-", "chatterbox-")
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

# ============== LLM Configuration Endpoints ==============

@app.get("/api/llm/config")
async def get_llm_config():
    """Get current LLM configuration."""
    config = load_llm_config()
    # Mask API key for security
    if config.get("api_key"):
        config["api_key"] = "***" + config["api_key"][-4:] if len(config["api_key"]) > 4 else "****"
    config["available_providers"] = get_available_providers()
    return config

@app.get("/api/llm/ollama/models")
async def get_ollama_models():
    """Get list of locally available Ollama models."""
    import httpx
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get("http://localhost:11434/api/tags")
            if response.status_code == 200:
                data = response.json()
                models = [m["name"] for m in data.get("models", [])]
                return {"models": models, "available": True}
            return {"models": [], "available": False, "error": "Ollama not responding"}
    except Exception as e:
        return {"models": [], "available": False, "error": str(e)}

@app.post("/api/llm/config")
async def update_llm_config(request: LLMConfigRequest):
    """Update LLM configuration."""
    config = {
        "provider": request.provider,
        "model": request.model,
    }
    # Only update API key if a new one is provided (not masked)
    if request.api_key and not request.api_key.startswith("***"):
        config["api_key"] = request.api_key
    else:
        # Keep existing key
        old_config = load_llm_config()
        if old_config.get("api_key"):
            config["api_key"] = old_config["api_key"]

    if request.api_base:
        config["api_base"] = request.api_base

    save_llm_config(config)
    return {"message": "Configuration saved", "provider": request.provider, "model": request.model}

# ============== Emma IPA Endpoints ==============

@app.get("/api/ipa/sample")
async def get_ipa_sample():
    """Get the default sample text for IPA generation."""
    return {"text": get_ipa_sample_text()}

@app.get("/api/ipa/samples")
async def get_ipa_samples():
    """Get all saved Emma IPA sample texts with preloaded IPA transcriptions."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, title, input_text, audio_file, is_default, version1_ipa, version2_ipa
        FROM emma_ipa_samples
        ORDER BY is_default DESC, id ASC
    """)
    rows = cursor.fetchall()
    conn.close()

    samples = []
    for row in rows:
        audio_file = row[3]
        has_audio = audio_file and Path(audio_file).exists()
        samples.append({
            "id": row[0],
            "title": row[1],
            "input_text": row[2],
            "audio_url": f"/pregenerated/{Path(audio_file).name}" if has_audio else None,
            "has_audio": has_audio,
            "is_default": bool(row[4]),
            "version1_ipa": row[5],
            "version2_ipa": row[6],
            "has_preloaded_ipa": bool(row[5] and row[6])
        })

    return {"samples": samples}

@app.post("/api/ipa/generate")
async def generate_ipa(request: IPAGenerateRequest):
    """Generate IPA-like British transcription for the given text."""
    try:
        result = generate_ipa_transcription(
            request.text,
            provider_name=request.provider,
            model=request.model
        )
        return {
            "ipa": result.get("ipa", ""),
            "version1": result.get("version1", ""),  # Backward compatibility
            "original_text": request.text
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/ipa/pregenerated")
async def get_ipa_pregenerated():
    """Get pregenerated IPA sample with audio."""
    ipa_audio_path = Path(__file__).parent / "data" / "pregenerated" / "emma-ipa-lily-sample.wav"
    sample_text = get_ipa_sample_text()

    result = {
        "text": sample_text,
        "has_audio": ipa_audio_path.exists(),
        "audio_url": "/pregenerated/emma-ipa-lily-sample.wav" if ipa_audio_path.exists() else None
    }
    return result

@app.post("/api/ipa/save-output")
async def save_ipa_output(
    input_text: str,
    version1_ipa: str,
    version2_ipa: str,
    llm_provider: str,
    sample_id: Optional[int] = None
):
    """Save a generated IPA output to history."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO emma_ipa_outputs
           (sample_id, input_text, version1_ipa, version2_ipa, llm_provider)
           VALUES (?, ?, ?, ?, ?)""",
        (sample_id, input_text, version1_ipa, version2_ipa, llm_provider)
    )
    conn.commit()
    output_id = cursor.lastrowid
    conn.close()

    return {"id": output_id, "message": "Output saved successfully"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
