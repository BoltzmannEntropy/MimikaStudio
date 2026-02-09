#!/usr/bin/env python3
"""Bump version across all MimikaStudio components."""

import re
import sys
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).parent.parent

def read_current_version():
    """Read current version from backend/version.py."""
    version_file = PROJECT_ROOT / "backend" / "version.py"
    content = version_file.read_text()
    match = re.search(r'VERSION = "(.+)"', content)
    if match:
        return match.group(1)
    raise ValueError("Could not find VERSION in version.py")

def bump_version(new_version: str, version_name: str = None):
    """Update version in all files."""

    # 1. Update backend/version.py
    backend_version = PROJECT_ROOT / "backend" / "version.py"
    content = backend_version.read_text()

    # Get current build number and increment
    build_match = re.search(r'BUILD_NUMBER = (\d+)', content)
    build_number = int(build_match.group(1)) + 1 if build_match else 1

    new_content = re.sub(r'VERSION = ".+"', f'VERSION = "{new_version}"', content)
    new_content = re.sub(r'BUILD_NUMBER = \d+', f'BUILD_NUMBER = {build_number}', new_content)
    if version_name:
        new_content = re.sub(r'VERSION_NAME = ".+"', f'VERSION_NAME = "{version_name}"', new_content)

    backend_version.write_text(new_content)
    print(f"Updated backend/version.py")

    # 2. Update flutter_app/lib/version.dart
    flutter_version = PROJECT_ROOT / "flutter_app" / "lib" / "version.dart"
    content = flutter_version.read_text()

    new_content = re.sub(r'const String appVersion = ".+";', f'const String appVersion = "{new_version}";', content)
    new_content = re.sub(r'const int buildNumber = \d+;', f'const int buildNumber = {build_number};', new_content)
    if version_name:
        new_content = re.sub(r'const String versionName = ".+";', f'const String versionName = "{version_name}";', new_content)

    flutter_version.write_text(new_content)
    print(f"Updated flutter_app/lib/version.dart")

    # 3. Update flutter_app/pubspec.yaml
    pubspec = PROJECT_ROOT / "flutter_app" / "pubspec.yaml"
    content = pubspec.read_text()

    new_content = re.sub(r'version: .+', f'version: {new_version}+{build_number}', content)

    pubspec.write_text(new_content)
    print(f"Updated flutter_app/pubspec.yaml")

    print(f"\nVersion bumped to {new_version} (build {build_number})")
    return new_version, build_number

def main():
    if len(sys.argv) < 2:
        current = read_current_version()
        print(f"Current version: {current}")
        print(f"\nUsage: {sys.argv[0]} <new_version> [version_name]")
        print(f"Example: {sys.argv[0]} 2026.02.2 'Bug fixes'")
        print(f"\nFor date-based versioning, use: YYYY.MM.N format")
        today = datetime.now()
        print(f"Suggested next version: {today.year}.{today.month:02d}.N")
        return

    new_version = sys.argv[1]
    version_name = sys.argv[2] if len(sys.argv) > 2 else None

    bump_version(new_version, version_name)

if __name__ == "__main__":
    main()
