# Suppress pkg_resources deprecation warning from third-party packages (perth, etc.)
# This must be done before any imports that might trigger the warning
import warnings
warnings.filterwarnings("ignore", message="pkg_resources is deprecated")

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Request, BackgroundTasks
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.datastructures import Headers
from starlette.staticfiles import NotModifiedResponse
from pydantic import BaseModel
from pathlib import Path
from contextlib import asynccontextmanager
from collections import deque
from typing import Optional
import logging
from logging.handlers import RotatingFileHandler
import os
import re
import shutil
import mimetypes
import threading
import tempfile
import urllib.request
import zipfile
from datetime import datetime
from urllib.parse import quote, urlparse
import uuid
import soundfile as sf

from database import init_db, seed_db, get_connection
from version import VERSION, VERSION_NAME
from tts.kokoro_engine import get_kokoro_engine, BRITISH_VOICES, DEFAULT_VOICE
from tts.qwen3_engine import get_qwen3_engine, GenerationParams, QWEN_SPEAKERS, unload_all_engines
from tts.chatterbox_engine import get_chatterbox_engine, ChatterboxParams
from tts.supertonic_engine import (
    get_supertonic_engine,
    SupertonicParams,
    SUPPORTED_LANGUAGES as SUPERTONIC_LANGUAGES,
    DEFAULT_VOICE_NAME as SUPERTONIC_DEFAULT_VOICE,
)
from tts.cosyvoice3_engine import (
    get_cosyvoice3_engine,
    CosyVoice3Params,
    SUPPORTED_LANGUAGES as COSYVOICE3_LANGUAGES,
    DEFAULT_VOICE_NAME as COSYVOICE3_DEFAULT_VOICE,
)
from tts.text_chunking import smart_chunk_text
from tts.audio_utils import merge_audio_chunks, resample_audio
from models.registry import ModelRegistry
from settings_service import get_all_settings, get_setting, set_setting, get_output_folder, set_output_folder

def _env_path(name: str) -> Optional[Path]:
    raw = (os.getenv(name) or "").strip()
    return Path(raw).expanduser() if raw else None


def _env_int(name: str, default: int) -> int:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


BACKEND_HOST = (os.getenv("MIMIKA_BACKEND_HOST") or "127.0.0.1").strip() or "127.0.0.1"
BACKEND_PORT = _env_int("MIMIKA_BACKEND_PORT", 7693)


def _ensure_dir_with_fallback(primary: Path, fallback: Path) -> Path:
    try:
        primary.mkdir(parents=True, exist_ok=True)
        return primary
    except OSError:
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


_backend_dir = Path(__file__).resolve().parent
_repo_root = _backend_dir.parents[0]
_runtime_home = _ensure_dir_with_fallback(
    _env_path("MIMIKA_RUNTIME_HOME") or (Path.home() / "MimikaStudio"),
    Path("/tmp/mimikastudio"),
)
_runtime_data_dir = _ensure_dir_with_fallback(
    _env_path("MIMIKA_DATA_DIR") or (_runtime_home / "data"),
    _runtime_home / "data",
)
_bundled_data_dir = _backend_dir / "data"
_log_dir = _ensure_dir_with_fallback(
    _env_path("MIMIKA_LOG_DIR") or (_runtime_home / "logs"),
    Path("/tmp/mimikastudio-logs"),
)
_api_log_path = _log_dir / "backend_api.log"

logger = logging.getLogger("mimika.backend.api")


def _init_mimetypes_for_sandbox() -> None:
    """Avoid sandbox-denied reads of system mime.types files in bundled app builds."""
    # Prevent later bare mimetypes.init() calls from reading protected system paths
    # like /etc/apache2/mime.types inside sandboxed app translocation.
    mimetypes.knownfiles = []
    mimetypes.inited = False
    mimetypes.init(files=[])
    # Ensure common media types used by StaticFiles/FileResponse are registered.
    mimetypes.add_type("application/pdf", ".pdf")
    mimetypes.add_type("audio/wav", ".wav")
    mimetypes.add_type("audio/mpeg", ".mp3")


_init_mimetypes_for_sandbox()


_STATIC_MEDIA_TYPES = {
    ".pdf": "application/pdf",
    ".wav": "audio/wav",
    ".mp3": "audio/mpeg",
    ".txt": "text/plain; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
}


class SafeStaticFiles(StaticFiles):
    """Static files wrapper that avoids stdlib mimetypes file probing in sandbox."""

    def file_response(
        self,
        full_path,
        stat_result,
        scope,
        status_code: int = 200,
    ):
        request_headers = Headers(scope=scope)
        suffix = Path(str(full_path)).suffix.lower()
        media_type = _STATIC_MEDIA_TYPES.get(suffix, "application/octet-stream")
        response = FileResponse(
            full_path,
            status_code=status_code,
            stat_result=stat_result,
            media_type=media_type,
        )
        if self.is_not_modified(response.headers, request_headers):
            return NotModifiedResponse(response.headers)
        return response


class _RequestContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if not hasattr(record, "request_id"):
            record.request_id = "-"
        return True


