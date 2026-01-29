from pathlib import Path
from kokoro import KPipeline
import soundfile as sf
import uuid

# British voices from Kokoro-82M
BRITISH_VOICES = {
    "bf_emma": {"name": "Emma", "gender": "female", "grade": "B-"},
    "bf_alice": {"name": "Alice", "gender": "female", "grade": "D"},
    "bf_isabella": {"name": "Isabella", "gender": "female", "grade": "C"},
    "bf_lily": {"name": "Lily", "gender": "female", "grade": "D"},
    "bm_daniel": {"name": "Daniel", "gender": "male", "grade": "D"},
    "bm_fable": {"name": "Fable", "gender": "male", "grade": "C"},
    "bm_george": {"name": "George", "gender": "male", "grade": "C"},
    "bm_lewis": {"name": "Lewis", "gender": "male", "grade": "D+"},
}

DEFAULT_VOICE = "bm_george"

class KokoroEngine:
    def __init__(self):
        self.pipeline = None
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)

    def load_model(self):
        if self.pipeline is None:
            # 'b' for British English
            self.pipeline = KPipeline(lang_code='b')
            print("Kokoro model loaded for British English")
        return self.pipeline

    def generate(self, text: str, voice: str = DEFAULT_VOICE, speed: float = 1.0) -> Path:
        """Generate speech using predefined British voice."""
        self.load_model()

        if voice not in BRITISH_VOICES:
            voice = DEFAULT_VOICE

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"kokoro-{voice}-{short_uuid}.wav"

        # Generate audio
        generator = self.pipeline(text, voice=voice, speed=speed)

        # Kokoro returns a generator, we need to collect all audio chunks
        audio_chunks = []
        for i, (gs, ps, audio) in enumerate(generator):
            audio_chunks.append(audio)

        # Concatenate and save
        if audio_chunks:
            import numpy as np
            full_audio = np.concatenate(audio_chunks)
            sf.write(str(output_file), full_audio, 24000)

        return output_file

    def get_voices(self) -> dict:
        return BRITISH_VOICES

    def get_default_voice(self) -> str:
        return DEFAULT_VOICE

# Singleton instance
_engine = None

def get_kokoro_engine() -> KokoroEngine:
    global _engine
    if _engine is None:
        _engine = KokoroEngine()
    return _engine
