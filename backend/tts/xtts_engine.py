import platform
import torch
from pathlib import Path
from TTS.api import TTS
import uuid
import html as html_module

# Language mapping for XTTS
LANGUAGES = {
    "Arabic": "ar",
    "Chinese": "zh-cn",
    "Czech": "cs",
    "Dutch": "nl",
    "English": "en",
    "French": "fr",
    "German": "de",
    "Hungarian": "hu",
    "Italian": "it",
    "Japanese": "ja",
    "Korean": "ko",
    "Polish": "pl",
    "Portuguese": "pt",
    "Russian": "ru",
    "Spanish": "es",
    "Turkish": "tr"
}

class XTTSEngine:
    def __init__(self):
        self.model = None
        self.device = None
        self.outputs_dir = Path(__file__).parent.parent / "outputs"
        self.outputs_dir.mkdir(parents=True, exist_ok=True)

    def _get_device(self):
        if platform.system() == 'Darwin':
            return torch.device('cpu')
        return torch.device('cuda:0' if torch.cuda.is_available() else 'cpu')

    def load_model(self):
        if self.model is None:
            self.device = self._get_device()
            self.model = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2").to(self.device)
            print(f"XTTS model loaded on {self.device}")
        return self.model

    def generate(self, text: str, speaker_wav_path: str, language: str = "English", speed: float = 0.8) -> Path:
        """Generate speech using voice cloning."""
        self.load_model()

        text = html_module.unescape(text)
        lang_code = LANGUAGES.get(language, "en")

        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        short_uuid = str(uuid.uuid4())[:8]
        output_file = self.outputs_dir / f"xtts-{short_uuid}.wav"

        self.model.tts_to_file(
            text=text,
            speed=speed,
            file_path=str(output_file),
            speaker_wav=[speaker_wav_path],
            language=lang_code
        )

        return output_file

    def get_languages(self) -> list:
        return list(LANGUAGES.keys())

# Singleton instance
_engine = None

def get_xtts_engine() -> XTTSEngine:
    global _engine
    if _engine is None:
        _engine = XTTSEngine()
    return _engine
