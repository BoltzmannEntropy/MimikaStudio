#!/usr/bin/env python3
"""Generate voice sample audio files for Kokoro TTS demo."""

import sys
import shutil
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from tts.kokoro_engine import get_kokoro_engine

def main():
    """Generate voice sample audio files."""
    samples_dir = Path(__file__).parent.parent / "data" / "samples" / "kokoro"
    samples_dir.mkdir(parents=True, exist_ok=True)

    sentences = [
        ("This is not all that can be said, however. In so far as a specifically moral anthropology has to deal with the conditions that hinder or further the execution of the moral laws in human nature.", "bf_emma", "Emma"),
        ("Anthropology must be concerned with the sociological and even historical developments which are relevant to morality. In so far as pragmatic anthropology also deals with these questions, it is also relevant here.", "bm_george", "George"),
        ("The spread and strengthening of moral principles through the education in schools and in public, and also with the personal and public contexts of morality that are open to empirical observation.", "bf_lily", "Lily"),
    ]

    print("Loading Kokoro TTS engine...")
    engine = get_kokoro_engine()
    engine.load_model()

    for i, (text, voice_code, voice_name) in enumerate(sentences):
        final_path = samples_dir / f"sentence-{i+1:02d}-{voice_code}.wav"
        print(f"\nGenerating sample {i+1}/3: {voice_name} ({voice_code})")
        print(f"  Text: {text[:60]}...")

        try:
            # Generate returns a Path to the temp output
            temp_path = engine.generate(text, voice_code, speed=1.0)
            # Copy to the final location
            shutil.copy(temp_path, final_path)
            print(f"  Saved: {final_path}")
        except Exception as e:
            print(f"  Error: {e}")

    print("\nDone! Generated samples in:", samples_dir)

if __name__ == "__main__":
    main()
