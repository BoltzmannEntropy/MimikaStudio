#!/usr/bin/env python3
"""
Test All TTS Models
Runs all model tests and generates artifacts in runs/
"""

import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
RUNS_DIR = SCRIPTS_DIR.parent / "runs"

def run_test(script_name: str) -> bool:
    """Run a test script and return success status."""
    script_path = SCRIPTS_DIR / script_name
    print(f"\n{'='*60}")
    print(f"Running: {script_name}")
    print('='*60)

    try:
        result = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(SCRIPTS_DIR.parent / "backend"),
            capture_output=False
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error running {script_name}: {e}")
        return False

def main():
    print("=" * 60)
    print("MimikaStudio - Full Model Test Suite")
    print("=" * 60)

    # Create runs directory
    RUNS_DIR.mkdir(exist_ok=True)

    tests = [
        ("test_kokoro.py", "Kokoro TTS (British Voices)"),
    ]

    results = []
    for script, description in tests:
        print(f"\n>>> {description}")
        success = run_test(script)
        results.append((description, success))

    # Final summary
    print("\n" + "=" * 60)
    print("FINAL SUMMARY")
    print("=" * 60)

    for description, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"  [{status}] {description}")

    # List all generated artifacts
    print(f"\nGenerated artifacts in {RUNS_DIR}:")
    total_size = 0
    for subdir in sorted(RUNS_DIR.iterdir()):
        if subdir.is_dir():
            files = list(subdir.glob("*.wav"))
            dir_size = sum(f.stat().st_size for f in files)
            total_size += dir_size
            print(f"\n  {subdir.name}/ ({len(files)} files, {dir_size:,} bytes)")
            for f in sorted(files)[:5]:  # Show first 5
                print(f"    - {f.name}")
            if len(files) > 5:
                print(f"    ... and {len(files) - 5} more")

    print(f"\nTotal size: {total_size:,} bytes ({total_size / 1024 / 1024:.1f} MB)")

if __name__ == "__main__":
    main()
