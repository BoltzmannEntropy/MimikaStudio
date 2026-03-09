"""MimikaStudio version information."""

VERSION = "2026.03.5"
BUILD_NUMBER = 11
VERSION_NAME = "Voice Prompt Import Workflow and Pre-Production Hardening"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