if not logger.handlers:
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s [request_id=%(request_id)s] %(message)s"
    )
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    file_handler = RotatingFileHandler(
        _api_log_path,
        maxBytes=2 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    request_filter = _RequestContextFilter()
    stream_handler.addFilter(request_filter)
    file_handler.addFilter(request_filter)
    logger.addHandler(stream_handler)
    logger.addHandler(file_handler)
    logger.propagate = False

# Request models
class KokoroRequest(BaseModel):
    text: str
    voice: str = DEFAULT_VOICE
    speed: float = 1.0
    smart_chunking: bool = True
    max_chars_per_chunk: int = 1500
    crossfade_ms: int = 40


class SupertonicRequest(BaseModel):
    text: str
    voice: str = SUPERTONIC_DEFAULT_VOICE
    language: str = "en"
    speed: float = 1.05
    total_steps: int = 5
    smart_chunking: bool = True
    max_chars_per_chunk: int = 300
    silence_ms: int = 300


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
    enqueue: bool = False  # Queue generation and return job_id immediately

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


class WordAlignmentRequest(BaseModel):
    text: str
    audio_url: str
    language: str = "en"


# Lifespan context manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Initializing database...", extra={"request_id": "startup"})
    init_db()
    seed_db()
    _ensure_supertonic_pregenerated_rows()
    _ensure_cosyvoice3_pregenerated_rows()
    env_output_override = _env_path("MIMIKA_OUTPUT_DIR")
    configured_output = str(env_output_override) if env_output_override else get_output_folder()
    _sync_output_folder_runtime(configured_output)
    _migrate_legacy_voice_samples()
    logger.info("Database ready.", extra={"request_id": "startup"})
    yield
    # Shutdown
    logger.info("Shutting down...", extra={"request_id": "shutdown"})

app = FastAPI(
    title="MimikaStudio API",
    description="Local-first Voice Cloning with Qwen3-TTS and Kokoro",
    version=VERSION,
    lifespan=lifespan
)


@app.middleware("http")
async def request_context_middleware(request: Request, call_next):
    request_id = request.headers.get("x-request-id", str(uuid.uuid4())[:12])
    request.state.request_id = request_id
    try:
        response = await call_next(request)
    except (HTTPException, RequestValidationError):
        raise
    except Exception:
        logger.exception(
            "Unhandled exception while processing %s %s",
            request.method,
            request.url.path,
            extra={"request_id": request_id},
        )
        return JSONResponse(
            status_code=500,
            content={
                "error": "internal_server_error",
                "detail": "Internal server error",
                "request_id": request_id,
            },
        )
    response.headers["X-Request-ID"] = request_id
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    request_id = getattr(request.state, "request_id", "-")
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "http_error",
            "detail": exc.detail,
            "request_id": request_id,
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    request_id = getattr(request.state, "request_id", "-")
    return JSONResponse(
        status_code=422,
        content={
            "error": "validation_error",
            "detail": exc.errors(),
            "request_id": request_id,
        },
    )

# CORS origins are configurable for production hardening.
_default_local_origins = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:7693",
    "http://localhost:8000",
    "http://127.0.0.1",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:7693",
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
outputs_dir = _ensure_dir_with_fallback(
    _env_path("MIMIKA_OUTPUT_DIR") or (_runtime_home / "outputs"),
    Path("/tmp/mimikastudio-outputs"),
)
app.mount("/audio", SafeStaticFiles(directory=str(outputs_dir)), name="audio")

_word_align_model = None
_word_align_model_lock = threading.Lock()
_job_history: deque[dict] = deque(maxlen=2000)
_job_history_lock = threading.Lock()
_live_generation_jobs: dict[str, dict] = {}
_live_generation_jobs_lock = threading.Lock()


def _record_job_history_entry(entry: dict) -> None:
    with _job_history_lock:
        _job_history.appendleft(entry)


def _utc_timestamp() -> str:
    return datetime.utcnow().isoformat() + "Z"


def _upsert_live_generation_job(job_id: str, base: Optional[dict] = None, **updates) -> dict:
    with _live_generation_jobs_lock:
        current = dict(_live_generation_jobs.get(job_id, {}))
        if not current and base:
            current.update(base)
        current.update(updates)
        current["id"] = job_id
        current["timestamp"] = current.get("timestamp") or _utc_timestamp()
        _live_generation_jobs[job_id] = current
        return dict(current)


def _pop_live_generation_job(job_id: str) -> Optional[dict]:
    with _live_generation_jobs_lock:
        item = _live_generation_jobs.pop(job_id, None)
    return dict(item) if item else None


def _snapshot_live_generation_jobs() -> list[dict]:
    with _live_generation_jobs_lock:
        return [dict(item) for item in _live_generation_jobs.values()]


def _record_job_event(
    http_request: Request,
    *,
    engine: str,
    mode: str,
    status: str,
    text: str = "",
    output_path: Optional[Path] = None,
    streamed: bool = False,
    voice: Optional[str] = None,
    speaker: Optional[str] = None,
    language: Optional[str] = None,
    model_name: Optional[str] = None,
    job_type: Optional[str] = None,
    job_id: Optional[str] = None,
    title: Optional[str] = None,
) -> None:
    request_id = getattr(http_request.state, "request_id", "-")
    resolved_type = job_type or ("voice_clone" if mode == "clone" else "tts")
    if streamed and resolved_type == "tts":
        resolved_type = "tts_stream"
    _record_job_history_entry(
        {
            "id": job_id or str(uuid.uuid4())[:12],
            "type": resolved_type,
            "engine": engine,
            "mode": mode,
            "status": status,
            "title": title or f"{engine} {mode}",
            "chars": len((text or "").strip()),
            "voice": voice,
            "speaker": speaker,
            "language": language,
            "model": model_name,
            "streamed": streamed,
            "output_path": str(output_path) if output_path else None,
            "audio_url": f"/audio/{output_path.name}" if output_path else None,
            "request_id": request_id,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }
    )


def _log_generation_event(
    http_request: Request,
    *,
    engine: str,
    mode: str,
    text: str,
    output_path: Optional[Path] = None,
    streamed: bool = False,
    voice: Optional[str] = None,
    speaker: Optional[str] = None,
    language: Optional[str] = None,
    model_name: Optional[str] = None,
) -> None:
    """Emit a consistent log line for TTS/voice-clone generation requests."""
    _record_job_event(
        http_request,
        engine=engine,
        mode=mode,
        status="completed",
        text=text,
        output_path=output_path,
        streamed=streamed,
        voice=voice,
        speaker=speaker,
        language=language,
        model_name=model_name,
    )
    request_id = getattr(http_request.state, "request_id", "-")
    logger.info(
        (
            "generation engine=%s mode=%s streamed=%s chars=%s voice=%s "
            "speaker=%s language=%s model=%s output=%s"
        ),
        engine,
        mode,
        "yes" if streamed else "no",
        len((text or "").strip()),
        voice or "-",
        speaker or "-",
        language or "-",
        model_name or "-",
        str(output_path) if output_path else "-",
        extra={"request_id": request_id},
    )


def _log_job_queue_action(
    *,
    action: str,
    job_id: str,
    engine: str,
    mode: str,
    request_id: str = "-",
    status: Optional[str] = None,
    title: Optional[str] = None,
    details: Optional[str] = None,
) -> None:
    logger.info(
        "job_queue action=%s id=%s engine=%s mode=%s status=%s title=%s details=%s",
        action,
        job_id,
        engine,
        mode,
        status or "-",
        title or "-",
        details or "-",
        extra={"request_id": request_id},
    )


def _normalize_alignment_token(token: str) -> str:
    """Normalize words for robust sentence-word alignment."""
    return re.sub(r"[^\w]", "", token).lower()


def _tokenize_alignment_text(text: str) -> list[str]:
    tokens = []
    for raw in re.split(r"\s+", text):
        tok = _normalize_alignment_token(raw)
        if len(tok) >= 2:
            tokens.append(tok)
    return tokens


def _resolve_audio_path_from_url(audio_url: str) -> Path:
    """Resolve /audio/... or absolute localhost URL into local outputs path."""
    path_part = audio_url
    parsed = urlparse(audio_url)
    if parsed.scheme:
        path_part = parsed.path
    if not path_part.startswith("/audio/"):
        raise HTTPException(
            status_code=400,
            detail="audio_url must point to /audio/<filename>",
        )
    filename = Path(path_part).name
    candidate = outputs_dir / filename
    if not candidate.exists() or not candidate.is_file():
        raise HTTPException(status_code=404, detail=f"Audio file not found: {filename}")
    return candidate


def _get_word_align_model():
    """Lazy-load alignment model once (fast startup, lower memory spikes)."""
    global _word_align_model
    if _word_align_model is not None:
        return _word_align_model
    with _word_align_model_lock:
        if _word_align_model is None:
            try:
                from faster_whisper import WhisperModel
            except Exception as e:
                raise HTTPException(
                    status_code=503,
                    detail=(
                        "Forced alignment backend unavailable. "
                        "Install: pip install faster-whisper"
                    ),
                ) from e
            _word_align_model = WhisperModel("tiny.en", device="cpu", compute_type="int8")
    return _word_align_model


def _align_expected_words_to_observed(
    expected_tokens: list[str],
    observed_words: list[dict],
) -> list[int]:
    """Map expected tokens to observed ASR words using monotonic greedy match."""
    starts_ms: list[int] = []
    cursor = 0
    last_ms = 0

    for expected in expected_tokens:
        matched_ms: Optional[int] = None
        for i in range(cursor, len(observed_words)):
            if observed_words[i]["token"] == expected:
                matched_ms = observed_words[i]["start_ms"]
                cursor = i + 1
                last_ms = matched_ms
                break

        if matched_ms is None:
            # Keep sequence length stable; fallback to previous boundary.
            starts_ms.append(last_ms)
        else:
            starts_ms.append(matched_ms)

    return starts_ms


def _safe_read_text(path: Path) -> str:
    """Read text files safely to avoid decode/runtime crashes on user files."""
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _sync_output_folder_runtime(path: str) -> Path:
    """Apply output-folder setting to runtime storage and /audio static mount."""
    global outputs_dir
    configured = (path or "").strip()
    resolved = Path(configured).expanduser() if configured else (Path.home() / "MimikaStudio" / "outputs")
    try:
        resolved.mkdir(parents=True, exist_ok=True)
    except OSError:
        fallback = _ensure_dir_with_fallback(
            _runtime_home / "outputs",
            Path("/tmp/mimikastudio-outputs"),
        )
        logger.exception(
            "Failed to use output folder '%s', falling back to '%s'",
            configured or "<empty>",
            fallback,
            extra={"request_id": "runtime"},
        )
        resolved = fallback
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


def _output_folder_from_env_or_settings() -> str:
    env_output_override = _env_path("MIMIKA_OUTPUT_DIR")
    if env_output_override is not None:
        return str(env_output_override)
    return get_output_folder()


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


def _ensure_supertonic_pregenerated_rows() -> None:
    """Ensure Supertonic pregenerated sample rows exist in the database."""
    pregen_dir = _bundled_data_dir / "pregenerated"
    samples = [
        {
            "engine": "supertonic",
            "voice": "F1",
            "title": "Genesis 4 Preview (F1)",
            "description": "Supertonic F1 English preview for instant playback",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen? If thou doest well, "
                "shalt thou not be accepted? and if thou doest not well, sin lieth at the door."
            ),
            "file_name": "supertonic-f1-genesis4-demo.wav",
        },
        {
            "engine": "supertonic",
            "voice": "M2",
            "title": "Genesis 4 Preview (M2)",
            "description": "Supertonic M2 English preview using Genesis 4:8-9",
            "text": (
                "Genesis chapter 4, verses 8 and 9: And Cain talked with Abel his brother: "
                "and it came to pass, when they were in the field, that Cain rose up against Abel his brother, "
                "and slew him. And the Lord said unto Cain, Where is Abel thy brother? "
                "And he said, I know not: Am I my brother's keeper?"
            ),
            "file_name": "supertonic-m2-genesis4-demo.wav",
        },
    ]

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """
        DELETE FROM pregenerated_samples
        WHERE engine = ?
          AND (
                title = ?
                OR file_path LIKE ?
          )
        """,
        ("supertonic", "Deterrence Brief (M2)", "%/supertonic-m2-geopolitics-demo.wav"),
    )
    removed = cursor.rowcount
    inserted = 0
    for sample in samples:
        file_path = pregen_dir / sample["file_name"]
        if not file_path.exists():
            continue
        cursor.execute(
            "SELECT id FROM pregenerated_samples WHERE engine = ? AND file_path = ?",
            (sample["engine"], str(file_path)),
        )
        existing = cursor.fetchone()
        if existing is not None:
            cursor.execute(
                """
                UPDATE pregenerated_samples
                SET voice = ?, title = ?, description = ?, text = ?
                WHERE id = ?
                """,
                (
                    sample["voice"],
                    sample["title"],
                    sample["description"],
                    sample["text"],
                    existing[0],
                ),
            )
            continue
        cursor.execute(
            """
            INSERT INTO pregenerated_samples (engine, voice, title, description, text, file_path)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                sample["engine"],
                sample["voice"],
                sample["title"],
                sample["description"],
                sample["text"],
                str(file_path),
            ),
        )
        inserted += 1

    if inserted > 0 or removed > 0:
        conn.commit()
        logger.info(
            "Reconciled Supertonic pregenerated rows (inserted=%s removed=%s)",
            inserted,
            removed,
            extra={"request_id": "startup"},
        )
    conn.close()


def _ensure_cosyvoice3_pregenerated_rows() -> None:
    """Ensure CosyVoice3 pregenerated Bible sample rows/files exist."""
    pregen_dir = _bundled_data_dir / "pregenerated"
    if not pregen_dir.exists():
        return

    # Keep separate filenames/rows so the UI and filtering are engine-specific.
    source_to_target = [
        ("supertonic-f1-genesis4-demo.wav", "cosyvoice3-f1-genesis4-demo.wav"),
        ("supertonic-m2-genesis4-demo.wav", "cosyvoice3-m2-genesis4-demo.wav"),
    ]
    for source_name, target_name in source_to_target:
        source_path = pregen_dir / source_name
        target_path = pregen_dir / target_name
        if source_path.exists() and not target_path.exists():
            shutil.copy2(source_path, target_path)

    samples = [
        {
            "engine": "cosyvoice3",
            "voice": "Eden",
            "title": "Genesis 4 Preview (Eden)",
            "description": "CosyVoice3 Eden English preview for instant playback",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen? If thou doest well, "
                "shalt thou not be accepted? and if thou doest not well, sin lieth at the door."
            ),
            "file_name": "cosyvoice3-f1-genesis4-demo.wav",
        },
        {
            "engine": "cosyvoice3",
            "voice": "Atlas",
            "title": "Genesis 4 Preview (Atlas)",
            "description": "CosyVoice3 Atlas English preview using Genesis 4:8-9",
            "text": (
                "Genesis chapter 4, verses 8 and 9: And Cain talked with Abel his brother: "
                "and it came to pass, when they were in the field, that Cain rose up against Abel his brother, "
                "and slew him. And the Lord said unto Cain, Where is Abel thy brother? "
                "And he said, I know not: Am I my brother's keeper?"
            ),
            "file_name": "cosyvoice3-m2-genesis4-demo.wav",
        },
    ]

    conn = get_connection()
    cursor = conn.cursor()
    removed = 0
    inserted = 0
    for sample in samples:
        file_path = pregen_dir / sample["file_name"]
        if not file_path.exists():
            continue
        cursor.execute(
            "SELECT id FROM pregenerated_samples WHERE engine = ? AND file_path = ?",
            (sample["engine"], str(file_path)),
        )
        if cursor.fetchone() is not None:
            continue
        cursor.execute(
            """
            INSERT INTO pregenerated_samples (engine, voice, title, description, text, file_path)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                sample["engine"],
                sample["voice"],
                sample["title"],
                sample["description"],
                sample["text"],
                str(file_path),
            ),
        )
        inserted += 1

    expected_paths = {str((pregen_dir / sample["file_name"]).resolve()) for sample in samples}

    # Remove stale CosyVoice3 rows if file is missing or not part of the expected set.
    cursor.execute(
        "SELECT id, file_path FROM pregenerated_samples WHERE engine = ?",
        ("cosyvoice3",),
    )
    stale_ids = []
    for row in cursor.fetchall():
        sid, file_path = row
        resolved_path = str(Path(file_path).resolve())
        if (not Path(file_path).exists()) or (resolved_path not in expected_paths):
            stale_ids.append((sid,))
    if stale_ids:
        cursor.executemany(
            "DELETE FROM pregenerated_samples WHERE id = ?",
            stale_ids,
        )
        removed = len(stale_ids)

    if inserted > 0 or removed > 0:
        conn.commit()
        logger.info(
            "Reconciled CosyVoice3 pregenerated rows (inserted=%s removed=%s)",
            inserted,
            removed,
            extra={"request_id": "startup"},
        )
    conn.close()

