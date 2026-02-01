#!/usr/bin/env python3
"""MimikaStudio MCP Server - Exposes TTS functionality to Codex CLI.

Provides MCP tools for:
- Generating TTS audio (Kokoro, Qwen3, Chatterbox)
- Listing available voices
- Voice management (upload, delete, update, preview)
- Audiobook generation and management
- Audio library management
- System information and monitoring
- LLM configuration
- IPA generation
"""
import sys
import os
import json
import argparse
import logging
import atexit
import io
import uuid
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer
from logging.handlers import RotatingFileHandler

SERVER_NAME = "mimikastudio-mcp"
SERVER_VERSION = "2.0.0"

# Resolve paths
SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
BACKEND_DIR = ROOT_DIR / "backend"
LOG_DIR = ROOT_DIR / "runs" / "logs"

# Add backend to path for imports
sys.path.insert(0, str(BACKEND_DIR))

def _setup_logging():
    try:
        level = os.environ.get("LOG_LEVEL", "INFO").upper()
        logger = logging.getLogger(SERVER_NAME)
        logger.setLevel(getattr(logging, level, logging.INFO))

        # stderr handler
        sh = logging.StreamHandler(sys.stderr)
        sh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(sh)

        # file handler
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        fh = RotatingFileHandler(
            LOG_DIR / "tts_mcp_server.log",
            maxBytes=5*1024*1024,
            backupCount=3,
            encoding="utf-8"
        )
        fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(fh)

        logger.info("Logger initialized")
        return logger
    except Exception:
        return logging.getLogger(SERVER_NAME)

LOGGER = _setup_logging()

# Backend API URL
BACKEND_URL = os.environ.get("MIMIKASTUDIO_BACKEND_URL", "http://localhost:8000")

def _call_backend(endpoint: str, method: str = "GET", data: dict = None, timeout: int = 60) -> dict:
    """Call the MimikaStudio backend API."""
    import urllib.request
    import urllib.error

    url = f"{BACKEND_URL}{endpoint}"

    try:
        if method == "POST" and data:
            req = urllib.request.Request(
                url,
                data=json.dumps(data).encode('utf-8'),
                headers={"Content-Type": "application/json"},
                method="POST"
            )
        elif method in ("DELETE", "PUT"):
            if data:
                req = urllib.request.Request(
                    url,
                    data=json.dumps(data).encode('utf-8'),
                    headers={"Content-Type": "application/json"},
                    method=method
                )
            else:
                req = urllib.request.Request(url, method=method)
        elif method == "POST" and data is None:
            # POST with no body
            req = urllib.request.Request(
                url,
                data=b'',
                headers={"Content-Type": "application/json"},
                method="POST"
            )
        else:
            req = urllib.request.Request(url)

        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.URLError as e:
        LOGGER.error(f"Backend call failed: {e}")
        raise Exception(f"Backend unavailable: {e}")
    except Exception as e:
        LOGGER.error(f"Backend error: {e}")
        raise


def _call_backend_upload(endpoint: str, fields: dict, files: dict, timeout: int = 300) -> dict:
    """Call the MimikaStudio backend API with multipart/form-data upload.

    Args:
        endpoint: API endpoint path
        fields: Dict of form field name -> value (strings)
        files: Dict of form field name -> (filename, file_bytes, content_type)
        timeout: Request timeout in seconds
    """
    import urllib.request
    import urllib.error

    url = f"{BACKEND_URL}{endpoint}"
    boundary = f"----MCPBoundary{uuid.uuid4().hex}"

    body = io.BytesIO()

    # Add form fields
    for key, value in fields.items():
        body.write(f"--{boundary}\r\n".encode('utf-8'))
        body.write(f'Content-Disposition: form-data; name="{key}"\r\n'.encode('utf-8'))
        body.write(b'\r\n')
        body.write(str(value).encode('utf-8'))
        body.write(b'\r\n')

    # Add file fields
    for key, (filename, file_bytes, content_type) in files.items():
        body.write(f"--{boundary}\r\n".encode('utf-8'))
        body.write(f'Content-Disposition: form-data; name="{key}"; filename="{filename}"\r\n'.encode('utf-8'))
        body.write(f'Content-Type: {content_type}\r\n'.encode('utf-8'))
        body.write(b'\r\n')
        body.write(file_bytes)
        body.write(b'\r\n')

    body.write(f"--{boundary}--\r\n".encode('utf-8'))
    body_bytes = body.getvalue()

    try:
        req = urllib.request.Request(
            url,
            data=body_bytes,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Content-Length": str(len(body_bytes)),
            },
            method="POST"
        )

        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.URLError as e:
        LOGGER.error(f"Backend upload failed: {e}")
        raise Exception(f"Backend unavailable: {e}")
    except Exception as e:
        LOGGER.error(f"Backend upload error: {e}")
        raise


