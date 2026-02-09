"""MimikaStudio version information."""

VERSION = "2026.02.1"
BUILD_NUMBER = 1
VERSION_NAME = "Initial Release"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
