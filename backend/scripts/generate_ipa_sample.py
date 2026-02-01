#!/usr/bin/env python3
"""Generate the IPA sample audio using Lily voice."""
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from tts.kokoro_engine import get_kokoro_engine
from language.ipa_generator import get_sample_text

def main():
    sample_text = get_sample_text()
    print(f"Generating audio for sample text ({len(sample_text)} chars)...")
    print(f"Text: {sample_text[:100]}...")

    engine = get_kokoro_engine()

    # Generate with Lily voice (bf_lily)
    output_path = engine.generate(
        text=sample_text,
        voice="bf_lily",
        speed=1.0
    )

    # Copy to pregenerated directory
    pregen_dir = Path(__file__).parent.parent / "data" / "pregenerated"
    pregen_dir.mkdir(parents=True, exist_ok=True)

    dest_path = pregen_dir / "emma-ipa-lily-sample.wav"
    import shutil
    shutil.copy(output_path, dest_path)

    print(f"Generated: {dest_path}")
    print("Done!")

if __name__ == "__main__":
    main()
