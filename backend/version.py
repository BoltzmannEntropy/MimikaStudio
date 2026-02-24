"""MimikaStudio version information."""

VERSION = "2026.02.4"
BUILD_NUMBER = 4
VERSION_NAME = "CosyVoice3 Separation + Jobs Queue"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
