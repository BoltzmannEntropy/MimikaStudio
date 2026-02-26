"""MimikaStudio version information."""

VERSION = "2026.02.7"
BUILD_NUMBER = 7
VERSION_NAME = "Audiobook Output + PDF Highlighting Fixes"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
