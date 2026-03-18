"""MimikaStudio version information."""

VERSION = "2026.03.7"
BUILD_NUMBER = 13
VERSION_NAME = "Fix Library Validation for Sandboxed Release Builds"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
