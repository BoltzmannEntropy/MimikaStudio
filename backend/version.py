"""MimikaStudio version information."""

VERSION = "2026.02.3"
BUILD_NUMBER = 3
VERSION_NAME = "Shutdown Reliability + Distribution Hardening"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
