"""MimikaStudio version information."""

VERSION = "2026.03.9"
BUILD_NUMBER = 15
VERSION_NAME = "Fix Long-Form Audiobook Startup Failures"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
