#!/usr/bin/env python3
"""
Generate long-form audiobook examples for MimikaStudio using Kokoro TTS.

Usage:
    cd MimikaCODE
    source venv/bin/activate
    python scripts/generate-long-audiobooks.py

This generates two audiobook demos:
- long-history-emma.mp3 (British female, Emma voice)
- long-history-george.mp3 (British male, George voice)

Using speed 0.95 for a natural, slightly slower reading pace.
"""

import os
import sys
import time
from pathlib import Path

# Add backend to path
SCRIPT_DIR = Path(__file__).parent.resolve()
BACKEND_DIR = SCRIPT_DIR.parent / "backend"
sys.path.insert(0, str(BACKEND_DIR))

# Max characters to process (keeps demos reasonable ~5 min each)
MAX_CHARS = 15000

# Voices to generate with
VOICES = [
    ("bf_emma", "long-history-emma"),
    ("bm_george", "long-history-george"),
]

# Speech speed (0.95 for natural, slightly slower)
SPEED = 0.95


def load_text() -> str:
    """Load the public domain text excerpt."""
    text_file = BACKEND_DIR / "data" / "texts" / "public_domain_history_wells_excerpt.txt"
    if not text_file.exists():
        print(f"Error: Text file not found: {text_file}")
        sys.exit(1)

    with open(text_file, "r", encoding="utf-8") as f:
        text = f.read()

    # Skip header lines and clean up
    lines = text.split("\n")
    content_lines = []
    in_content = False

    for line in lines:
        if line.startswith("---"):
            in_content = True
            continue
        if in_content:
            content_lines.append(line)

    content = "\n".join(content_lines).strip()

    # Truncate to MAX_CHARS
    if len(content) > MAX_CHARS:
        # Find a good break point (end of sentence)
        truncated = content[:MAX_CHARS]
        last_period = truncated.rfind(".")
        if last_period > MAX_CHARS * 0.8:
            truncated = truncated[:last_period + 1]
        content = truncated

    return content


def generate_audiobook(text: str, voice: str, output_name: str, speed: float = 1.0):
    """Generate an audiobook using Kokoro TTS."""
    import numpy as np
    import soundfile as sf
    import subprocess

    # Import Kokoro engine
    from tts.kokoro_engine import get_kokoro_engine

    output_dir = BACKEND_DIR / "data" / "pregenerated"
    output_dir.mkdir(parents=True, exist_ok=True)

    wav_path = output_dir / f"{output_name}.wav"
    mp3_path = output_dir / f"{output_name}.mp3"

    print(f"\n{'='*60}")
    print(f"Generating: {output_name}")
    print(f"Voice: {voice}, Speed: {speed}")
    print(f"Text length: {len(text)} characters")
    print(f"{'='*60}")

    start_time = time.time()

    # Get Kokoro engine
    engine = get_kokoro_engine()

    # Generate audio
    print("Loading model and generating audio...")
    audio, sample_rate = engine.generate_audio(text=text, voice=voice, speed=speed)

    if len(audio) == 0:
        print(f"Error: No audio generated for {output_name}")
        return None

    # Save WAV
    sf.write(str(wav_path), audio, sample_rate)

    elapsed = time.time() - start_time
    duration = len(audio) / sample_rate

    print(f"Generated {duration:.1f} seconds of audio in {elapsed:.1f} seconds")
    print(f"Saved WAV: {wav_path}")

    # Convert to MP3
    print("Converting to MP3...")
    try:
        subprocess.run([
            "ffmpeg", "-y", "-i", str(wav_path),
            "-codec:a", "libmp3lame", "-qscale:a", "2",
            str(mp3_path)
        ], check=True, capture_output=True)
        print(f"Saved MP3: {mp3_path}")

        # Remove WAV to save space
        wav_path.unlink()
        print("Removed intermediate WAV file")

    except subprocess.CalledProcessError as e:
        print(f"Warning: ffmpeg conversion failed: {e}")
        print("Keeping WAV file instead")
    except FileNotFoundError:
        print("Warning: ffmpeg not found, keeping WAV file")

    return mp3_path if mp3_path.exists() else wav_path


def main():
    print("MimikaStudio Long Audiobook Generator")
    print("=====================================")

    # Load text
    text = load_text()
    print(f"\nLoaded {len(text)} characters of text")

    # Generate for each voice
    generated = []
    for voice, output_name in VOICES:
        result = generate_audiobook(text, voice, output_name, speed=SPEED)
        if result:
            generated.append(result)

    print(f"\n{'='*60}")
    print("Generation Complete!")
    print(f"Generated {len(generated)} audiobook files:")
    for path in generated:
        size_mb = path.stat().st_size / (1024 * 1024)
        print(f"  - {path.name} ({size_mb:.1f} MB)")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
