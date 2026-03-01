"""MimikaStudio version information."""

VERSION = "2026.03.2"
BUILD_NUMBER = 9
VERSION_NAME = "Kokoro Embedded Backend Crash Fix"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
