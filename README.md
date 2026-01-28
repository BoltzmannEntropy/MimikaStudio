<div align="center">
  <img src="assets/light-mode-logo.png" alt="MimikaStudio Logo" width="400"/>
  <br>
</div>

# MimikaStudio - Voice Cloning, TTS & PDF Reader

> **Custom Voice Cloning** • **Text-to-Speech** • **PDF Read Aloud**

A local-first desktop application with three core capabilities: **clone any voice** from just 3 seconds of audio, generate **high-quality text-to-speech** with multiple engines and premium voices, and **read PDFs aloud** with sentence-by-sentence highlighting.

> *I ported my old Gradio app into this beautiful native Flutter desktop application, specifically optimized for Apple Silicon users who want a polished, responsive UI with proper macOS integration.*

**MimikaStudio is the most comprehensive desktop application for voice cloning and text-to-speech synthesis.** Whether you want to clone your own voice from just 3 seconds of audio, use one of 9 premium preset speakers, or leverage fast high-quality TTS engines for narration and content creation - MimikaStudio has you covered.

![Qwen3-TTS Custom Voice Speakers](assets/04-qwen3-custom-voice.png)

## Why MimikaStudio?

MimikaStudio brings together the latest advances in neural text-to-speech into a beautiful, unified desktop experience:

### Lightning-Fast British TTS with Kokoro

