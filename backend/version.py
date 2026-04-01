"""MimikaStudio version information."""

VERSION = "2026.04.1"
BUILD_NUMBER = 18
VERSION_NAME = "Disable Trial Expiration and Add PDF Preview"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
