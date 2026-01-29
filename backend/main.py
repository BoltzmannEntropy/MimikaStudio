from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional
import json
import os
import shutil
import subprocess

from database import init_db, seed_db, get_connection
from tts.xtts_engine import get_xtts_engine
from tts.kokoro_engine import get_kokoro_engine, BRITISH_VOICES, DEFAULT_VOICE
from tts.qwen3_engine import get_qwen3_engine, GenerationParams, QWEN_SPEAKERS, unload_all_engines
from models.registry import ModelRegistry
from language.ipa_generator import generate_ipa_transcription, get_sample_text as get_ipa_sample_text
from llm.factory import load_config as load_llm_config, save_config as save_llm_config, get_available_providers

# Request models
class XTTSRequest(BaseModel):
    text: str
    speaker_id: str
    language: str = "English"
    speed: float = 0.8

class KokoroRequest(BaseModel):
    text: str
    voice: str = DEFAULT_VOICE
    speed: float = 1.0

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
    print("Database ready.")
    yield
    # Shutdown
    print("Shutting down...")

app = FastAPI(
    title="MimikaStudio API",
    description="Local-first Voice Cloning with Qwen3-TTS, Kokoro, and XTTS",
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

# XTTS subprocess config (isolated env to avoid transformer conflicts)
XTTS_PYTHON = Path(__file__).parent / "venv_xtts" / "bin" / "python"
XTTS_SCRIPT = Path(__file__).parent / "scripts" / "xtts_generate.py"


def _run_xtts_subprocess(text: str, speaker_wav_path: str, language: str, speed: float) -> Optional[Path]:
    if not XTTS_PYTHON.exists() or not XTTS_SCRIPT.exists():
        return None

    payload = {
        "text": text,
        "speaker_wav_path": speaker_wav_path,
        "language": language,
        "speed": speed,
    }
    proc = subprocess.run(
        [str(XTTS_PYTHON), str(XTTS_SCRIPT)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or "XTTS subprocess failed"
        raise HTTPException(status_code=500, detail=detail)

    try:
        data = json.loads(proc.stdout.strip())
        output_path = data.get("output_path")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"XTTS subprocess parse error: {exc}")

    if not output_path:
        raise HTTPException(status_code=500, detail="XTTS subprocess did not return output path")

    return Path(output_path)

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
    xtts_info = {"model": "XTTS v2.0", "framework": "Coqui TTS"}
    qwen3_info = {"model": "Qwen3-TTS-12Hz-0.6B-Base", "features": "3-sec voice clone"}

    return {
        "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "os": f"{platform.system()} {platform.release()}",
        "arch": platform.machine(),
        "device": device,
        "torch_version": torch.__version__,
        "models": {
            "kokoro": kokoro_info,
            "xtts": xtts_info,
            "qwen3": qwen3_info,
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
    """List all custom voice samples from both XTTS and Qwen3 for unified voice cloning."""
    voices = []

    # Get XTTS voices from database
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT name, file_path FROM xtts_voices")
    xtts_rows = cursor.fetchall()
    conn.close()

    for row in xtts_rows:
        name, file_path = row
        voices.append({
            "name": name,
            "source": "xtts",
            "transcript": None,
            "has_audio": file_path and Path(file_path).exists(),
        })

    # Get Qwen3 voices
    try:
        engine = get_qwen3_engine()
        qwen3_voices = engine.get_saved_voices()
        for voice in qwen3_voices:
            # Avoid duplicates by checking name
            if not any(v["name"] == voice["name"] and v["source"] == "qwen3" for v in voices):
                voices.append({
                    "name": voice["name"],
                    "source": "qwen3",
                    "transcript": voice.get("transcript"),
                    "has_audio": True,
                })
    except ImportError:
        pass  # Qwen3 not installed

    return {"voices": voices, "total": len(voices)}


# ============== XTTS Endpoints ==============

@app.post("/api/xtts/generate")
async def xtts_generate(request: XTTSRequest):
    """Generate speech using XTTS voice cloning."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT file_path FROM xtts_voices WHERE name = ?", (request.speaker_id,))
    row = cursor.fetchone()
    conn.close()

    if row is None:
        raise HTTPException(status_code=404, detail=f"Voice '{request.speaker_id}' not found")

    speaker_path = row[0]
    if not Path(speaker_path).exists():
        raise HTTPException(status_code=404, detail=f"Voice file not found: {speaker_path}")

    output_path = None
    use_subprocess = os.environ.get("XTTS_USE_SUBPROCESS", "1") != "0"
    if use_subprocess:
        output_path = _run_xtts_subprocess(
            text=request.text,
            speaker_wav_path=speaker_path,
            language=request.language,
            speed=request.speed,
        )

    if output_path is None:
        engine = get_xtts_engine()
        output_path = engine.generate(
            text=request.text,
            speaker_wav_path=speaker_path,
            language=request.language,
            speed=request.speed
        )

    return {
        "audio_url": f"/audio/{output_path.name}",
        "filename": output_path.name
    }

@app.get("/api/xtts/voices")
async def xtts_list_voices():
    """List available XTTS voices for cloning."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, file_path FROM xtts_voices")
    rows = cursor.fetchall()
    conn.close()

    return [
        {"id": row[0], "name": row[1], "file_path": row[2]}
        for row in rows
    ]

@app.post("/api/xtts/voices")
async def xtts_upload_voice(
    file: UploadFile = File(...),
    name: str = Form(...)
):
    """Upload a new voice sample for XTTS cloning."""
    voices_dir = Path(__file__).parent / "data" / "samples" / "voices"
    voices_dir.mkdir(parents=True, exist_ok=True)

    file_path = voices_dir / f"{name}.wav"
    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT OR REPLACE INTO xtts_voices (name, file_path) VALUES (?, ?)",
        (name, str(file_path))
    )
    conn.commit()
    conn.close()

    return {"message": f"Voice '{name}' uploaded successfully", "name": name}

@app.delete("/api/xtts/voices/{name}")
async def xtts_delete_voice(name: str):
    """Delete an XTTS voice sample."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT file_path FROM xtts_voices WHERE name = ?", (name,))
    row = cursor.fetchone()

    if row is None:
        conn.close()
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    file_path = Path(row[0])
    if file_path.exists():
        file_path.unlink()

    cursor.execute("DELETE FROM xtts_voices WHERE name = ?", (name,))
    conn.commit()
    conn.close()

    return {"message": f"Voice '{name}' deleted successfully"}


@app.put("/api/xtts/voices/{name}")
async def xtts_update_voice(
    name: str,
    new_name: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    """Update an XTTS voice sample (rename or replace audio)."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT file_path FROM xtts_voices WHERE name = ?", (name,))
    row = cursor.fetchone()

    if row is None:
        conn.close()
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    old_file_path = Path(row[0])
    voices_dir = Path(__file__).parent / "data" / "samples" / "voices"

    # Update audio file if provided
    if file:
        if old_file_path.exists():
            old_file_path.unlink()
        new_file_path = voices_dir / f"{new_name or name}.wav"
        with open(new_file_path, "wb") as f:
            shutil.copyfileobj(file.file, f)
    else:
        new_file_path = old_file_path
        if new_name and new_name != name:
            # Rename file
            renamed_path = voices_dir / f"{new_name}.wav"
            old_file_path.rename(renamed_path)
            new_file_path = renamed_path

    # Update database
    final_name = new_name or name
    cursor.execute("DELETE FROM xtts_voices WHERE name = ?", (name,))
    cursor.execute(
        "INSERT INTO xtts_voices (name, file_path) VALUES (?, ?)",
        (final_name, str(new_file_path))
    )
    conn.commit()
    conn.close()

    return {"message": f"Voice updated successfully", "name": final_name}


@app.get("/api/xtts/languages")
async def xtts_list_languages():
    """List available languages for XTTS."""
    engine = get_xtts_engine()
    return {"languages": engine.get_languages()}

# ============== Kokoro Endpoints ==============

@app.post("/api/kokoro/generate")
async def kokoro_generate(request: KokoroRequest):
    """Generate speech using Kokoro with predefined British voice."""
    engine = get_kokoro_engine()
    output_path = engine.generate(
        text=request.text,
        voice=request.voice,
        speed=request.speed
    )

    return {
        "audio_url": f"/audio/{output_path.name}",
        "filename": output_path.name
    }

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
        voices = engine.get_saved_voices(include_xtts=True)
        return {"voices": voices}
    except ImportError:
        return {"voices": [], "error": "Qwen3-TTS not installed"}


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
    voices_dir = Path(__file__).parent / "data" / "samples" / "voices"
    qwen3_voices_dir = Path(__file__).parent / "data" / "samples" / "qwen3_voices"

    # Check both directories
    for vdir in [qwen3_voices_dir, voices_dir]:
        audio_file = vdir / f"{name}.wav"
        transcript_file = vdir / f"{name}.txt"

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
    voices_dir = Path(__file__).parent / "data" / "samples" / "voices"
    qwen3_voices_dir = Path(__file__).parent / "data" / "samples" / "qwen3_voices"

    # Find the voice
    found_dir = None
    for vdir in [qwen3_voices_dir, voices_dir]:
        if (vdir / f"{name}.wav").exists():
            found_dir = vdir
            break

    if found_dir is None:
        raise HTTPException(status_code=404, detail=f"Voice '{name}' not found")

    old_audio = found_dir / f"{name}.wav"
    old_transcript = found_dir / f"{name}.txt"
    final_name = new_name or name

    # If renaming or updating audio, move to qwen3_voices dir
    target_dir = qwen3_voices_dir
    target_dir.mkdir(parents=True, exist_ok=True)

    new_audio = target_dir / f"{final_name}.wav"
    new_transcript = target_dir / f"{final_name}.txt"

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


# ============== Audiobook Generation Endpoints ==============

class AudiobookRequest(BaseModel):
    text: str
    title: str = "Untitled"
    voice: str = "bf_emma"
    speed: float = 1.0
    output_format: str = "wav"  # "wav" or "mp3"


@app.post("/api/audiobook/generate")
async def audiobook_generate(request: AudiobookRequest):
    """Start audiobook generation from text.

    Returns a job_id that can be used to poll for status.
    The generation runs in the background.

    Args:
        text: Document text to convert
        title: Audiobook title
        voice: Kokoro voice ID (default: bf_emma)
        speed: Playback speed (default: 1.0)
        output_format: "wav" or "mp3" (default: wav)
    """
    from tts.audiobook import create_audiobook_job

    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    # Validate output format
    output_format = request.output_format.lower()
    if output_format not in ("wav", "mp3"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid output_format: {request.output_format}. Use 'wav' or 'mp3'"
        )

    job = create_audiobook_job(
        text=request.text,
        title=request.title,
        voice=request.voice,
        speed=request.speed,
        output_format=output_format,
    )

    return {
        "job_id": job.job_id,
        "status": job.status.value,
        "total_chunks": job.total_chunks,
        "output_format": output_format,
    }


@app.get("/api/audiobook/status/{job_id}")
async def audiobook_status(job_id: str):
    """Get the status of an audiobook generation job."""
    from tts.audiobook import get_job, JobStatus

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
    }

    if job.status == JobStatus.COMPLETED:
        result["audio_url"] = f"/audio/{job.audio_path.name}"
        result["duration_seconds"] = round(job.duration_seconds, 1)
        result["file_size_mb"] = round(job.file_size_mb, 2)

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
    """List all generated audiobooks (WAV and MP3)."""
    import os
    from datetime import datetime

    audiobooks = []
    audiobook_pattern = "audiobook-"

    # Search for both WAV and MP3 files
    for ext in ["wav", "mp3"]:
        for file in outputs_dir.glob(f"{audiobook_pattern}*.{ext}"):
            stat = file.stat()
            # Parse job_id from filename: audiobook-{job_id}.wav or .mp3
            job_id = file.stem.replace(audiobook_pattern, "")

            # Get audio duration
            try:
                if ext == "wav":
                    import soundfile as sf
                    info = sf.info(str(file))
                    duration_seconds = info.duration
                else:
                    # For MP3, use pydub
                    from pydub import AudioSegment
                    audio = AudioSegment.from_mp3(str(file))
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
            })

    # Sort by creation time, newest first
    audiobooks.sort(key=lambda x: x["created_at"], reverse=True)

    return {"audiobooks": audiobooks, "total": len(audiobooks)}


