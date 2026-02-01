#!/usr/bin/env python3
"""Generate the preloaded Emma IPA sample audio using Kokoro Lily voice."""
import sys
from pathlib import Path

# Add backend to path
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir))

from tts.kokoro_engine import get_kokoro_engine
from language.ipa_generator import get_sample_text
import shutil

def main():
    print("Generating Emma IPA sample audio with Lily voice...")

    # Get sample text
    text = get_sample_text()
    print(f"Text length: {len(text)} characters")

    # Generate audio
    engine = get_kokoro_engine()
    output_path = engine.generate(
        text=text,
        voice="bf_lily",
        speed=1.0
    )

    # Move to pregenerated directory
    pregen_dir = backend_dir / "data" / "pregenerated"
    pregen_dir.mkdir(parents=True, exist_ok=True)

    target_path = pregen_dir / "emma-ipa-lily-sample.wav"
    shutil.move(str(output_path), str(target_path))

    print(f"Audio generated: {target_path}")
    print(f"File size: {target_path.stat().st_size / 1024:.1f} KB")

if __name__ == "__main__":
    main()