Need instant, high-quality speech? **[Kokoro TTS](https://github.com/hexgrad/kokoro)** delivers sub-200ms latency with crystal-clear British and American accents. The 82M parameter model runs effortlessly on any machine, generating natural-sounding speech with Emma, George, Lily, and other premium voices. Perfect for real-time applications, PDF narration, and quick prototyping.

Kokoro also includes **Emma IPA** - a British phonetic transcription tool powered by your choice of LLM (Claude, OpenAI, Ollama). Generate IPA transcriptions to understand exactly how words should be pronounced in Received Pronunciation.

![Kokoro TTS with Emma IPA](assets/01-kokoro-tts-emma-ipa.png)

### Voice Cloning Without Limits

Clone any voice from remarkably short audio samples. Our **[Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)** integration requires just **3 seconds** of reference audio to capture a speaker's characteristics - their tone, rhythm, accent, and personality. Compare this to older systems that required 30+ seconds of clean recordings. Upload a voice memo, a podcast clip, or any audio snippet, and MimikaStudio will synthesize new speech in that voice.

### Premium Preset Speakers

Don't have reference audio? No problem. MimikaStudio includes **9 premium preset speakers** across 4 languages (English, Chinese, Japanese, Korean), each with distinct personalities - from the dynamic rhythm of Ryan to the warm emotional tones of Sohee. These CustomVoice speakers require no audio samples at all - just type your text and generate.

### Multiple State-of-the-Art Models

We've integrated the most capable open-source TTS models available:

| Model | Type | Strength |
|-------|------|----------|
| **[Kokoro-82M](https://github.com/hexgrad/kokoro)** | Fast TTS | Sub-200ms latency, British RP & American accents |
| **[Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 0.6B/1.7B Base** | Voice Cloning | 3-second cloning, 10 languages |
| **[Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 0.6B/1.7B CustomVoice** | Preset Speakers | 9 premium voices, style control |
| **XTTS2** | Multi-language Cloning | 16 languages, proven quality |

### Beyond Simple TTS

MimikaStudio isn't just a TTS engine wrapper:

- **Emma IPA Transcription**: Generate British IPA-like phonetic transcriptions using LLM providers (Claude, OpenAI, Ollama). Perfect for language learning and pronunciation guides.

- **PDF Reader with Voice**: Load any PDF from the `./pdf` directory and have it read aloud with sentence-by-sentence highlighting. Choose your preferred Kokoro voice, adjust speed, and let MimikaStudio narrate your documents.

![PDF Reader with TTS](assets/03-pdf-reader.png)

- **Unified Voice Library**: All your custom voice samples (XTTS and Qwen3) in one unified list. Upload once, use with either engine.

- **Advanced Generation Controls**: Fine-tune every aspect of synthesis with temperature, top_p, top_k, repetition penalty, and reproducible generation with seeds.

- **Style Instructions**: Tell the CustomVoice speakers *how* to speak - "whisper softly", "speak with excitement", "sound contemplative", or "Optimized for engaging, professional audiobook narration" - and watch the AI adapt.

- **Real-time System Monitoring**: CPU, RAM, and GPU usage displayed in the app header so you always know what resources your generations are consuming.

- **Multi-LLM Support**: Connect to Claude, OpenAI, Ollama (local), or Claude Code CLI for IPA generation and other AI features.

### Built for macOS, Ready for More

MimikaStudio has been **extensively tested on macOS** (both Intel and Apple Silicon). It's our primary platform, with careful attention to MPS acceleration where supported and graceful CPU fallback where needed. The architecture cleanly separates the **Flutter-based UI** from the **Python FastAPI backend**, making adaptation to Linux or Windows with CUDA straightforward.

### Production-Quality Codebase

This isn't a weekend hack:

- **Comprehensive test suite** with 11 test files covering health checks, API generation, voice management, model registry, streaming endpoints, and end-to-end workflows
- **MCP server integration** for programmatic access via Codex CLI
- **Clean CLI tool** (`mimikactl`) for service management, logs, and maintenance
- **Modular engine architecture** making it easy to add new TTS backends

---

## Features

- **Qwen3-TTS Voice Clone**: Clone any voice from just 3+ seconds of audio
- **Qwen3-TTS Custom Voice**: 9 preset premium speakers (Ryan, Aiden, Vivian, Serena, Uncle Fu, Dylan, Eric, Ono Anna, Sohee)
- **Advanced Generation Controls**: Temperature, top_p, top_k, repetition penalty, seed
- **Model Size Selection**: 0.6B (Fast) or 1.7B (Quality)
- **Kokoro TTS**: Fast, high-quality English synthesis with British/American voices
- **Emma IPA**: British phonetic transcription with multi-LLM support (Claude, OpenAI, Ollama)
- **XTTS2**: Multi-language voice cloning
- **Unified Voice Library**: Single voice list usable with both Qwen3 and XTTS engines
- **Document Reader**: Read PDFs, TXT, and MD files aloud with Kokoro TTS
- **CLI Tool**: Full command-line interface for all TTS engines
- **MCP Server**: Codex CLI integration for programmatic access

## Quick Start

```bash
# First time setup
cd /path/to/MimikaStudio
./bin/mimikactl db seed          # Initialize database
./bin/mimikactl models download  # Pre-download ML models (optional)

# Start all services (Backend + MCP + Flutter UI)
./bin/mimikactl up

# Or backend + MCP only (no Flutter)
./bin/mimikactl up --no-flutter

# Check status
./bin/mimikactl status

# View logs
./bin/mimikactl logs backend
```

## Control Script (mimikactl)

```bash
# Service Commands
./bin/mimikactl up                    # Start all services
./bin/mimikactl up --no-flutter       # Backend + MCP only
./bin/mimikactl down                  # Stop all services
./bin/mimikactl restart               # Restart all
./bin/mimikactl status                # Check status

# Backend Commands
./bin/mimikactl backend start         # Start backend only
./bin/mimikactl backend stop          # Stop backend

# Flutter Commands
./bin/mimikactl flutter start         # Start Flutter (release mode)
./bin/mimikactl flutter start --dev   # Start in dev mode
./bin/mimikactl flutter stop          # Stop Flutter
./bin/mimikactl flutter build         # Build macOS app

# MCP Server Commands
./bin/mimikactl mcp start             # Start MCP server (port 8010)
./bin/mimikactl mcp stop              # Stop MCP server
./bin/mimikactl mcp status            # Check MCP status

# Utility Commands
./bin/mimikactl logs [service]        # Tail logs (backend|mcp|flutter|all)
./bin/mimikactl test                  # Run API tests
./bin/mimikactl clean                 # Clean logs and temp files
./bin/mimikactl version               # Show version info
```

## CLI Tool (mimika)

Full command-line interface for voice cloning and TTS generation.

```bash
# Kokoro TTS (fast British/American voices)
./bin/mimika kokoro "Hello, world!" --voice bf_emma --output hello.wav
./bin/mimika kokoro input.txt --voice bm_george --speed 1.2

# Qwen3 Custom Voice (preset speakers)
./bin/mimika qwen3 "Hello, world!" --speaker Ryan --style "professional narration"
./bin/mimika qwen3 book.epub --speaker Sohee --output audiobook.wav

# Qwen3 Voice Clone (clone from reference audio)
./bin/mimika qwen3 "Hello, world!" --clone --reference voice.wav
./bin/mimika qwen3 book.pdf --clone --reference speaker.wav --output book.wav

# XTTS Voice Clone
./bin/mimika xtts "Hello, world!" --voice Natasha --language en

# List available voices
./bin/mimika voices --engine kokoro
./bin/mimika voices --engine qwen3
```

### Supported File Formats

| Format | Extension | Status |
|--------|-----------|--------|
| Plain Text | `.txt` | Full support |
| PDF | `.pdf` | Full support |
| EPUB | `.epub` | Full support |
| Word Document | `.docx` | Full support (requires python-docx) |
| Legacy Word | `.doc` | Full support (requires docx2txt) |
| Markdown | `.md` | Full support |

---

## [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)

### Voice Clone Mode (Base)

Clone any voice from just 3+ seconds of reference audio.

**Models**:
- `Qwen3-TTS-12Hz-0.6B-Base` - Fast, 1.4GB
- `Qwen3-TTS-12Hz-1.7B-Base` - Higher quality, 3.6GB

**Languages**: Chinese, English, Japanese, Korean, German, French, Russian, Portuguese, Spanish, Italian

**How It Works**:
1. Upload a 3+ second audio sample
2. (Optional) Provide transcript for better quality
3. Enter text to synthesize
4. Adjust generation parameters if needed
5. Generate!

### Custom Voice Mode (Preset Speakers)

Use 9 premium preset speakers without any reference audio.

**Models**:
- `Qwen3-TTS-12Hz-0.6B-CustomVoice`
- `Qwen3-TTS-12Hz-1.7B-CustomVoice`

| Speaker | Language | Character |
|---------|----------|-----------|
| Ryan | English | Dynamic male, strong rhythm |
| Aiden | English | Sunny American male |
| Vivian | Chinese | Bright young female |
| Serena | Chinese | Warm gentle female |
| Uncle_Fu | Chinese | Seasoned male, mellow timbre |
| Dylan | Chinese | Beijing youthful male |
| Eric | Chinese | Sichuan lively male |
| Ono_Anna | Japanese | Playful female |
| Sohee | Korean | Warm emotional female |

**Style Instructions**: Control tone with prompts like "Speak slowly", "Very happy", "Whisper", or use "Optimized for engaging, professional audiobook narration" for long-form content. See [Qwen3-Audiobook-Converter](https://github.com/WhiskeyCoder/Qwen3-Audiobook-Converter) for inspiration.

### Advanced Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Temperature | 0.9 | 0.1-2.0 | Randomness in generation |
| Top P | 0.9 | 0.1-1.0 | Nucleus sampling threshold |
| Top K | 50 | 1-100 | Top-k sampling |
| Repetition Penalty | 1.0 | 1.0-2.0 | Reduce repetition |
| Seed | -1 | -1 or 0+ | Reproducible generation (-1=random) |

![Qwen3-TTS with Advanced Parameters](assets/05-qwen3-advanced.png)

---

## Other Engines

### Kokoro TTS + Emma IPA

Fast, high-quality British English synthesis (82M parameters, 24kHz) with integrated IPA transcription.

**Emma IPA** generates British phonetic transcriptions using your choice of LLM provider:
- **Claude** (Anthropic) - claude-sonnet-4, claude-opus-4, claude-haiku-3
- **OpenAI** - gpt-4, gpt-4-turbo, gpt-3.5-turbo
- **Ollama** (Local) - Any locally installed model
- **Claude Code CLI** - Use your local Claude CLI

The IPA transcription highlights stress patterns and provides British RP pronunciation guides.

![Emma IPA Phonetic Transcription](assets/02-emma-ipa-transcription.png)

**Kokoro TTS** - Fast, high-quality English synthesis (82M parameters, 24kHz).

| Voice | Code | Gender | Accent |
|-------|------|--------|--------|
| Emma | bf_emma | Female | British RP |
| Heart | af_heart | Female | American |
| Michael | am_michael | Male | American |
| George | bm_george | Male | British |

### XTTS2 Voice Cloning

Multi-language voice cloning (requires 6-30 second reference audio).

**Supported Languages**: EN, ES, FR, DE, IT, PT, PL, TR, RU, NL, CS, AR, ZH, JA, HU, KO

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/system/info` | GET | System information |
| `/api/system/stats` | GET | CPU/RAM/GPU stats |
| `/api/voices/custom` | GET | Unified list of all custom voices (XTTS + Qwen3) |
| **Qwen3** |||
| `/api/qwen3/generate` | POST | Generate audio (clone or custom mode) |
| `/api/qwen3/generate/stream` | POST | Streaming audio generation |
| `/api/qwen3/voices` | GET | List saved voice samples |
| `/api/qwen3/voices` | POST | Upload new voice sample |
| `/api/qwen3/speakers` | GET | List preset speakers |
| `/api/qwen3/models` | GET | List available models |
| `/api/qwen3/languages` | GET | List supported languages |
| **Kokoro** |||
| `/api/kokoro/generate` | POST | Generate TTS audio |
| `/api/kokoro/voices` | GET | List available voices |
| **XTTS** |||
| `/api/xtts/generate` | POST | Generate cloned voice audio |
| `/api/xtts/voices` | GET/POST/DELETE | Voice management |
| **Emma IPA** |||
| `/api/ipa/samples` | GET | List IPA sample texts |
| `/api/ipa/generate` | POST | Generate British IPA transcription |
| `/api/ipa/pregenerated` | GET | Get pregenerated IPA with audio |
| **LLM Configuration** |||
| `/api/llm/config` | GET/POST | Get or update LLM provider settings |
| `/api/llm/ollama/models` | GET | List locally available Ollama models |

Full API documentation: http://localhost:8000/docs

---

## Architecture

```
MimikaStudio/
├── bin/
│   ├── mimikactl              # Control script
│   └── tts_mcp_server.py      # MCP server for Codex CLI
│
├── pdf/                       # Place PDFs here for the PDF Reader
│
├── flutter_app/               # macOS Flutter desktop application
│   ├── lib/
│   │   ├── main.dart          # App entry, tab navigation
│   │   ├── screens/
│   │   │   ├── quick_tts_screen.dart      # Kokoro TTS + Emma IPA
│   │   │   ├── voice_clone_screen.dart    # Qwen3 + XTTS
│   │   │   └── pdf_reader_screen.dart     # PDF reader with TTS
│   │   └── services/
│   │       └── api_service.dart           # Backend API client
│   └── macos/                             # macOS configuration
│
├── backend/                   # FastAPI Python backend
│   ├── main.py               # API endpoints
│   ├── tts/                  # TTS engine wrappers
│   │   ├── kokoro_engine.py
│   │   ├── xtts_engine.py
│   │   └── qwen3_engine.py   # Clone + CustomVoice
│   ├── language/             # Language processing
│   │   └── ipa_generator.py  # British IPA transcription
│   ├── llm/                  # LLM provider integration
│   │   └── factory.py        # Claude, OpenAI, Ollama support
│   ├── models/
│   │   └── registry.py       # Model registry
│   ├── tests/                # Test suite
│   └── data/
│       ├── samples/          # Voice samples
│       │   ├── voices/       # XTTS voice samples
│       │   ├── qwen3_voices/ # Qwen3 voice samples
│       │   └── kokoro/       # Pre-generated Kokoro samples
│       └── outputs/          # Generated audio files
│
└── docs/
    └── plans/                # Integration plans
```

---

## Requirements

- **Python 3.10+** with pip
- **Flutter 3.x** with macOS desktop support enabled
- **macOS 12+** for Flutter desktop
- **espeak-ng** for Kokoro phonemization (`brew install espeak-ng`)

**Optional**:
- **CUDA GPU** for faster inference (NVIDIA)
- **Apple Silicon** (M1/M2/M3) - uses MPS where supported, CPU fallback for Qwen3

## Installation

```bash
# Clone repository
cd /path/to/MimikaStudio

# Create Python venv and install dependencies
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Install Qwen3-TTS
pip install -U qwen-tts soundfile

# Initialize database
cd ..
./bin/mimikactl db seed

# Start services
./bin/mimikactl up
```

## Running Tests

```bash
cd backend
source venv/bin/activate
pytest tests/

# With model tests (slow, requires models downloaded)
RUN_MODEL_TESTS=1 pytest tests/
```

---

## Author

| | |
|---|---|
| 👨‍💻 **Author** | Shlomo Kashani |
| 🏫 **Affiliation** | Johns Hopkins University, Maryland, U.S.A. |

---

## Citation

If you use MimikaStudio in your research or projects, please cite this work:

```bibtex
@software{kashani2025mimikastudio,
  title={MimikaStudio: Local-First Voice Cloning and Text-to-Speech Desktop Application},
  author={Kashani, Shlomo},
  year={2025},
  institution={Johns Hopkins University},
  url={https://github.com/BoltzmannEntropy/MimikaStudio},
  note={Comprehensive desktop application integrating Qwen3-TTS, Kokoro, and XTTS2 for voice cloning and synthesis}
}
```

**APA Format:**

Kashani, S. (2025). *MimikaStudio: Local-First Voice Cloning and Text-to-Speech Desktop Application*. Johns Hopkins University. https://github.com/BoltzmannEntropy/MimikaStudio

**IEEE Format:**

S. Kashani, "MimikaStudio: Local-First Voice Cloning and Text-to-Speech Desktop Application," Johns Hopkins University, 2025. [Online]. Available: https://github.com/BoltzmannEntropy/MimikaStudio

---

## License

MIT License

## Acknowledgments

- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) - 3-second voice cloning with CustomVoice
- [Kokoro TTS](https://github.com/hexgrad/kokoro) - Fast, high-quality English TTS
- [Coqui TTS](https://github.com/coqui-ai/TTS) - XTTS2 voice cloning
- [Flutter](https://flutter.dev) - Cross-platform UI framework
- [FastAPI](https://fastapi.tiangolo.com) - Python API framework