# MCP Tool definitions
MCP_TOOLS = [
    # ==================== Existing Tools (unchanged) ====================
    {
        "name": "tts_generate_kokoro",
        "description": "Generate speech using Kokoro TTS (fast, high quality). Returns audio file path.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to convert to speech"},
                "voice": {"type": "string", "description": "Voice name (e.g., 'af_heart', 'am_michael')"},
                "speed": {"type": "number", "description": "Speech speed (0.5-2.0, default 1.0)"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "tts_generate_qwen3",
        "description": "Generate speech using Qwen3-TTS voice cloning (3-second samples, 10 languages).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to convert to speech"},
                "voice_name": {"type": "string", "description": "Voice sample name"},
                "language": {"type": "string", "description": "Language (e.g., 'English', 'Chinese', 'Japanese')"},
                "speed": {"type": "number", "description": "Speech speed (0.5-2.0, default 1.0)"}
            },
            "required": ["text", "voice_name"]
        }
    },
    {
        "name": "tts_list_voices",
        "description": "List available voices for a TTS engine.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "engine": {"type": "string", "enum": ["kokoro", "qwen3"], "description": "TTS engine"}
            },
            "required": ["engine"]
        }
    },
    {
        "name": "tts_system_info",
        "description": "Get MimikaStudio system information (device, models, status).",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "tts_system_stats",
        "description": "Get system resource usage (CPU, RAM, GPU).",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== System ====================
    {
        "name": "health_check",
        "description": "Check if the MimikaStudio backend is running and healthy.",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== Kokoro Audio Library ====================
    {
        "name": "kokoro_list_audio",
        "description": "List all generated Kokoro TTS audio files with metadata (voice, duration, size).",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "kokoro_delete_audio",
        "description": "Delete a specific Kokoro audio file by filename.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string", "description": "Filename to delete (e.g., 'kokoro-bf_emma-abc123.wav')"}
            },
            "required": ["filename"]
        }
    },

    # ==================== Qwen3 ====================
    {
        "name": "qwen3_generate_stream",
        "description": "Generate speech using Qwen3-TTS with streaming response. Returns the streaming URL since MCP cannot stream audio directly.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to convert to speech"},
                "mode": {"type": "string", "enum": ["clone", "custom"], "description": "Generation mode: 'clone' for voice cloning, 'custom' for preset speakers"},
                "voice_name": {"type": "string", "description": "Voice sample name (required for clone mode)"},
                "speaker": {"type": "string", "description": "Preset speaker name (required for custom mode)"},
                "style_instruction": {"type": "string", "description": "Style instruction for custom mode (e.g., 'Speak slowly and calmly')"},
                "model_size": {"type": "string", "enum": ["0.6B", "1.7B"], "description": "Model size (default: 0.6B)"},
                "language": {"type": "string", "description": "Language (default: Auto)"},
                "params": {
                    "type": "object",
                    "description": "Advanced generation parameters",
                    "properties": {
                        "temperature": {"type": "number"},
                        "top_p": {"type": "number"},
                        "top_k": {"type": "integer"},
                        "repetition_penalty": {"type": "number"},
                        "seed": {"type": "integer"}
                    }
                }
            },
            "required": ["text"]
        }
    },
    {
        "name": "qwen3_upload_voice",
        "description": "Upload a new voice sample for Qwen3 voice cloning. Requires a WAV audio file (3+ seconds recommended) and a transcript of what is said.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the WAV audio file to upload"},
                "name": {"type": "string", "description": "Name for the voice sample"},
                "transcript": {"type": "string", "description": "Transcript of what is said in the audio"}
            },
            "required": ["file_path", "name", "transcript"]
        }
    },
    {
        "name": "qwen3_delete_voice",
        "description": "Delete a Qwen3 voice sample by name.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Voice sample name to delete"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "qwen3_update_voice",
        "description": "Update a Qwen3 voice sample (rename or update transcript).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Current voice sample name"},
                "new_name": {"type": "string", "description": "New name for the voice (optional)"},
                "transcript": {"type": "string", "description": "New transcript (optional)"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "qwen3_preview_voice",
        "description": "Get the audio preview URL for a Qwen3 voice sample.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Voice sample name"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "qwen3_list_speakers",
        "description": "List available preset speakers for Qwen3 CustomVoice mode.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "qwen3_list_models",
        "description": "List available Qwen3-TTS models with their capabilities.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "qwen3_list_languages",
        "description": "List supported languages for Qwen3-TTS.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "qwen3_info",
        "description": "Get Qwen3-TTS model information (installed status, model details).",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "qwen3_clear_cache",
        "description": "Clear Qwen3 voice prompt cache and free memory.",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== Chatterbox ====================
    {
        "name": "chatterbox_generate",
        "description": "Generate speech using Chatterbox voice cloning.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to convert to speech"},
                "voice_name": {"type": "string", "description": "Voice sample name to clone"},
                "language": {"type": "string", "description": "Language code (default: 'en')"},
                "params": {
                    "type": "object",
                    "description": "Generation parameters",
                    "properties": {
                        "temperature": {"type": "number", "description": "Temperature (default: 0.8)"},
                        "cfg_weight": {"type": "number", "description": "CFG weight (default: 1.0)"},
                        "exaggeration": {"type": "number", "description": "Exaggeration (default: 0.5)"},
                        "seed": {"type": "integer", "description": "Random seed (-1 for random)"}
                    }
                }
            },
            "required": ["text", "voice_name"]
        }
    },
    {
        "name": "chatterbox_list_voices",
        "description": "List available voice samples for Chatterbox cloning.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "chatterbox_upload_voice",
        "description": "Upload a new voice sample for Chatterbox voice cloning.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the WAV audio file to upload"},
                "name": {"type": "string", "description": "Name for the voice sample"},
                "transcript": {"type": "string", "description": "Transcript of what is said in the audio (optional)"}
            },
            "required": ["file_path", "name"]
        }
    },
    {
        "name": "chatterbox_preview_voice",
        "description": "Get the audio preview URL for a Chatterbox voice sample.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Voice sample name"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "chatterbox_delete_voice",
        "description": "Delete a Chatterbox voice sample by name.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Voice sample name to delete"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "chatterbox_update_voice",
        "description": "Update a Chatterbox voice sample (rename or update transcript).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Current voice sample name"},
                "new_name": {"type": "string", "description": "New name for the voice (optional)"},
                "transcript": {"type": "string", "description": "New transcript (optional)"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "chatterbox_list_languages",
        "description": "List supported languages for Chatterbox TTS.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "chatterbox_info",
        "description": "Get Chatterbox model information (installed status, model details).",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== Unified ====================
    {
        "name": "list_all_custom_voices",
        "description": "List all custom voice samples across all engines (Qwen3, Chatterbox).",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== Audiobook ====================
    {
        "name": "audiobook_generate",
        "description": "Start audiobook generation from text. Returns a job_id for tracking progress. Supports WAV, MP3, M4B output and SRT/VTT subtitles.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Document text to convert to audiobook"},
                "title": {"type": "string", "description": "Audiobook title (default: 'Untitled')"},
                "voice": {"type": "string", "description": "Kokoro voice ID (default: 'bf_emma')"},
                "speed": {"type": "number", "description": "Playback speed (default: 1.0)"},
                "output_format": {"type": "string", "enum": ["wav", "mp3", "m4b"], "description": "Output format (default: 'wav')"},
                "subtitle_format": {"type": "string", "enum": ["none", "srt", "vtt"], "description": "Subtitle format (default: 'none')"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "audiobook_generate_from_file",
        "description": "Start audiobook generation from an uploaded file (PDF, EPUB, TXT, MD, DOCX). Returns a job_id for tracking progress.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the document file to convert"},
                "title": {"type": "string", "description": "Audiobook title (defaults to filename)"},
                "voice": {"type": "string", "description": "Kokoro voice ID (default: 'bf_emma')"},
                "speed": {"type": "number", "description": "Playback speed (default: 1.0)"},
                "output_format": {"type": "string", "enum": ["wav", "mp3", "m4b"], "description": "Output format (default: 'wav')"}
            },
            "required": ["file_path"]
        }
    },
    {
        "name": "audiobook_status",
        "description": "Get the status of an audiobook generation job including progress, ETA, and character processing speed.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "job_id": {"type": "string", "description": "Job ID returned from audiobook_generate"}
            },
            "required": ["job_id"]
        }
    },
    {
        "name": "audiobook_cancel",
        "description": "Cancel an in-progress audiobook generation job.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "job_id": {"type": "string", "description": "Job ID to cancel"}
            },
            "required": ["job_id"]
        }
    },
    {
        "name": "audiobook_list",
        "description": "List all generated audiobooks (WAV, MP3, M4B) with metadata.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "audiobook_delete",
        "description": "Delete an audiobook by job_id (removes WAV, MP3, and M4B files).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "job_id": {"type": "string", "description": "Job ID of the audiobook to delete"}
            },
            "required": ["job_id"]
        }
    },

    # ==================== Audio Library ====================
    {
        "name": "tts_audio_list",
        "description": "List all generated Kokoro TTS audio files with metadata.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "tts_audio_delete",
        "description": "Delete a Kokoro TTS audio file by filename.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string", "description": "Filename to delete (e.g., 'kokoro-bf_emma-abc123.wav')"}
            },
            "required": ["filename"]
        }
    },
    {
        "name": "voice_clone_audio_list",
        "description": "List all generated voice clone audio files (Qwen3 and Chatterbox).",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "voice_clone_audio_delete",
        "description": "Delete a voice clone audio file by filename.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string", "description": "Filename to delete (e.g., 'qwen3-Natasha-abc123.wav')"}
            },
            "required": ["filename"]
        }
    },

    # ==================== Samples ====================
    {
        "name": "list_samples",
        "description": "Get sample texts for a specific TTS engine.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "engine": {"type": "string", "description": "Engine name (e.g., 'kokoro')"}
            },
            "required": ["engine"]
        }
    },
    {
        "name": "list_pregenerated",
        "description": "List pregenerated audio samples for instant playback.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "list_voice_samples",
        "description": "List pre-generated voice sample sentences with audio URLs.",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== LLM Config ====================
    {
        "name": "llm_get_config",
        "description": "Get current LLM configuration (provider, model, available providers).",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "llm_set_config",
        "description": "Update LLM configuration (provider, model, API key, base URL).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "provider": {"type": "string", "description": "LLM provider name"},
                "model": {"type": "string", "description": "Model name"},
                "api_key": {"type": "string", "description": "API key (optional)"},
                "base_url": {"type": "string", "description": "API base URL (optional, for custom endpoints)"}
            },
            "required": ["provider", "model"]
        }
    },
    {
        "name": "llm_list_ollama_models",
        "description": "Get list of locally available Ollama models.",
        "inputSchema": {"type": "object", "properties": {}}
    },

    # ==================== IPA ====================
    {
        "name": "ipa_get_sample",
        "description": "Get the default sample text for IPA generation.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "ipa_list_samples",
        "description": "Get all saved Emma IPA sample texts with preloaded IPA transcriptions.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "ipa_generate",
        "description": "Generate IPA-like British transcription for given text using an LLM.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to transcribe to IPA"},
                "provider": {"type": "string", "description": "LLM provider (optional, uses configured default)"},
                "model": {"type": "string", "description": "LLM model (optional, uses configured default)"},
                "api_key": {"type": "string", "description": "API key override (optional)"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "ipa_get_pregenerated",
        "description": "Get pregenerated IPA sample with audio URL.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    {
        "name": "ipa_save_output",
        "description": "Save a generated IPA output to history.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Original input text"},
                "transcription": {"type": "string", "description": "IPA transcription"},
                "provider": {"type": "string", "description": "LLM provider used"},
                "model": {"type": "string", "description": "LLM model used"}
            },
            "required": ["text", "transcription", "provider", "model"]
        }
    },
]


