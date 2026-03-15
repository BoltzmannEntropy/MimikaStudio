#!/usr/bin/env python3
"""
Generate long-form audiobook examples for MimikaStudio using Kokoro TTS.

Usage:
    cd MimikaCODE
    source venv/bin/activate
    python scripts/generate-long-audiobooks.py

This generates two audiobook demos:
- long-meditations-emma.mp3 (British female, Emma voice)
- long-meditations-george.mp3 (British male, George voice)

Using speed 0.95 for a natural, slightly slower reading pace.
"""

import os
import re
import sys
import time
from pathlib import Path

# Add backend to path
SCRIPT_DIR = Path(__file__).parent.resolve()
BACKEND_DIR = SCRIPT_DIR.parent / "backend"
sys.path.insert(0, str(BACKEND_DIR))

# Max characters to process (keeps demos long-form but practical to regenerate)
MAX_CHARS = 14000

# Voices to generate with
VOICES = [
    ("bf_emma", "long-meditations-emma"),
    ("bm_george", "long-meditations-george"),
]

# Speech speed (0.95 for natural, slightly slower)
SPEED = 0.95
TEXT_FILE = "public_domain_philosophy_meditations_excerpt.txt"


def _normalize_text(raw_text: str) -> str:
    raw_text = raw_text.replace("\ufeff", "").replace("\r\n", "\n").replace("\r", "\n")

    if "------------------------------------------------------------" in raw_text:
        raw_text = raw_text.split("------------------------------------------------------------", 1)[1]

    text = raw_text.strip()
    text = re.sub(r"_([^_]+)_", r"\1", text)
    text = text.replace("--", ", ")

    paragraphs = []
    for block in re.split(r"\n\s*\n+", text):
        block = block.strip()
        if not block:
            continue
        block = re.sub(r"\s*\n\s*", " ", block)
        block = re.sub(r"\s+", " ", block).strip()
        block = re.sub(r" (?=([IVXLCDM]{1,7}\.) [A-Z])", "\n\n", block)
        paragraphs.extend(part.strip() for part in block.split("\n\n") if part.strip())

    return "\n\n".join(paragraphs)


def _trim_to_sentence_boundary(text: str, max_chars: int) -> str:
    from tts.text_chunking import split_into_sentences

    sentences = split_into_sentences(text)
    selected = []
    total = 0

    for sentence in sentences:
        addition = len(sentence) + (1 if selected else 0)
        if total + addition > max_chars:
            break
        selected.append(sentence)
        total += addition

    return " ".join(selected).strip() if selected else text[:max_chars].strip()


def _validate_no_broken_words(text: str) -> None:
    suspicious_patterns = [
        r"\b[a-zA-Z]{1,20}-\s+[a-zA-Z]{2,20}\b",
        r"\b[a-zA-Z]{1,20}-\n[a-zA-Z]{2,20}\b",
    ]

    for pattern in suspicious_patterns:
        match = re.search(pattern, text)
        if match:
            raise ValueError(f"Suspicious split-word pattern found in source text: {match.group(0)!r}")


def load_text() -> str:
    """Load the public domain text excerpt."""
    text_file = BACKEND_DIR / "data" / "texts" / TEXT_FILE
    if not text_file.exists():
        print(f"Error: Text file not found: {text_file}")
        sys.exit(1)

    with open(text_file, "r", encoding="utf-8") as f:
        raw_text = f.read()

    content = _normalize_text(raw_text)
    content = _trim_to_sentence_boundary(content, MAX_CHARS)
    _validate_no_broken_words(content)
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
