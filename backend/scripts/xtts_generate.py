#!/usr/bin/env python3
import json
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from tts.xtts_engine import get_xtts_engine


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        sys.stderr.write(f"Failed to read input JSON: {exc}\n")
        return 1

    text = payload.get("text", "")
    speaker_wav_path = payload.get("speaker_wav_path")
    language = payload.get("language", "English")
    speed = payload.get("speed", 0.8)

    if not text or not speaker_wav_path:
        sys.stderr.write("Missing required fields: text, speaker_wav_path\n")
        return 1

    engine = get_xtts_engine()
    # XTTS prints to stdout; redirect to stderr so stdout stays JSON-only.
    original_stdout = sys.stdout
    try:
        sys.stdout = sys.stderr
        output_path = engine.generate(
            text=text,
            speaker_wav_path=speaker_wav_path,
            language=language,
            speed=speed,
        )
    finally:
        sys.stdout = original_stdout

    sys.stdout.write(json.dumps({"output_path": str(output_path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