def handle_tool_call(name: str, arguments: dict) -> str:
    """Handle MCP tool calls."""
    LOGGER.info(f"Tool call: {name} with {arguments}")

    try:
        # ==================== Existing Tools (unchanged) ====================

        if name == "tts_generate_kokoro":
            text = arguments.get("text", "")
            voice = arguments.get("voice", "af_heart")
            speed = arguments.get("speed", 1.0)

            result = _call_backend("/api/kokoro/generate", "POST", {
                "text": text,
                "voice": voice,
                "speed": speed
            }, timeout=300)
            audio_url = f"{BACKEND_URL}{result['audio_url']}"
            return f"Audio generated: {audio_url}"

        elif name == "tts_generate_qwen3":
            text = arguments.get("text", "")
            voice_name = arguments.get("voice_name", "")
            language = arguments.get("language", "English")
            speed = arguments.get("speed", 1.0)

            result = _call_backend("/api/qwen3/generate", "POST", {
                "text": text,
                "voice_name": voice_name,
                "language": language,
                "speed": speed
            }, timeout=300)
            audio_url = f"{BACKEND_URL}{result['audio_url']}"
            return f"Audio generated: {audio_url}"

        elif name == "tts_list_voices":
            engine = arguments.get("engine", "kokoro")

            if engine == "kokoro":
                result = _call_backend("/api/kokoro/voices")
                voices = result.get("voices", [])
                voice_list = [
                    f"{v.get('code', 'unknown')} ({v.get('name', '')})"
                    for v in voices
                ]
                return "Kokoro voices:\n" + "\n".join(voice_list[:20])  # Limit output

            elif engine == "qwen3":
                result = _call_backend("/api/qwen3/voices")
                voices = result.get("voices", [])
                voice_list = [f"{v['name']} (source: {v.get('source', 'unknown')})" for v in voices]
                return "Qwen3 voices:\n" + "\n".join(voice_list)

            return f"Unknown engine: {engine}"

        elif name == "tts_system_info":
            result = _call_backend("/api/system/info")
            return json.dumps(result, indent=2)

        elif name == "tts_system_stats":
            result = _call_backend("/api/system/stats")
            cpu = result.get("cpu_percent", 0)
            ram_used = result.get("ram_used_gb", 0)
            ram_total = result.get("ram_total_gb", 0)
            gpu = result.get("gpu")

            stats = f"CPU: {cpu}%\nRAM: {ram_used:.1f}/{ram_total:.0f} GB"
            if gpu:
                stats += f"\nGPU: {gpu.get('name', 'Unknown')}"
                if gpu.get('memory_used_gb'):
                    stats += f" ({gpu['memory_used_gb']:.1f}/{gpu['memory_total_gb']:.0f} GB)"
            return stats

        # ==================== System ====================

        elif name == "health_check":
            result = _call_backend("/api/health")
            return json.dumps(result, indent=2)

        # ==================== Kokoro Audio Library ====================

        elif name == "kokoro_list_audio":
            result = _call_backend("/api/kokoro/audio/list")
            files = result.get("audio_files", [])
            if not files:
                return "No Kokoro audio files found."
            lines = [f"Kokoro audio files ({result.get('total', len(files))}):\n"]
            for f in files:
                lines.append(
                    f"  {f['filename']} | voice: {f.get('voice', '?')} | "
                    f"{f.get('duration_seconds', 0):.1f}s | {f.get('size_mb', 0):.2f}MB | "
                    f"{f.get('created_at', '')}"
                )
            return "\n".join(lines)

        elif name == "kokoro_delete_audio":
            filename = arguments.get("filename", "")
            result = _call_backend(f"/api/kokoro/audio/{filename}", "DELETE")
            return result.get("message", json.dumps(result))

        # ==================== Qwen3 ====================

        elif name == "qwen3_generate_stream":
            # MCP cannot stream audio; return the streaming URL for the client to use directly
            text = arguments.get("text", "")
            mode = arguments.get("mode", "clone")
            voice_name = arguments.get("voice_name")
            speaker = arguments.get("speaker")
            style_instruction = arguments.get("style_instruction")
            model_size = arguments.get("model_size", "0.6B")
            language = arguments.get("language", "Auto")
            params = arguments.get("params", {})

            payload = {
                "text": text,
                "mode": mode,
                "language": language,
                "model_size": model_size,
            }
            if voice_name:
                payload["voice_name"] = voice_name
            if speaker:
                payload["speaker"] = speaker
            if style_instruction:
                payload["instruct"] = style_instruction
            if params.get("temperature") is not None:
                payload["temperature"] = params["temperature"]
            if params.get("top_p") is not None:
                payload["top_p"] = params["top_p"]
            if params.get("top_k") is not None:
                payload["top_k"] = params["top_k"]
            if params.get("repetition_penalty") is not None:
                payload["repetition_penalty"] = params["repetition_penalty"]
            if params.get("seed") is not None:
                payload["seed"] = params["seed"]

            stream_url = f"{BACKEND_URL}/api/qwen3/generate/stream"
            return (
                f"Streaming endpoint: {stream_url}\n"
                f"MCP cannot stream audio directly. Use this URL with a streaming HTTP client.\n"
                f"Payload: {json.dumps(payload, indent=2)}"
            )

        elif name == "qwen3_upload_voice":
            file_path = arguments.get("file_path", "")
            voice_name = arguments.get("name", "")
            transcript = arguments.get("transcript", "")

            path = Path(file_path)
            if not path.exists():
                return f"Error: File not found: {file_path}"

            with open(path, "rb") as f:
                file_bytes = f.read()

            result = _call_backend_upload(
                "/api/qwen3/voices",
                fields={"name": voice_name, "transcript": transcript},
                files={"file": (path.name, file_bytes, "audio/wav")},
            )
            return result.get("message", json.dumps(result))

        elif name == "qwen3_delete_voice":
            voice_name = arguments.get("name", "")
            result = _call_backend(f"/api/qwen3/voices/{voice_name}", "DELETE")
            return result.get("message", json.dumps(result))

        elif name == "qwen3_update_voice":
            voice_name = arguments.get("name", "")
            new_name = arguments.get("new_name")
            transcript = arguments.get("transcript")

            # The backend uses multipart form for PUT, so we use _call_backend_upload
            # but with PUT method. Since our helper only supports POST, we build
            # the form data manually for PUT.
            import urllib.request
            import urllib.error

            boundary = f"----MCPBoundary{uuid.uuid4().hex}"
            body = io.BytesIO()

            if new_name:
                body.write(f"--{boundary}\r\n".encode('utf-8'))
                body.write(b'Content-Disposition: form-data; name="new_name"\r\n')
                body.write(b'\r\n')
                body.write(new_name.encode('utf-8'))
                body.write(b'\r\n')

            if transcript is not None:
                body.write(f"--{boundary}\r\n".encode('utf-8'))
                body.write(b'Content-Disposition: form-data; name="transcript"\r\n')
                body.write(b'\r\n')
                body.write(transcript.encode('utf-8'))
                body.write(b'\r\n')

            body.write(f"--{boundary}--\r\n".encode('utf-8'))
            body_bytes = body.getvalue()

            url = f"{BACKEND_URL}/api/qwen3/voices/{voice_name}"
            req = urllib.request.Request(
                url,
                data=body_bytes,
                headers={
                    "Content-Type": f"multipart/form-data; boundary={boundary}",
                    "Content-Length": str(len(body_bytes)),
                },
                method="PUT"
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode('utf-8'))
            return result.get("message", json.dumps(result))

        elif name == "qwen3_preview_voice":
            voice_name = arguments.get("name", "")
            audio_url = f"{BACKEND_URL}/api/qwen3/voices/{voice_name}/audio"
            return f"Voice preview URL: {audio_url}"

        elif name == "qwen3_list_speakers":
            result = _call_backend("/api/qwen3/speakers")
            speakers = result.get("speakers", [])
            info = result.get("speaker_info", {})
            lines = ["Qwen3 preset speakers:\n"]
            for s in speakers:
                details = info.get(s, {})
                lang = details.get("language", "?")
                desc = details.get("description", "")
                lines.append(f"  {s} ({lang}) - {desc}")
            return "\n".join(lines)

        elif name == "qwen3_list_models":
            result = _call_backend("/api/qwen3/models")
            return json.dumps(result, indent=2)

        elif name == "qwen3_list_languages":
            result = _call_backend("/api/qwen3/languages")
            languages = result.get("languages", [])
            return "Supported languages: " + ", ".join(languages)

        elif name == "qwen3_info":
            result = _call_backend("/api/qwen3/info")
            return json.dumps(result, indent=2)

        elif name == "qwen3_clear_cache":
            result = _call_backend("/api/qwen3/clear-cache", "POST")
            return result.get("message", json.dumps(result))

        # ==================== Chatterbox ====================

        elif name == "chatterbox_generate":
            text = arguments.get("text", "")
            voice_name = arguments.get("voice_name", "")
            language = arguments.get("language", "en")
            params = arguments.get("params", {})

            payload = {
                "text": text,
                "voice_name": voice_name,
                "language": language,
            }
            if params.get("temperature") is not None:
                payload["temperature"] = params["temperature"]
            if params.get("cfg_weight") is not None:
                payload["cfg_weight"] = params["cfg_weight"]
            if params.get("exaggeration") is not None:
                payload["exaggeration"] = params["exaggeration"]
            if params.get("seed") is not None:
                payload["seed"] = params["seed"]

            result = _call_backend("/api/chatterbox/generate", "POST", payload, timeout=300)
            audio_url = f"{BACKEND_URL}{result['audio_url']}"
            return f"Audio generated: {audio_url}\nFilename: {result.get('filename', '')}\nVoice: {result.get('voice', '')}"

        elif name == "chatterbox_list_voices":
            result = _call_backend("/api/chatterbox/voices")
            voices = result.get("voices", [])
            if not voices:
                error = result.get("error", "")
                return f"No Chatterbox voices found.{' ' + error if error else ''}"
            lines = ["Chatterbox voices:\n"]
            for v in voices:
                lines.append(f"  {v['name']} (source: {v.get('source', 'unknown')})")
            return "\n".join(lines)

        elif name == "chatterbox_upload_voice":
            file_path = arguments.get("file_path", "")
            voice_name = arguments.get("name", "")
            transcript = arguments.get("transcript", "")

            path = Path(file_path)
            if not path.exists():
                return f"Error: File not found: {file_path}"

            with open(path, "rb") as f:
                file_bytes = f.read()

            fields = {"name": voice_name}
            if transcript:
                fields["transcript"] = transcript

            result = _call_backend_upload(
                "/api/chatterbox/voices",
                fields=fields,
                files={"file": (path.name, file_bytes, "audio/wav")},
            )
            return result.get("message", json.dumps(result))

        elif name == "chatterbox_preview_voice":
            voice_name = arguments.get("name", "")
            audio_url = f"{BACKEND_URL}/api/chatterbox/voices/{voice_name}/audio"
            return f"Voice preview URL: {audio_url}"

        elif name == "chatterbox_delete_voice":
            voice_name = arguments.get("name", "")
            result = _call_backend(f"/api/chatterbox/voices/{voice_name}", "DELETE")
            return result.get("message", json.dumps(result))

        elif name == "chatterbox_update_voice":
            voice_name = arguments.get("name", "")
            new_name = arguments.get("new_name")
            transcript = arguments.get("transcript")

            import urllib.request
            import urllib.error

            boundary = f"----MCPBoundary{uuid.uuid4().hex}"
            body = io.BytesIO()

            if new_name:
                body.write(f"--{boundary}\r\n".encode('utf-8'))
                body.write(b'Content-Disposition: form-data; name="new_name"\r\n')
                body.write(b'\r\n')
                body.write(new_name.encode('utf-8'))
                body.write(b'\r\n')

            if transcript is not None:
                body.write(f"--{boundary}\r\n".encode('utf-8'))
                body.write(b'Content-Disposition: form-data; name="transcript"\r\n')
                body.write(b'\r\n')
                body.write(transcript.encode('utf-8'))
                body.write(b'\r\n')

            body.write(f"--{boundary}--\r\n".encode('utf-8'))
            body_bytes = body.getvalue()

            url = f"{BACKEND_URL}/api/chatterbox/voices/{voice_name}"
            req = urllib.request.Request(
                url,
                data=body_bytes,
                headers={
                    "Content-Type": f"multipart/form-data; boundary={boundary}",
                    "Content-Length": str(len(body_bytes)),
                },
                method="PUT"
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode('utf-8'))
            return result.get("message", json.dumps(result))

        elif name == "chatterbox_list_languages":
            result = _call_backend("/api/chatterbox/languages")
            languages = result.get("languages", [])
            return "Supported languages: " + ", ".join(languages)

        elif name == "chatterbox_info":
            result = _call_backend("/api/chatterbox/info")
            return json.dumps(result, indent=2)

        # ==================== Unified ====================

        elif name == "list_all_custom_voices":
            result = _call_backend("/api/voices/custom")
            voices = result.get("voices", [])
            total = result.get("total", len(voices))
            if not voices:
                return "No custom voices found."
            lines = [f"Custom voices ({total}):\n"]
            for v in voices:
                lines.append(
                    f"  {v['name']} (engine: {v.get('source', '?')}) "
                    f"| transcript: {(v.get('transcript') or 'none')[:50]}"
                )
            return "\n".join(lines)

        # ==================== Audiobook ====================

        elif name == "audiobook_generate":
            text = arguments.get("text", "")
            payload = {"text": text}
            if arguments.get("title"):
                payload["title"] = arguments["title"]
            if arguments.get("voice"):
                payload["voice"] = arguments["voice"]
            if arguments.get("speed") is not None:
                payload["speed"] = arguments["speed"]
            if arguments.get("output_format"):
                payload["output_format"] = arguments["output_format"]
            if arguments.get("subtitle_format"):
                payload["subtitle_format"] = arguments["subtitle_format"]

            result = _call_backend("/api/audiobook/generate", "POST", payload, timeout=300)
            return (
                f"Audiobook generation started.\n"
                f"Job ID: {result.get('job_id', '?')}\n"
                f"Status: {result.get('status', '?')}\n"
                f"Total chunks: {result.get('total_chunks', '?')}\n"
                f"Total chars: {result.get('total_chars', '?')}\n"
                f"Output format: {result.get('output_format', '?')}\n"
                f"Use audiobook_status with this job_id to track progress."
            )

        elif name == "audiobook_generate_from_file":
            file_path = arguments.get("file_path", "")
            path = Path(file_path)
            if not path.exists():
                return f"Error: File not found: {file_path}"

            with open(path, "rb") as f:
                file_bytes = f.read()

            fields = {}
            if arguments.get("title"):
                fields["title"] = arguments["title"]
            if arguments.get("voice"):
                fields["voice"] = arguments["voice"]
            if arguments.get("speed") is not None:
                fields["speed"] = str(arguments["speed"])
            if arguments.get("output_format"):
                fields["output_format"] = arguments["output_format"]

            # Determine content type from extension
            ext = path.suffix.lower()
            content_types = {
                ".pdf": "application/pdf",
                ".epub": "application/epub+zip",
                ".txt": "text/plain",
                ".md": "text/markdown",
                ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            }
            content_type = content_types.get(ext, "application/octet-stream")

            result = _call_backend_upload(
                "/api/audiobook/generate-from-file",
                fields=fields,
                files={"file": (path.name, file_bytes, content_type)},
                timeout=300,
            )
            return (
                f"Audiobook generation started from file.\n"
                f"Job ID: {result.get('job_id', '?')}\n"
                f"Status: {result.get('status', '?')}\n"
                f"Total chunks: {result.get('total_chunks', '?')}\n"
                f"Chapters: {result.get('chapters', '?')}\n"
                f"Use audiobook_status with this job_id to track progress."
            )

        elif name == "audiobook_status":
            job_id = arguments.get("job_id", "")
            result = _call_backend(f"/api/audiobook/status/{job_id}")
            status = result.get("status", "unknown")
            lines = [
                f"Audiobook Job: {result.get('job_id', job_id)}",
                f"Status: {status}",
                f"Progress: {result.get('current_chunk', 0)}/{result.get('total_chunks', '?')} chunks ({result.get('percent', 0):.1f}%)",
                f"Processed: {result.get('processed_chars', 0)}/{result.get('total_chars', '?')} chars",
                f"Speed: {result.get('chars_per_sec', 0):.1f} chars/sec",
                f"Elapsed: {result.get('elapsed_seconds', 0):.1f}s",
                f"ETA: {result.get('eta_formatted', 'N/A')}",
            ]
            if status == "completed":
                audio_url = result.get("audio_url", "")
                lines.append(f"Audio URL: {BACKEND_URL}{audio_url}")
                lines.append(f"Duration: {result.get('duration_seconds', 0):.1f}s")
                lines.append(f"File size: {result.get('file_size_mb', 0):.2f} MB")
                if result.get("subtitle_url"):
                    lines.append(f"Subtitle URL: {BACKEND_URL}{result['subtitle_url']}")
            elif status == "failed":
                lines.append(f"Error: {result.get('error', 'Unknown error')}")
            return "\n".join(lines)

        elif name == "audiobook_cancel":
            job_id = arguments.get("job_id", "")
            result = _call_backend(f"/api/audiobook/cancel/{job_id}", "POST")
            return result.get("message", json.dumps(result))

        elif name == "audiobook_list":
            result = _call_backend("/api/audiobook/list")
            audiobooks = result.get("audiobooks", [])
            total = result.get("total", len(audiobooks))
            if not audiobooks:
                return "No audiobooks found."
            lines = [f"Audiobooks ({total}):\n"]
            for ab in audiobooks:
                lines.append(
                    f"  {ab['filename']} | format: {ab.get('format', '?')} | "
                    f"{ab.get('duration_seconds', 0):.1f}s | {ab.get('size_mb', 0):.2f}MB | "
                    f"{ab.get('created_at', '')}"
                )
            return "\n".join(lines)

        elif name == "audiobook_delete":
            job_id = arguments.get("job_id", "")
            result = _call_backend(f"/api/audiobook/{job_id}", "DELETE")
            return result.get("message", json.dumps(result))

        # ==================== Audio Library ====================

        elif name == "tts_audio_list":
            result = _call_backend("/api/tts/audio/list")
            files = result.get("audio_files", [])
            total = result.get("total", len(files))
            if not files:
                return "No TTS audio files found."
            lines = [f"TTS audio files ({total}):\n"]
            for f in files:
                lines.append(
                    f"  {f['filename']} | engine: {f.get('engine', '?')} | voice: {f.get('voice', '?')} | "
                    f"{f.get('duration_seconds', 0):.1f}s | {f.get('size_mb', 0):.2f}MB"
                )
            return "\n".join(lines)

        elif name == "tts_audio_delete":
            filename = arguments.get("filename", "")
            result = _call_backend(f"/api/tts/audio/{filename}", "DELETE")
            return result.get("message", json.dumps(result))

        elif name == "voice_clone_audio_list":
            result = _call_backend("/api/voice-clone/audio/list")
            files = result.get("audio_files", [])
            total = result.get("total", len(files))
            if not files:
                return "No voice clone audio files found."
            lines = [f"Voice clone audio files ({total}):\n"]
            for f in files:
                lines.append(
                    f"  {f['filename']} | engine: {f.get('engine', '?')} | voice: {f.get('voice', '?')} | "
                    f"{f.get('duration_seconds', 0):.1f}s | {f.get('size_mb', 0):.2f}MB"
                )
            return "\n".join(lines)

        elif name == "voice_clone_audio_delete":
            filename = arguments.get("filename", "")
            result = _call_backend(f"/api/voice-clone/audio/{filename}", "DELETE")
            return result.get("message", json.dumps(result))

        # ==================== Samples ====================

        elif name == "list_samples":
            engine = arguments.get("engine", "kokoro")
            result = _call_backend(f"/api/samples/{engine}")
            samples = result.get("samples", [])
            if not samples:
                return f"No sample texts found for engine: {engine}"
            lines = [f"Sample texts for {engine} ({len(samples)}):\n"]
            for s in samples:
                text_preview = s.get("text", "")[:80]
                lines.append(f"  [{s.get('id', '?')}] {s.get('category', '?')} ({s.get('language', '?')}): {text_preview}...")
            return "\n".join(lines)

        elif name == "list_pregenerated":
            result = _call_backend("/api/pregenerated")
            samples = result.get("samples", [])
            if not samples:
                return "No pregenerated samples found."
            lines = [f"Pregenerated samples ({len(samples)}):\n"]
            for s in samples:
                audio_url = f"{BACKEND_URL}{s.get('audio_url', '')}"
                lines.append(
                    f"  [{s.get('id', '?')}] {s.get('title', '?')} | engine: {s.get('engine', '?')} | "
                    f"voice: {s.get('voice', '?')} | {audio_url}"
                )
            return "\n".join(lines)

        elif name == "list_voice_samples":
            result = _call_backend("/api/voice-samples")
            samples = result.get("samples", [])
            total = result.get("total", len(samples))
            if not samples:
                return "No voice samples found."
            lines = [f"Voice samples ({total}):\n"]
            for s in samples:
                audio_url = f"{BACKEND_URL}{s.get('audio_url', '')}"
                text_preview = s.get("text", "")[:60]
                lines.append(
                    f"  [{s.get('id', '?')}] {s.get('voice_name', '?')} ({s.get('voice_code', '?')}): "
                    f"{text_preview}... | {audio_url}"
                )
            return "\n".join(lines)

        # ==================== LLM Config ====================

        elif name == "llm_get_config":
            result = _call_backend("/api/llm/config")
            return json.dumps(result, indent=2)

        elif name == "llm_set_config":
            payload = {
                "provider": arguments.get("provider", ""),
                "model": arguments.get("model", ""),
            }
            if arguments.get("api_key"):
                payload["api_key"] = arguments["api_key"]
            if arguments.get("base_url"):
                payload["api_base"] = arguments["base_url"]

            result = _call_backend("/api/llm/config", "POST", payload)
            return result.get("message", json.dumps(result))

        elif name == "llm_list_ollama_models":
            result = _call_backend("/api/llm/ollama/models")
            models = result.get("models", [])
            available = result.get("available", False)
            if not available:
                error = result.get("error", "Ollama not available")
                return f"Ollama not available: {error}"
            if not models:
                return "No Ollama models found locally."
            return "Ollama models:\n" + "\n".join(f"  {m}" for m in models)

        # ==================== IPA ====================

        elif name == "ipa_get_sample":
            result = _call_backend("/api/ipa/sample")
            return result.get("text", json.dumps(result))

        elif name == "ipa_list_samples":
            result = _call_backend("/api/ipa/samples")
            samples = result.get("samples", [])
            if not samples:
                return "No IPA samples found."
            lines = [f"IPA samples ({len(samples)}):\n"]
            for s in samples:
                text_preview = s.get("input_text", "")[:60]
                has_ipa = "yes" if s.get("has_preloaded_ipa") else "no"
                has_audio = "yes" if s.get("has_audio") else "no"
                lines.append(
                    f"  [{s.get('id', '?')}] {s.get('title', '?')} | "
                    f"preloaded IPA: {has_ipa} | audio: {has_audio} | "
                    f"text: {text_preview}..."
                )
            return "\n".join(lines)

        elif name == "ipa_generate":
            text = arguments.get("text", "")
            payload = {"text": text}
            if arguments.get("provider"):
                payload["provider"] = arguments["provider"]
            if arguments.get("model"):
                payload["model"] = arguments["model"]

            result = _call_backend("/api/ipa/generate", "POST", payload, timeout=120)
            ipa = result.get("ipa", result.get("version1", ""))
            return f"IPA transcription:\n{ipa}\n\nOriginal text: {result.get('original_text', text)}"

        elif name == "ipa_get_pregenerated":
            result = _call_backend("/api/ipa/pregenerated")
            has_audio = result.get("has_audio", False)
            text = result.get("text", "")
            audio_url = f"{BACKEND_URL}{result['audio_url']}" if result.get("audio_url") else "N/A"
            return f"Text: {text}\nHas audio: {has_audio}\nAudio URL: {audio_url}"

        elif name == "ipa_save_output":
            text = arguments.get("text", "")
            transcription = arguments.get("transcription", "")
            provider = arguments.get("provider", "")
            model = arguments.get("model", "")

            # The backend endpoint uses query parameters, not JSON body
            import urllib.request
            import urllib.error
            import urllib.parse

            params = urllib.parse.urlencode({
                "input_text": text,
                "version1_ipa": transcription,
                "version2_ipa": transcription,
                "llm_provider": provider,
            })
            url = f"{BACKEND_URL}/api/ipa/save-output?{params}"
            req = urllib.request.Request(url, data=b'', method="POST")
            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode('utf-8'))
            return result.get("message", json.dumps(result))

        # ==================== Unknown ====================

        else:
            return f"Unknown tool: {name}"

    except Exception as e:
        LOGGER.error(f"Tool error: {e}")
        return f"Error: {e}"


class MCPHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[mcp] {fmt % args}\n")

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length).decode('utf-8') if length else "{}"

        try:
            obj = json.loads(raw)
        except Exception as e:
            LOGGER.warning(f"Parse error: {e}")
            self._write_json({
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Parse error: {e}"}
            })
            return

        mid = obj.get("id")
        method = obj.get("method")
        params = obj.get("params") or {}

        # Handle MCP methods
        if method == "initialize":
            proto = params.get("protocolVersion", "2024-11-05")
            LOGGER.info(f"Initialize request (proto={proto})")
            self._write_json({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "protocolVersion": proto,
                    "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                    "capabilities": {"tools": {"list": True, "call": True}}
                }
            })
            return

        if method in ("tools/list", "tools.list"):
            self._write_json({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {"tools": MCP_TOOLS}
            })
            return

        if method in ("tools/call", "tools.call"):
            name = params.get("name")
            arguments = params.get("arguments") or {}

            result = handle_tool_call(name, arguments)
            self._write_json({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {"content": [{"type": "text", "text": result}]}
            })
            return

        # Unknown method
        self._write_json({
            "jsonrpc": "2.0",
            "id": mid,
            "error": {"code": -32601, "message": f"Method not found: {method}"}
        })

    def _write_json(self, obj):
        data = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser(description="MimikaStudio MCP Server")
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind')
    parser.add_argument('--port', type=int, default=8010, help='Port to listen on')
    args = parser.parse_args()

    httpd = HTTPServer((args.host, args.port), MCPHandler)
    LOGGER.info(f"Starting {SERVER_NAME} on http://{args.host}:{args.port}")
    LOGGER.info(f"Registered {len(MCP_TOOLS)} tools")
    atexit.register(lambda: LOGGER.info(f"Stopping {SERVER_NAME}"))

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        LOGGER.info("Shutting down...")
        httpd.shutdown()


if __name__ == '__main__':
    main()
