#!/usr/bin/env python3
"""Compatibility entry point for the Mimika MCP server."""
from pathlib import Path
import os
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
TARGET = SCRIPT_DIR / "tts_mcp_server.py"

if not TARGET.exists():
    raise SystemExit(f"Missing target MCP server script: {TARGET}")

os.execv(sys.executable, [sys.executable, str(TARGET), *sys.argv[1:]])
