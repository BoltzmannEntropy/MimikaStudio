#!/usr/bin/env python3
"""MimikaStudio MCP Server - Exposes TTS functionality to Codex CLI.

Provides MCP tools for:
- Generating TTS audio (Kokoro, Qwen3)
- Listing available voices
- System information
"""
import sys
import os
import json
import argparse
import logging
import atexit
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer
from logging.handlers import RotatingFileHandler

SERVER_NAME = "mimikastudio-mcp"
SERVER_VERSION = "1.0.0"

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

def _call_backend(endpoint: str, method: str = "GET", data: dict = None) -> dict:
    """Call the MimikaStudio backend API."""
    import urllib.request
    import urllib.error

    url = f"{BACKEND_URL}{endpoint}"

    try:
        if method == "POST" and data:
            req = urllib.request.Request(
                url,
                data=json.dumps(data).encode('utf-8'),
                headers={"Content-Type": "application/json"}
            )
        else:
            req = urllib.request.Request(url)

        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.URLError as e:
        LOGGER.error(f"Backend call failed: {e}")
        raise Exception(f"Backend unavailable: {e}")
    except Exception as e:
        LOGGER.error(f"Backend error: {e}")
        raise

# MCP Tool definitions
MCP_TOOLS = [
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
    }
]

def handle_tool_call(name: str, arguments: dict) -> str:
    """Handle MCP tool calls."""
    LOGGER.info(f"Tool call: {name} with {arguments}")

    try:
        if name == "tts_generate_kokoro":
            text = arguments.get("text", "")
            voice = arguments.get("voice", "af_heart")
            speed = arguments.get("speed", 1.0)

            result = _call_backend("/api/kokoro/generate", "POST", {
                "text": text,
                "voice": voice,
                "speed": speed
            })
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
            })
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
    atexit.register(lambda: LOGGER.info(f"Stopping {SERVER_NAME}"))

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        LOGGER.info("Shutting down...")
        httpd.shutdown()


if __name__ == '__main__':
    main()