# Qwen3 voice storage locations
SHARED_SAMPLE_VOICES_DIR = _bundled_data_dir / "samples" / "voices"
QWEN3_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
CLONER_USER_VOICES_DIR = _runtime_data_dir / "user_voices" / "cloners"
QWEN3_USER_VOICES_DIR = CLONER_USER_VOICES_DIR

# Chatterbox voice storage locations
CHATTERBOX_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
CHATTERBOX_USER_VOICES_DIR = CLONER_USER_VOICES_DIR

# IndexTTS-2 voice storage locations
INDEXTTS2_SAMPLE_VOICES_DIR = SHARED_SAMPLE_VOICES_DIR
INDEXTTS2_USER_VOICES_DIR = CLONER_USER_VOICES_DIR
_bundled_dicta_model_dir = _backend_dir / "models" / "dicta-onnx"
_runtime_dicta_model_dir = _runtime_data_dir / "models" / "dicta-onnx"
if (_bundled_dicta_model_dir / "dicta-1.0.onnx").exists():
    DICTA_MODEL_DIR = _bundled_dicta_model_dir
else:
    DICTA_MODEL_DIR = _runtime_dicta_model_dir
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
        ("cloners", CLONER_USER_VOICES_DIR, "user"),
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
                    transcript = _safe_read_text(txt_file).strip()
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
        CLONER_USER_VOICES_DIR,
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
    samples_root = _bundled_data_dir / "samples"
    shared_dir = SHARED_SAMPLE_VOICES_DIR
    cloner_user_dir = CLONER_USER_VOICES_DIR
    legacy_qwen3_dir = samples_root / "qwen3_voices"
    legacy_chatterbox_dir = samples_root / "chatterbox_voices"

    CLONER_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)

    def move_voice(src_dir: Path, name: str, dest_dir: Path) -> None:
        src_wav = src_dir / f"{name}.wav"
        src_txt = src_dir / f"{name}.txt"
        if src_wav.exists():
            try:
                dest_wav = dest_dir / src_wav.name
                if dest_wav.exists():
                    src_wav.unlink()
                else:
                    shutil.move(str(src_wav), str(dest_wav))
            except OSError:
                logger.warning(
                    "Skipping voice migration for %s (read-only or permission issue)",
                    src_wav,
                    extra={"request_id": "startup"},
                )
        if src_txt.exists():
            try:
                dest_txt = dest_dir / src_txt.name
                if dest_txt.exists():
                    src_txt.unlink()
                else:
                    shutil.move(str(src_txt), str(dest_txt))
            except OSError:
                logger.warning(
                    "Skipping transcript migration for %s (read-only or permission issue)",
                    src_txt,
                    extra={"request_id": "startup"},
                )

    # Migrate deprecated engine-specific sample folders into shared defaults.
    for legacy_dir in (legacy_qwen3_dir, legacy_chatterbox_dir):
        if not legacy_dir.exists():
            continue
        for wav_file in legacy_dir.glob("*.wav"):
            move_voice(legacy_dir, wav_file.stem, shared_dir)

    runtime_user_root = _runtime_data_dir / "user_voices"
    legacy_user_dirs = (
        runtime_user_root / "qwen3",
        runtime_user_root / "chatterbox",
        runtime_user_root / "indextts2",
        _bundled_data_dir / "user_voices" / "qwen3",
        _bundled_data_dir / "user_voices" / "chatterbox",
        _bundled_data_dir / "user_voices" / "indextts2",
    )
    for legacy_user_dir in legacy_user_dirs:
        if legacy_user_dir.resolve() == cloner_user_dir.resolve():
            continue
        if not legacy_user_dir.exists():
            continue
        for wav_file in legacy_user_dir.glob("*.wav"):
            move_voice(legacy_user_dir, wav_file.stem, cloner_user_dir)


def _safe_tag(value: str, fallback: str = "model") -> str:
    tag = re.sub(r"[^a-zA-Z0-9_-]+", "", value.replace("/", "-").replace(" ", "-")).strip("-_")
    return tag[:32] if tag else fallback


def _decode_and_normalize_uploaded_voice(uploaded_path: Path, target_path: Path) -> float:
    """Decode user upload and normalize it to mono 24k PCM WAV."""
    try:
        audio, sample_rate = sf.read(str(uploaded_path), dtype="float32")
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid or unsupported audio file. Please upload a WAV file. ({exc})",
        ) from exc

    if getattr(audio, "size", 0) == 0:
        raise HTTPException(status_code=400, detail="Uploaded audio is empty")

    if len(audio.shape) > 1:
        audio = audio.mean(axis=1)
    if sample_rate <= 0:
        raise HTTPException(status_code=400, detail="Invalid audio sample rate")

    normalized_sr = 24000
    if sample_rate != normalized_sr:
        audio = resample_audio(audio, sample_rate, normalized_sr)
        sample_rate = normalized_sr

    sf.write(str(target_path), audio, sample_rate, subtype="PCM_16")
    return float(len(audio) / sample_rate)


def _prepare_clone_reference_audio(audio_path: str, voice_name: str) -> Path:
    """Normalize a clone reference voice to a guaranteed readable WAV path."""
    source = Path(audio_path)
    if not source.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Voice sample '{voice_name}' file is missing. Re-upload the voice.",
        )

    outputs_dir.mkdir(parents=True, exist_ok=True)
    temp_ref = outputs_dir / f"qwen3-ref-{_safe_tag(voice_name, 'voice')}-{uuid.uuid4().hex[:8]}.wav"
    try:
        _decode_and_normalize_uploaded_voice(source, temp_ref)
    except HTTPException as exc:
        temp_ref.unlink(missing_ok=True)
        raise HTTPException(
            status_code=400,
            detail=(
                f"Voice sample '{voice_name}' cannot be decoded. "
                "Please re-upload this voice as a WAV file."
            ),
        ) from exc
    return temp_ref


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


