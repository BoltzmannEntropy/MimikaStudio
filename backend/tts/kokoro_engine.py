from pathlib import Path
import threading
import uuid
import soundfile as sf
import numpy as np

try:
    from mlx_audio.tts import load as load_tts_model
except ImportError:
    load_tts_model = None

try:
    import mlx.core as mx
except Exception:  # pragma: no cover - fallback for non-MLX systems
    mx = None

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
        self.model = None
        self._generate_lock = threading.Lock()
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)

    def load_model(self):
        if self.model is None:
            if load_tts_model is None:
                raise ImportError("mlx-audio package not installed. Install with: pip install -U mlx-audio")
            self.model = load_tts_model("mlx-community/Kokoro-82M-bf16")
        return self.model

    def unload(self):
        self.model = None
        if mx is not None:
            mx.clear_cache()

    def generate(self, text: str, voice: str = DEFAULT_VOICE, speed: float = 1.0) -> Path:
        """Generate speech using predefined British voice."""
        audio, sample_rate = self.generate_audio(text=text, voice=voice, speed=speed)

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"kokoro-{voice}-{short_uuid}.wav"
        sf.write(str(output_file), audio, sample_rate)

        return output_file

    def generate_audio(self, text: str, voice: str = DEFAULT_VOICE, speed: float = 1.0):
        """Generate audio as a numpy array and sample rate."""
        self.load_model()

        if voice not in BRITISH_VOICES:
            voice = DEFAULT_VOICE

        audio_chunks = []
        sample_rate = 24000
        # mlx-audio Kokoro is not thread-safe under concurrent generation.
        with self._generate_lock:
            generator = self.model.generate(
                text=text,
                voice=voice,
                speed=speed,
                lang_code="b",
            )
            for result in generator:
                sample_rate = int(getattr(result, "sample_rate", sample_rate))
                audio_chunks.append(np.asarray(result.audio, dtype=np.float32).reshape(-1))
        if not audio_chunks:
            return np.array([], dtype=np.float32), 24000

        full_audio = np.concatenate(audio_chunks)
        return full_audio, sample_rate

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