@app.delete("/api/audiobook/{job_id}")
async def audiobook_delete(job_id: str):
    """Delete an audiobook file (WAV or MP3)."""
    # Check for both WAV and MP3
    wav_path = outputs_dir / f"audiobook-{job_id}.wav"
    mp3_path = outputs_dir / f"audiobook-{job_id}.mp3"

    deleted = False
    if wav_path.exists():
        wav_path.unlink()
        deleted = True
    if mp3_path.exists():
        mp3_path.unlink()
        deleted = True

    if not deleted:
        raise HTTPException(status_code=404, detail=f"Audiobook '{job_id}' not found")

    return {"message": "Audiobook deleted", "job_id": job_id}


# ============== Kokoro Audio Library Endpoints ==============

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
    """List all generated Qwen3/XTTS voice clone audio files."""
    from datetime import datetime

    audio_files = []
    patterns = [
        ("qwen3", "qwen3-*.wav"),
        ("xtts", "xtts-*.wav"),
    ]

    for engine, pattern in patterns:
        for file in outputs_dir.glob(pattern):
            stat = file.stat()
            stem = file.stem
            parts = stem.split("-")

            mode = "clone"
            if engine == "qwen3" and len(parts) > 1:
                mode = parts[1]

            label = "XTTS Clone"
            if engine == "qwen3":
                label = f"Qwen3 {mode.capitalize()}"

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
    # Security: ensure filename starts with qwen3-/xtts- and ends with .wav
    if not (
        filename.endswith(".wav")
        and (filename.startswith("qwen3-") or filename.startswith("xtts-"))
    ):
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
    valid_engines = ["xtts", "kokoro"]
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
