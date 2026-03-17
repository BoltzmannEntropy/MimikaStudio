"""MimikaStudio version information."""

VERSION = "2026.03.6"
BUILD_NUMBER = 12
VERSION_NAME = "Non-Blocking Generation and Voice Display Improvements"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