def _cleanup_temp_file(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _write_diagnostics_bundle(zip_path: Path) -> int:
    file_count = 0

    with zipfile.ZipFile(zip_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        now = datetime.now().astimezone().isoformat()
        archive.writestr(
            "metadata.txt",
            "\n".join(
                [
                    "MimikaStudio Diagnostics Bundle",
                    f"Generated: {now}",
                    f"Version: {VERSION} ({VERSION_NAME})",
                    f"Repository Root: {_repo_root}",
                ]
            )
            + "\n",
        )

        def add_directory(source_dir: Path, archive_prefix: str) -> None:
            nonlocal file_count
            if not source_dir.exists() or not source_dir.is_dir():
                return
            for file_path in sorted(source_dir.rglob("*")):
                if not file_path.is_file():
                    continue
                relative = file_path.relative_to(source_dir).as_posix()
                archive.write(file_path, arcname=f"{archive_prefix}/{relative}")
                file_count += 1

        add_directory(_repo_root / "runs" / "logs", "runs/logs")
        add_directory(_repo_root / ".logs", ".logs")

    return file_count


def _collect_system_log_sources() -> list[Path]:
    """Return known system-log files ordered from oldest to newest."""
    candidates: list[Path] = []
    seen: set[Path] = set()
    base_files = [
        _api_log_path,
        _log_dir / "backend.log",
        Path("/tmp/mimikastudio-backend.log"),
        _repo_root / "runs" / "logs" / "backend_api.log",
        _repo_root / ".logs" / "backend_api.log",
    ]

    for base in base_files:
        parent = base.parent
        if not parent.exists():
            continue
        pattern = f"{base.name}*"
        matches = sorted(parent.glob(pattern), key=lambda p: p.stat().st_mtime if p.exists() else 0.0)
        for path in matches:
            try:
                resolved = path.resolve()
            except OSError:
                continue
            if resolved in seen or not path.is_file():
                continue
            seen.add(resolved)
            candidates.append(path)

    if candidates:
        return candidates

    fallback_logs = sorted(_log_dir.glob("*.log*"), key=lambda p: p.stat().st_mtime if p.exists() else 0.0)
    for path in fallback_logs:
        try:
            resolved = path.resolve()
        except OSError:
            continue
        if resolved in seen or not path.is_file():
            continue
        seen.add(resolved)
        candidates.append(path)
    return candidates


def _read_system_log_lines(max_lines: int = 500) -> tuple[list[str], list[str]]:
    """Read and merge backend log lines with a global tail limit."""
    limit = max(50, min(max_lines, 5000))
    merged: deque[str] = deque(maxlen=limit)
    sources: list[str] = []

    for source in _collect_system_log_sources():
        source_label = source.name
        sources.append(str(source))
        try:
            with source.open("r", encoding="utf-8", errors="replace") as handle:
                for raw_line in handle:
                    line = raw_line.rstrip("\n")
                    if not line.strip():
                        continue
                    merged.append(f"[{source_label}] {line}")
        except OSError:
            continue

    return list(merged), sources


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
    import subprocess
    from importlib import metadata

    # Probe MLX in a subprocess to avoid hard interpreter aborts from native import failures.
    probe_code = (
        "import mlx.core as mx; "
        "print('1' if bool(mx.metal.is_available()) else '0')"
    )
    try:
        probe = subprocess.run(
            [sys.executable, "-c", probe_code],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        mlx_available = probe.returncode == 0 and probe.stdout.strip() == "1"
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
    supertonic_info = {
        "model": "Supertone/supertonic-2",
        "backend": "onnxruntime",
        "features": "multilingual on-device synthesis",
    }
    cosyvoice3_info = {
        "model": "ayousanz/cosy-voice3-onnx",
        "backend": "onnxruntime",
        "features": "expressive preset multilingual TTS (separate ONNX stack)",
    }
    folders = [
        {"id": "user_home", "label": "User Home", "path": str(Path.home())},
        {"id": "runtime_home", "label": "Mimika User Folder", "path": str(_runtime_home)},
        {"id": "runtime_data", "label": "Mimika Data Folder", "path": str(_runtime_data_dir)},
        {"id": "output", "label": "Generated Audio Folder", "path": str(outputs_dir)},
        {"id": "logs", "label": "Log Folder", "path": str(_log_dir)},
        {
            "id": "default_voices",
            "label": "Default Voices (Natasha/Max)",
            "path": str(SHARED_SAMPLE_VOICES_DIR),
        },
        {
            "id": "user_cloner_voices",
            "label": "Your Voice Clones",
            "path": str(CLONER_USER_VOICES_DIR),
        },
    ]

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
            "supertonic": supertonic_info,
            "cosyvoice3": cosyvoice3_info,
        },
        "folders": folders,
    }


@app.get("/api/system/folders")
async def system_folders():
    """List important runtime folders exposed in Settings."""
    return {
        "folders": [
            {"id": "user_home", "label": "User Home", "path": str(Path.home())},
            {"id": "runtime_home", "label": "Mimika User Folder", "path": str(_runtime_home)},
            {"id": "runtime_data", "label": "Mimika Data Folder", "path": str(_runtime_data_dir)},
            {"id": "output", "label": "Generated Audio Folder", "path": str(outputs_dir)},
            {"id": "logs", "label": "Log Folder", "path": str(_log_dir)},
            {
                "id": "default_voices",
                "label": "Default Voices (Natasha/Max)",
                "path": str(SHARED_SAMPLE_VOICES_DIR),
            },
            {
                "id": "user_cloner_voices",
                "label": "Your Voice Clones",
                "path": str(CLONER_USER_VOICES_DIR),
            },
        ]
    }

# System monitoring
@app.get("/api/system/stats")
async def system_stats():
    """Get real-time system stats: CPU, RAM, GPU memory."""
    import json
    import psutil
    import subprocess
    import sys

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

    # GPU memory (if available on MLX). Probe in a subprocess to avoid hard aborts.
    probe_code = """
import json
import mlx.core as mx
if not mx.metal.is_available():
    print("{}")
else:
    print(json.dumps({
        "active": float(mx.get_active_memory()),
        "peak": float(mx.get_peak_memory())
    }))
"""
    try:
        probe = subprocess.run(
            [sys.executable, "-c", probe_code],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if probe.returncode == 0:
            payload = json.loads(probe.stdout.strip() or "{}")
            active_raw = payload.get("active")
            peak_raw = payload.get("peak")
            if active_raw is not None and peak_raw is not None:
                active_mem = float(active_raw) / (1024 ** 3)
                peak_mem = float(peak_raw) / (1024 ** 3)
                result["gpu"] = {
                    "name": "Apple Silicon (MLX)",
                    "memory_used_gb": round(active_mem, 2),
                    "memory_total_gb": None,
                    "memory_percent": None,
                    "peak_memory_gb": round(peak_mem, 2),
                    "note": "MLX memory is shared with system RAM",
                }
    except Exception:
        pass

    return result


@app.get("/api/system/diagnostics/export")
async def export_system_diagnostics(background_tasks: BackgroundTasks):
    """Create and download a ZIP bundle of diagnostic logs."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    fd, temp_path = tempfile.mkstemp(prefix=f"mimika_diagnostics_{timestamp}_", suffix=".zip")
    os.close(fd)
    zip_path = Path(temp_path)

    try:
        file_count = _write_diagnostics_bundle(zip_path)
        if file_count == 0:
            raise HTTPException(status_code=404, detail="No diagnostic logs found to export")

        background_tasks.add_task(_cleanup_temp_file, zip_path)
        return FileResponse(
            path=str(zip_path),
            media_type="application/zip",
            filename=f"mimika_diagnostics_{timestamp}.zip",
        )
    except HTTPException:
        _cleanup_temp_file(zip_path)
        raise
    except Exception as exc:
        _cleanup_temp_file(zip_path)
        logger.exception(
            "Failed to export diagnostics bundle: %s",
            exc,
            extra={"request_id": "diagnostics"},
        )
        raise HTTPException(
            status_code=500,
            detail=f"Failed to export diagnostic logs: {exc}",
        ) from exc


@app.get("/api/system/logs")
async def system_logs(max_lines: int = 500):
    """Return tail lines from available backend/system log files."""
    lines, sources = _read_system_log_lines(max_lines=max_lines)
    return {
        "lines": lines,
        "line_count": len(lines),
        "sources": sources,
        "generated_at": datetime.now().astimezone().isoformat(),
    }


@app.get("/api/system/logs/export")
async def export_system_logs(background_tasks: BackgroundTasks, max_lines: int = 2000):
    """Export merged backend/system logs as a plain text file."""
    lines, sources = _read_system_log_lines(max_lines=max_lines)
    if not lines:
        raise HTTPException(status_code=404, detail="No system logs available")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    fd, temp_path = tempfile.mkstemp(prefix=f"mimika_system_logs_{timestamp}_", suffix=".log")
    os.close(fd)
    log_path = Path(temp_path)

    try:
        with log_path.open("w", encoding="utf-8") as handle:
            handle.write("MimikaStudio System Logs\n")
            handle.write(f"Generated: {datetime.now().astimezone().isoformat()}\n")
            if sources:
                handle.write("Sources:\n")
                for source in sources:
                    handle.write(f"- {source}\n")
            handle.write("\n")
            handle.write("\n".join(lines))
            handle.write("\n")

        background_tasks.add_task(_cleanup_temp_file, log_path)
        return FileResponse(
            path=str(log_path),
            media_type="text/plain; charset=utf-8",
            filename=f"mimika_system_logs_{timestamp}.log",
        )
    except Exception as exc:
        _cleanup_temp_file(log_path)
        logger.exception(
            "Failed to export system logs: %s",
            exc,
            extra={"request_id": "system-logs"},
        )
        raise HTTPException(
            status_code=500,
            detail=f"Failed to export system logs: {exc}",
        ) from exc


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
async def kokoro_generate(request: KokoroRequest, http_request: Request):
    """Generate speech using Kokoro with predefined British voice."""
    try:
        _ensure_named_model_ready("Kokoro", engine_label="Kokoro")
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
        _log_generation_event(
            http_request,
            engine="kokoro",
            mode="tts",
            text=request.text,
            output_path=output_path,
            voice=voice,
            model_name="Kokoro",
        )

        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name
        }
    except ModuleNotFoundError as e:
        if getattr(e, "name", "") == "torch":
            raise HTTPException(
                status_code=503,
                detail=(
                    "Kokoro backend dependency mismatch in this build. "
                    "Kokoro is MLX-based, but an optional spaCy plugin tried to import torch. "
                    "Please update to the latest DMG build. "
                    f"Error: {e}"
                ),
            )
        raise
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Kokoro backend unavailable. Run: pip install -U mlx-audio. Error: {e}",
        )


@app.post("/api/tts/align-words")
async def tts_align_words(request: WordAlignmentRequest):
    """Forced word alignment via faster-whisper word timestamps."""
    expected_tokens = _tokenize_alignment_text(request.text)
    if not expected_tokens:
        return {
            "timings_ms": [],
            "expected_count": 0,
            "matched_count": 0,
            "engine": "faster-whisper",
        }

    audio_path = _resolve_audio_path_from_url(request.audio_url)
    model = _get_word_align_model()

    segments, _ = model.transcribe(
        str(audio_path),
        language=(request.language or "en"),
        word_timestamps=True,
        beam_size=1,
        condition_on_previous_text=False,
        vad_filter=False,
    )

    observed_words: list[dict] = []
    for seg in segments:
        words = getattr(seg, "words", None) or []
        for word in words:
            token = _normalize_alignment_token(getattr(word, "word", "") or "")
            if len(token) < 2:
                continue
            start = int(round((getattr(word, "start", 0.0) or 0.0) * 1000))
            end = int(round((getattr(word, "end", 0.0) or 0.0) * 1000))
            observed_words.append(
                {"token": token, "start_ms": max(0, start), "end_ms": max(0, end)}
            )

    starts_ms = _align_expected_words_to_observed(expected_tokens, observed_words)
    matched_count = sum(1 for ms in starts_ms if ms > 0)
    return {
        "timings_ms": starts_ms,
        "expected_count": len(expected_tokens),
        "matched_count": matched_count,
        "engine": "faster-whisper",
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


# ============== Supertonic Endpoints ==============

@app.post("/api/supertonic/generate")
async def supertonic_generate(request: SupertonicRequest, http_request: Request):
    """Generate speech using Supertonic-2 ONNX model."""
    try:
        snapshot_path = _ensure_named_model_ready("Supertonic-2", engine_label="Supertonic")
        engine = get_supertonic_engine()
        engine.outputs_dir = outputs_dir
        engine.outputs_dir.mkdir(parents=True, exist_ok=True)
        params = SupertonicParams(
            speed=request.speed,
            total_steps=request.total_steps,
            max_chunk_length=request.max_chars_per_chunk if request.smart_chunking else None,
            silence_duration=max(0.0, float(request.silence_ms) / 1000.0),
            language=request.language,
        )
        output_path = engine.generate(
            text=request.text,
            voice=request.voice,
            params=params,
            model_name="supertonic-2",
            model_dir=snapshot_path,
        )
        _log_generation_event(
            http_request,
            engine="supertonic",
            mode="tts",
            text=request.text,
            output_path=output_path,
            voice=request.voice,
            language=request.language,
            model_name="Supertonic-2",
        )
        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name,
            "voice": request.voice,
            "language": request.language,
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Supertonic backend unavailable. Run: pip install supertonic. Error: {e}",
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/api/supertonic/voices")
async def supertonic_list_voices():
    """List available Supertonic preset voice styles."""
    engine = get_supertonic_engine()
    voices = engine.get_voices()
    return {"voices": voices, "default": SUPERTONIC_DEFAULT_VOICE}


@app.get("/api/supertonic/languages")
async def supertonic_list_languages():
    return {"languages": list(SUPERTONIC_LANGUAGES), "default": "en"}


@app.get("/api/supertonic/info")
async def supertonic_info():
    engine = get_supertonic_engine()
    info = engine.get_model_info()
    try:
        import supertonic  # noqa: F401
        info["installed"] = True
    except Exception:
        info["installed"] = False
    return info


# ============== CosyVoice3 Endpoints (Isolated from Supertonic UI namespace) ==============

@app.get("/api/cosyvoice3/voices")
async def cosyvoice3_list_voices():
    """List available CosyVoice3 ONNX preset voices."""
    engine = get_cosyvoice3_engine()
    return {"voices": engine.get_voices(), "default": COSYVOICE3_DEFAULT_VOICE}


@app.get("/api/cosyvoice3/languages")
async def cosyvoice3_list_languages():
    """List languages supported by CosyVoice3 backend."""
    return {"languages": list(COSYVOICE3_LANGUAGES), "default": "Auto"}


@app.get("/api/cosyvoice3/info")
async def cosyvoice3_info():
    engine = get_cosyvoice3_engine()
    info = engine.get_model_info()
    info["installed"] = bool(engine.is_runtime_available())
    return info


@app.post("/api/cosyvoice3/generate")
async def cosyvoice3_generate(request: SupertonicRequest, http_request: Request):
    """Generate speech using the dedicated CosyVoice3 ONNX runtime."""
    try:
        snapshot_path = _ensure_named_model_ready("CosyVoice3", engine_label="CosyVoice3")
        engine = get_cosyvoice3_engine()
        engine.outputs_dir = outputs_dir
        engine.outputs_dir.mkdir(parents=True, exist_ok=True)
        params = CosyVoice3Params(
            speed=request.speed,
            language=request.language,
            total_steps=request.total_steps,
        )
        output_path = engine.generate(
            text=request.text,
            voice=request.voice,
            params=params,
            snapshot_dir=snapshot_path,
        )
        resolved_voice = request.voice if request.voice else COSYVOICE3_DEFAULT_VOICE
        _log_generation_event(
            http_request,
            engine="cosyvoice3",
            mode="tts",
            text=request.text,
            output_path=output_path,
            voice=resolved_voice,
            language=request.language,
            model_name="CosyVoice3",
        )
        return {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name,
            "voice": resolved_voice,
            "language": request.language,
        }
    except ImportError as e:
        raise HTTPException(
            status_code=503,
            detail=(
                "CosyVoice3 ONNX runtime unavailable. Install dependencies: "
                "onnxruntime==1.18.0 librosa transformers soundfile scipy. "
                f"Error: {e}"
            ),
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

# ============== Qwen3-TTS Endpoints (Voice Clone + Custom Voice) ==============

def _qwen3_model_name_for_request(mode: str, model_size: str, model_quantization: str) -> str:
    suffix = "Base" if mode == "clone" else "CustomVoice"
    quant_suffix = "-8bit" if model_quantization == "8bit" else ""
    return f"Qwen3-TTS-12Hz-{model_size}-{suffix}{quant_suffix}"


def _ensure_named_model_ready(model_name: str, engine_label: Optional[str] = None) -> Path:
    """Validate a registry model is fully downloaded before inference."""
    registry = ModelRegistry()
    model = registry.get_model(model_name)
    if model is None:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' not found")

    snapshot_path = registry.get_downloaded_snapshot_path(model)
    if snapshot_path is None:
        cache_dir = registry.get_model_cache_dir(model)
        label = engine_label or model.engine
        raise HTTPException(
            status_code=409,
            detail=(
                f"{label} model '{model_name}' is not fully downloaded yet. "
                f"Download target: {cache_dir}"
            ),
        )
    return snapshot_path


def _ensure_qwen3_model_ready(mode: str, model_size: str, model_quantization: str) -> Path:
    """Validate required Qwen3 model is fully downloaded before inference."""
    model_name = _qwen3_model_name_for_request(mode, model_size, model_quantization)
    return _ensure_named_model_ready(model_name, engine_label="Qwen3")


def _run_qwen3_generation(request: Qwen3Request) -> tuple[dict, Path]:
    if request.model_quantization not in {"bf16", "8bit"}:
        raise HTTPException(
            status_code=400,
            detail="model_quantization must be 'bf16' or '8bit'",
        )
    _ensure_qwen3_model_ready(
        mode=request.mode,
        model_size=request.model_size,
        model_quantization=request.model_quantization,
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
            mode="clone"
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
                transcript = _safe_read_text(txt_file).strip()
            voice = {"name": request.voice_name, "audio_path": str(audio_file), "transcript": transcript}

        prepared_ref_path = _prepare_clone_reference_audio(
            voice["audio_path"],
            request.voice_name,
        )
        try:
            output_path = engine.generate_voice_clone(
                text=request.text,
                ref_audio_path=str(prepared_ref_path),
                ref_text=voice["transcript"],
                language=request.language,
                speed=request.speed,
                params=params,
            )
        finally:
            prepared_ref_path.unlink(missing_ok=True)

        result = {
            "audio_url": f"/audio/{output_path.name}",
            "filename": output_path.name,
            "mode": "clone",
            "voice": request.voice_name,
        }

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

    if request.unload_after:
        engine.unload()

    return result, output_path


def _queue_qwen3_job(request: Qwen3Request, http_request: Request) -> dict:
    if request.model_quantization not in {"bf16", "8bit"}:
        raise HTTPException(
            status_code=400,
            detail="model_quantization must be 'bf16' or '8bit'",
        )
    _ensure_qwen3_model_ready(
        mode=request.mode,
        model_size=request.model_size,
        model_quantization=request.model_quantization,
    )

    request_id = getattr(http_request.state, "request_id", "-")
    job_id = str(uuid.uuid4())[:12]
    model_name = _qwen3_model_name_for_request(
        request.mode,
        request.model_size,
        request.model_quantization,
    )
    base_job = {
        "id": job_id,
        "type": "voice_clone" if request.mode == "clone" else "tts",
        "engine": "qwen3",
        "mode": request.mode,
        "status": "started",
        "title": f"qwen3 {request.mode}",
        "chars": len((request.text or "").strip()),
        "voice": request.voice_name if request.mode == "clone" else None,
        "speaker": request.speaker if request.mode == "custom" else None,
        "language": request.language,
        "model": model_name,
        "streamed": False,
        "output_path": None,
        "audio_url": None,
        "request_id": request_id,
        "timestamp": _utc_timestamp(),
    }
    _upsert_live_generation_job(job_id, base=base_job)
    _log_job_queue_action(
        action="enqueue",
        job_id=job_id,
        engine="qwen3",
        mode=request.mode,
        request_id=request_id,
        status="started",
        title=base_job["title"],
        details=f"chars={base_job['chars']}",
    )

    payload = request.model_dump() if hasattr(request, "model_dump") else request.dict()

    def _worker():
        _upsert_live_generation_job(job_id, status="processing")
        _log_job_queue_action(
            action="processing",
            job_id=job_id,
            engine="qwen3",
            mode=request.mode,
            request_id=request_id,
            status="processing",
            title=base_job["title"],
        )
        try:
            queued_request = Qwen3Request(**payload)
            result, output_path = _run_qwen3_generation(queued_request)

            completed = _upsert_live_generation_job(
                job_id,
                status="completed",
                output_path=str(output_path),
                audio_url=result.get("audio_url"),
            )
            _record_job_history_entry(completed)
            _log_job_queue_action(
                action="completed",
                job_id=job_id,
                engine="qwen3",
                mode=queued_request.mode,
                request_id=request_id,
                status="completed",
                title=base_job["title"],
                details=str(output_path),
            )
            logger.info(
                "generation engine=%s mode=%s streamed=no chars=%s voice=%s speaker=%s language=%s model=%s output=%s",
                "qwen3",
                queued_request.mode,
                len((queued_request.text or "").strip()),
                queued_request.voice_name or "-",
                queued_request.speaker or "-",
                queued_request.language or "-",
                model_name,
                str(output_path),
                extra={"request_id": request_id},
            )
        except HTTPException as exc:
            failed = _upsert_live_generation_job(
                job_id,
                status="failed",
                error=str(exc.detail),
            )
            _record_job_history_entry(failed)
            _log_job_queue_action(
                action="failed",
                job_id=job_id,
                engine="qwen3",
                mode=request.mode,
                request_id=request_id,
                status="failed",
                title=base_job["title"],
                details=str(exc.detail),
            )
            logger.warning(
                "queued generation failed engine=qwen3 mode=%s detail=%s",
                request.mode,
                str(exc.detail),
                extra={"request_id": request_id},
            )
        except ImportError as exc:
            failed = _upsert_live_generation_job(
                job_id,
                status="failed",
                error=f"Qwen3-TTS backend unavailable. Run: pip install -U mlx-audio. Error: {exc}",
            )
            _record_job_history_entry(failed)
            _log_job_queue_action(
                action="failed",
                job_id=job_id,
                engine="qwen3",
                mode=request.mode,
                request_id=request_id,
                status="failed",
                title=base_job["title"],
                details=str(exc),
            )
            logger.warning(
                "queued generation unavailable engine=qwen3 mode=%s detail=%s",
                request.mode,
                str(exc),
                extra={"request_id": request_id},
            )
        except Exception as exc:
            failed = _upsert_live_generation_job(
                job_id,
                status="failed",
                error=str(exc),
            )
            _record_job_history_entry(failed)
            _log_job_queue_action(
                action="failed",
                job_id=job_id,
                engine="qwen3",
                mode=request.mode,
                request_id=request_id,
                status="failed",
                title=base_job["title"],
                details=str(exc),
            )
            logger.exception(
                "queued generation crashed engine=qwen3 mode=%s",
                request.mode,
                extra={"request_id": request_id},
            )
        finally:
            _pop_live_generation_job(job_id)

    thread = threading.Thread(target=_worker, daemon=True)
    thread.start()
    return {"job_id": job_id, "status": "started"}

@app.post("/api/qwen3/generate")
async def qwen3_generate(request: Qwen3Request, http_request: Request):
    """Generate speech using Qwen3-TTS.

    Supports two modes:
    - clone: Voice cloning from reference audio (requires voice_name)
    - custom: Preset speaker voices (requires speaker)
    """
    try:
        if request.enqueue:
            return _queue_qwen3_job(request, http_request)

        result, output_path = _run_qwen3_generation(request)
        _log_generation_event(
            http_request,
            engine="qwen3",
            mode=request.mode,
            text=request.text,
            output_path=output_path,
            voice=request.voice_name if request.mode == "clone" else None,
            speaker=request.speaker if request.mode == "custom" else None,
            language=request.language,
            model_name=_qwen3_model_name_for_request(
                request.mode, request.model_size, request.model_quantization
            ),
        )
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
async def qwen3_generate_stream(request: Qwen3Request, http_request: Request):
    """Generate speech and stream raw PCM chunks as they are synthesized."""
    from fastapi.responses import StreamingResponse

    try:
        if request.model_quantization not in {"bf16", "8bit"}:
            raise HTTPException(
                status_code=400,
                detail="model_quantization must be 'bf16' or '8bit'",
            )
        _ensure_qwen3_model_ready(
            mode=request.mode,
            model_size=request.model_size,
            model_quantization=request.model_quantization,
        )

        params = GenerationParams(
            temperature=request.temperature,
            top_p=request.top_p,
            top_k=request.top_k,
            repetition_penalty=request.repetition_penalty,
            seed=request.seed,
        )
        prepared_ref_path: Optional[Path] = None

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
                    transcript = _safe_read_text(txt_file).strip()
                voice = {
                    "name": request.voice_name,
                    "audio_path": str(audio_file),
                    "transcript": transcript,
                }

            prepared_ref_path = _prepare_clone_reference_audio(
                voice["audio_path"],
                request.voice_name,
            )
            chunk_iter = engine.stream_voice_clone_pcm(
                text=request.text,
                ref_audio_path=str(prepared_ref_path),
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
                if prepared_ref_path is not None:
                    prepared_ref_path.unlink(missing_ok=True)
                if request.unload_after:
                    engine.unload()

        headers = {
            "X-Audio-Format": "pcm_s16le",
            "X-Audio-Sample-Rate": "24000",
            "X-Audio-Channels": "1",
        }
        _log_generation_event(
            http_request,
            engine="qwen3",
            mode=request.mode,
            text=request.text,
            streamed=True,
            voice=request.voice_name if request.mode == "clone" else None,
            speaker=request.speaker if request.mode == "custom" else None,
            language=request.language,
            model_name=_qwen3_model_name_for_request(
                request.mode, request.model_size, request.model_quantization
            ),
        )
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
    transcript: Optional[str] = Form(""),
):
    """Upload a new voice sample for Qwen3 cloning.

    Requires:
    - Audio file (WAV, 3+ seconds recommended)
    """
    name = name.strip()
    if not name or "/" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid voice name")
    if _is_shared_default_voice(name):
        raise HTTPException(
            status_code=400,
            detail="That name is reserved for default voices"
        )

    try:
        QWEN3_USER_VOICES_DIR.mkdir(parents=True, exist_ok=True)
        outputs_dir.mkdir(parents=True, exist_ok=True)
        safe_tag = _safe_tag(name, fallback="voice")
        temp_path = outputs_dir / f"temp-{safe_tag}-{uuid.uuid4().hex[:8]}.wav"
        with open(temp_path, "wb") as f:
            shutil.copyfileobj(file.file, f)

        final_audio = QWEN3_USER_VOICES_DIR / f"{name}.wav"
        final_transcript = QWEN3_USER_VOICES_DIR / f"{name}.txt"
        duration_sec = _decode_and_normalize_uploaded_voice(temp_path, final_audio)
        transcript_text = (transcript or "").strip()
        final_transcript.write_text(transcript_text, encoding="utf-8")
        temp_path.unlink(missing_ok=True)
        audio_url = f"/api/qwen3/voices/{quote(name)}/audio"

        voice_info = {
            "name": name,
            "audio_path": str(final_audio),
            "audio_url": audio_url,
            "transcript": transcript_text,
            "source": "user",
            "duration_sec": round(duration_sec, 3),
        }

        try:
            engine = get_qwen3_engine()
            engine.clear_cache()
        except ImportError:
            pass

        return {
            "message": f"Voice '{name}' saved successfully",
            "voice": voice_info,
        }
    except HTTPException:
        raise
    except Exception as e:
        temp_path = locals().get("temp_path")
        if isinstance(temp_path, Path):
            temp_path.unlink(missing_ok=True)
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
        "transcript": transcript or (_safe_read_text(new_transcript) if new_transcript.exists() else ""),
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
async def chatterbox_generate(request: ChatterboxRequest, http_request: Request):
    """Generate speech using Chatterbox voice cloning."""
    try:
        _ensure_named_model_ready("Chatterbox Multilingual", engine_label="Chatterbox")
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

        _log_generation_event(
            http_request,
            engine="chatterbox",
            mode="clone",
            text=request.text,
            output_path=output_path,
            voice=request.voice_name,
            language=request.language,
            model_name="Chatterbox Multilingual",
        )
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
        "transcript": transcript or (_safe_read_text(new_transcript) if new_transcript.exists() else ""),
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
async def indextts2_generate(request: IndexTTS2Request, http_request: Request):
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

        _log_generation_event(
            http_request,
            engine="indextts2",
            mode="clone",
            text=request.text,
            output_path=output_path,
            voice=request.voice_name,
            model_name="IndexTTS-2",
        )
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
        "transcript": transcript or (_safe_read_text(new_transcript) if new_transcript.exists() else ""),
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

# Track active downloads:
# key (repo/name) -> {"status": "downloading"/"completed"/"failed", "error": str|None, "path": str|None}
_download_status: dict[str, dict] = {}
_download_status_lock = threading.Lock()


def _download_key_for_model(model) -> str:
    """Use HuggingFace repo as the canonical download key when available."""
    hf_repo = (getattr(model, "hf_repo", "") or "").strip()
    if hf_repo:
        return f"hf:{hf_repo}"
    return f"name:{getattr(model, 'name', '')}"


def _download_status_for_model(model) -> Optional[dict]:
    """Return download status for a model, with backward compatibility for old keys."""
    key = _download_key_for_model(model)
    with _download_status_lock:
        status_info = _download_status.get(key)
        if status_info is None:
            # Backward compatibility with old name-keyed status entries.
            status_info = _download_status.get(getattr(model, "name", ""))
    return status_info


@app.get("/api/models/status")
async def models_status():
    """Check which models are downloaded and their sizes."""
    registry = ModelRegistry()
    models = []
    for m in registry.list_all_models():
        snapshot_path = registry.get_downloaded_snapshot_path(m)
        downloaded = snapshot_path is not None
        cache_dir = registry.get_model_cache_dir(m)
        status_info = _download_status_for_model(m)
        status_path = status_info.get("path") if status_info else None
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
            "cache_dir": str(cache_dir),
            "downloaded_path": status_path or (str(snapshot_path) if snapshot_path else None),
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

    download_key = _download_key_for_model(model)

    # Check if already downloading
    with _download_status_lock:
        current = _download_status.get(download_key) or _download_status.get(model_name)
    if current and current.get("status") == "downloading":
        return {
            "message": "Download already in progress",
            "model": model_name,
            "cache_dir": str(registry.get_model_cache_dir(model)),
            "downloaded_path": current.get("path"),
        }

    with _download_status_lock:
        _download_status[download_key] = {"status": "downloading", "error": None, "path": None}
        # Keep legacy name-key in sync if present, but do not rely on it.
        if model_name in _download_status:
            del _download_status[model_name]

    def _do_download():
        try:
            from huggingface_hub import snapshot_download
            snapshot_path = snapshot_download(model.hf_repo)
            with _download_status_lock:
                _download_status[download_key] = {
                    "status": "completed",
                    "error": None,
                    "path": str(snapshot_path),
                }
        except Exception as e:
            with _download_status_lock:
                _download_status[download_key] = {
                    "status": "failed",
                    "error": str(e),
                    "path": None,
                }

    thread = threading.Thread(target=_do_download, daemon=True)
    thread.start()

    return {
        "message": f"Download started for {model_name}",
        "model": model_name,
        "hf_repo": model.hf_repo,
        "size_gb": model.size_gb,
        "cache_dir": str(registry.get_model_cache_dir(model)),
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
    cache_dir = registry.get_model_cache_dir(model)
    if cache_dir.exists():
        import shutil
        try:
            shutil.rmtree(cache_dir)
            # Clear download status if any
            download_key = _download_key_for_model(model)
            with _download_status_lock:
                if download_key in _download_status:
                    del _download_status[download_key]
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


def _audiobook_job_to_history_item(job) -> dict:
    timestamp = datetime.utcfromtimestamp(job.started_at).isoformat() + "Z"
    return {
        "id": job.job_id,
        "type": "audiobook",
        "engine": "kokoro",
        "mode": "audiobook",
        "status": job.status.value,
        "title": job.title or f"Audiobook {job.job_id}",
        "chars": job.total_chars,
        "voice": job.voice,
        "speaker": None,
        "language": "en",
        "model": "Kokoro",
        "streamed": False,
        "output_path": str(job.audio_path) if job.audio_path else None,
        "audio_url": f"/audio/{job.audio_path.name}" if job.audio_path else None,
        "request_id": None,
        "timestamp": timestamp,
        "percent": job.percent,
        "current_chunk": job.current_chunk,
        "total_chunks": job.total_chunks,
        "eta_seconds": round(job.eta_seconds, 1),
    }


@app.get("/api/jobs")
async def jobs_list(limit: int = 200):
    """List recent generation jobs across TTS, voice-clone, and audiobook flows."""
    safe_limit = max(1, min(limit, 1000))
    items = _snapshot_live_generation_jobs()
    with _job_history_lock:
        items.extend(list(_job_history))

    # Merge live audiobook job state so running/queued progress appears in Jobs UI.
    try:
        from tts.audiobook import list_jobs as _list_audiobook_jobs

        for job in _list_audiobook_jobs():
            items.insert(0, _audiobook_job_to_history_item(job))
    except Exception:
        # Jobs endpoint should still work even if audiobook runtime is unavailable.
        pass

    # Deduplicate by id (prefer latest inserted entry), then sort descending timestamp.
    deduped: dict[str, dict] = {}
    for item in items:
        item_id = str(item.get("id") or "")
        if item_id and item_id not in deduped:
            deduped[item_id] = item

    sorted_items = sorted(
        deduped.values(),
        key=lambda x: str(x.get("timestamp") or ""),
        reverse=True,
    )
    return {"jobs": sorted_items[:safe_limit], "total": len(sorted_items)}


@app.get("/api/jobs/{job_id}")
async def jobs_get(job_id: str):
    """Return one job by id, searching live queue first and history second."""
    with _live_generation_jobs_lock:
        live_item = _live_generation_jobs.get(job_id)
    if live_item is not None:
        return {"job": live_item}

    with _job_history_lock:
        for item in _job_history:
            if str(item.get("id") or "") == job_id:
                return {"job": item}

    try:
        from tts.audiobook import get_job as _get_audiobook_job

        book_job = _get_audiobook_job(job_id)
        if book_job is not None:
            return {"job": _audiobook_job_to_history_item(book_job)}
    except Exception:
        pass

    raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")


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
async def audiobook_generate(request: AudiobookRequest, http_request: Request):
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
        output_dir=outputs_dir,
    )
    _record_job_event(
        http_request,
        engine="kokoro",
        mode="audiobook",
        status=job.status.value,
        text=request.text,
        voice=request.voice,
        model_name="Kokoro",
        job_type="audiobook",
        job_id=job.job_id,
        title=request.title,
    )
    _log_job_queue_action(
        action="enqueue",
        job_id=job.job_id,
        engine="kokoro",
        mode="audiobook",
        request_id=getattr(http_request.state, "request_id", "-"),
        status=job.status.value,
        title=request.title,
        details=f"chars={job.total_chars}",
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
    http_request: Request,
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
            output_dir=outputs_dir,
        )
        _record_job_event(
            http_request,
            engine="kokoro",
            mode="audiobook",
            status=job.status.value,
            text=f"Uploaded file: {file.filename or 'document'}",
            voice=voice,
            model_name="Kokoro",
            job_type="audiobook",
            job_id=job.job_id,
            title=job.title,
        )
        _log_job_queue_action(
            action="enqueue",
            job_id=job.job_id,
            engine="kokoro",
            mode="audiobook",
            request_id=getattr(http_request.state, "request_id", "-"),
            status=job.status.value,
            title=job.title,
            details=f"file={file.filename or 'document'} chars={job.total_chars}",
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
async def audiobook_cancel(job_id: str, http_request: Request):
    """Cancel an in-progress audiobook generation job."""
    from tts.audiobook import cancel_job, get_job

    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")

    success = cancel_job(job_id)
    if success:
        _log_job_queue_action(
            action="cancel",
            job_id=job_id,
            engine="kokoro",
            mode="audiobook",
            request_id=getattr(http_request.state, "request_id", "-"),
            status="cancelled",
            title=job.title,
        )
        return {"message": "Cancellation requested", "job_id": job_id}
    else:
        _log_job_queue_action(
            action="cancel_ignored",
            job_id=job_id,
            engine="kokoro",
            mode="audiobook",
            request_id=getattr(http_request.state, "request_id", "-"),
            status=job.status.value,
            title=job.title,
            details="already completed/failed",
        )
        return {"message": "Job cannot be cancelled (already completed or failed)", "job_id": job_id}


@app.get("/api/audiobook/list")
async def audiobook_list():
    """List all generated audiobooks (WAV, MP3, and M4B)."""
    from datetime import datetime

    audiobooks = []
    audiobook_pattern = "audiobook-"

    # Primary output folder and legacy folder used by older audiobook code paths.
    scan_dirs: list[Path] = [outputs_dir]
    legacy_outputs_dir = _backend_dir / "outputs"
    if legacy_outputs_dir.exists():
        try:
            if legacy_outputs_dir.resolve() != outputs_dir.resolve():
                scan_dirs.append(legacy_outputs_dir)
        except OSError:
            scan_dirs.append(legacy_outputs_dir)

    seen_filenames: set[str] = set()

    # Search for WAV, MP3, and M4B files.
    for ext in ["wav", "mp3", "m4b"]:
        for scan_dir in scan_dirs:
            for source_file in scan_dir.glob(f"{audiobook_pattern}*.{ext}"):
                file = source_file
                # Migrate legacy files into the active /audio folder so URLs resolve.
                if scan_dir != outputs_dir:
                    migrated = outputs_dir / source_file.name
                    if not migrated.exists():
                        try:
                            shutil.copy2(source_file, migrated)
                        except Exception:
                            logger.warning(
                                "Failed to migrate legacy audiobook '%s' to '%s'",
                                source_file,
                                migrated,
                            )
                    if migrated.exists():
                        file = migrated

                if file.name in seen_filenames:
                    continue
                seen_filenames.add(file.name)

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


# ============== Supertonic Audio Library Endpoints ==============

@app.get("/api/supertonic/audio/list")
async def supertonic_audio_list():
    """List all generated Supertonic audio files."""
    from datetime import datetime

    audio_files = []
    for file in outputs_dir.glob("supertonic-*.wav"):
        stat = file.stat()
        stem = file.stem
        parts = stem.split("-")
        voice = parts[1] if len(parts) > 2 else "unknown"

        try:
            info = sf.info(str(file))
            duration_seconds = info.duration
        except Exception:
            duration_seconds = 0

        audio_files.append(
            {
                "id": stem,
                "filename": file.name,
                "engine": "supertonic",
                "voice": voice,
                "label": f"Supertonic {voice}",
                "audio_url": f"/audio/{file.name}",
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "duration_seconds": round(duration_seconds, 1),
                "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
            }
        )

    audio_files.sort(key=lambda x: x["created_at"], reverse=True)
    return {"audio_files": audio_files, "total": len(audio_files)}


@app.delete("/api/supertonic/audio/{filename}")
async def supertonic_audio_delete(filename: str):
    """Delete a Supertonic audio file."""
    if not filename.startswith("supertonic-") or not filename.endswith(".wav"):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = outputs_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Audio file '{filename}' not found")

    file_path.unlink()
    return {"message": "Audio file deleted", "filename": filename}


# ============== CosyVoice3 Audio Library Endpoints ==============

@app.get("/api/cosyvoice3/audio/list")
async def cosyvoice3_audio_list():
    """List all generated CosyVoice3 audio files."""
    from datetime import datetime

    audio_files = []
    for file in outputs_dir.glob("cosyvoice3-*.wav"):
        stat = file.stat()
        stem = file.stem
        parts = stem.split("-")
        alias = parts[1] if len(parts) > 2 else COSYVOICE3_DEFAULT_VOICE

        try:
            info = sf.info(str(file))
            duration_seconds = info.duration
        except Exception:
            duration_seconds = 0

        audio_files.append(
            {
                "id": stem,
                "filename": file.name,
                "engine": "cosyvoice3",
                "voice": alias,
                "label": f"CosyVoice3 {alias}",
                "audio_url": f"/audio/{file.name}",
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "duration_seconds": round(duration_seconds, 1),
                "created_at": datetime.fromtimestamp(stat.st_ctime).isoformat(),
            }
        )

    audio_files.sort(key=lambda x: x["created_at"], reverse=True)
    return {"audio_files": audio_files, "total": len(audio_files)}


@app.delete("/api/cosyvoice3/audio/{filename}")
async def cosyvoice3_audio_delete(filename: str):
    """Delete a CosyVoice3 audio file."""
    if not filename.startswith("cosyvoice3-") or not filename.endswith(".wav"):
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
                "file_path": str(file.resolve()),
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
pregen_dir = _bundled_data_dir / "pregenerated"
if not pregen_dir.exists():
    pregen_dir = _ensure_dir_with_fallback(
        _runtime_data_dir / "pregenerated",
        _runtime_home / "pregenerated",
    )
app.mount(
    "/pregenerated",
    SafeStaticFiles(directory=str(pregen_dir)),
    name="pregenerated",
)

# Mount samples directory for pre-recorded voice samples
samples_dir = _bundled_data_dir / "samples"
if not samples_dir.exists():
    samples_dir = _ensure_dir_with_fallback(
        _runtime_data_dir / "samples",
        _runtime_home / "samples",
    )
app.mount("/samples", SafeStaticFiles(directory=str(samples_dir)), name="samples")

# Mount PDF directory for serving documents
pdf_dir = _env_path("MIMIKA_PDF_DIR")
if pdf_dir is None:
    pdf_dir = _bundled_data_dir / "pdf"
if not pdf_dir.exists():
    pdf_dir = _ensure_dir_with_fallback(
        pdf_dir,
        _runtime_data_dir / "pdf",
    )
app.mount("/pdf", SafeStaticFiles(directory=str(pdf_dir)), name="pdf")


@app.get("/api/pdf/list")
async def list_pdfs():
    """List available PDF/TXT/MD/DOCX/EPUB documents in the documents directory."""
    docs = []
    for ext in ("*.pdf", "*.txt", "*.md", "*.docx", "*.epub"):
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
    """Extract normalized text from an uploaded document for read-aloud."""
    filename = (file.filename or "").lower()
    supported_extensions = (".pdf", ".txt", ".md", ".docx", ".epub")
    ext = Path(filename).suffix.lower() if filename else ".pdf"
    if ext not in supported_extensions:
        raise HTTPException(
            status_code=400,
            detail="Supported files: PDF, TXT, MD, DOCX, EPUB",
        )

    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=400, detail="Uploaded document is empty")

    temp_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as temp_file:
            temp_file.write(payload)
            temp_path = temp_file.name

        if ext == ".pdf":
            from tts.audiobook import extract_pdf_with_toc

            text, _chapters = extract_pdf_with_toc(temp_path)
        elif ext == ".epub":
            from tts.audiobook import extract_epub_chapters

            text, _chapters = extract_epub_chapters(temp_path)
        elif ext == ".docx":
            from tts.audiobook import extract_docx_text

            text = extract_docx_text(temp_path)
        elif ext == ".md":
            from tts.audiobook import strip_markdown_for_read_aloud

            markdown_text = payload.decode("utf-8", errors="replace")
            text = strip_markdown_for_read_aloud(markdown_text)
        else:  # .txt
            text = payload.decode("utf-8", errors="replace")

        normalized = _normalize_pdf_text_for_tts(text)
        return {
            "text": normalized,
            "chars": len(normalized),
            "type": ext.lstrip("."),
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to extract document text: {exc}",
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
    path = _output_folder_from_env_or_settings()
    active_path = str(_sync_output_folder_runtime(path))
    return {"path": active_path}

@app.put("/api/settings/output-folder")
async def api_set_output_folder(path: str):
    """Set the output folder path."""
    env_output_override = _env_path("MIMIKA_OUTPUT_DIR")
    if env_output_override is not None:
        active_path = str(_sync_output_folder_runtime(str(env_output_override)))
        return {
            "success": False,
            "path": active_path,
            "message": "Output folder is fixed by MIMIKA_OUTPUT_DIR in this runtime.",
        }

    normalized = (path or "").strip()
    if not normalized:
        raise HTTPException(status_code=400, detail="Output folder path cannot be empty")
    try:
        success = set_output_folder(normalized)
        active_path = str(_sync_output_folder_runtime(normalized))
        return {"success": success, "path": active_path}
    except OSError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Unable to set output folder: {exc}",
        ) from exc

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
    try:
        set_setting(request.key, request.value)
        response = {"key": request.key, "value": request.value}
        if request.key == "output_folder":
            response["path"] = str(_sync_output_folder_runtime(_output_folder_from_env_or_settings()))
        return response
    except OSError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Unable to persist setting '{request.key}': {exc}",
        ) from exc


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=BACKEND_HOST, port=BACKEND_PORT)
