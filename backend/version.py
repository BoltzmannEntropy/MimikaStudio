"""MimikaStudio version information."""

VERSION = "2026.03.11"
BUILD_NUMBER = 17
VERSION_NAME = "Fix First-Launch Backend Startup in DMG Releases"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
