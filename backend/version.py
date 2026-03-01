"""MimikaStudio version information."""

VERSION = "2026.03.1"
BUILD_NUMBER = 8
VERSION_NAME = "Embedded Backend Startup Hardening"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
