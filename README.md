<div align="center">
  <img src="assets/light-mode-logo.png" alt="MimikaStudio Logo" width="400"/>
  <br>
</div>

# MimikaStudio - Voice Cloning, TTS & Audiobook Creator

> **Custom Voice Cloning** • **Text-to-Speech** • **PDF Read Aloud** • **Audiobook Creator**

A local-first desktop application with four core capabilities: **clone any voice** from just 3 seconds of audio, generate **high-quality text-to-speech** with multiple engines and premium voices, **read PDFs aloud** with sentence-by-sentence highlighting, and **convert documents to audiobooks** with your choice of voice.

> *I ported my old Gradio app into this beautiful native Flutter desktop application, specifically optimized for Apple Silicon users who want a polished, responsive UI with proper macOS integration.*

![MimikaStudio](assets/00-mimikastudio-hero.png)

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

- **Audiobook Creator**: Convert entire documents (PDF, EPUB, TXT, MD, DOCX) into audiobook files with a single click. The system uses **spaCy-based sentence tokenization** (like [audiblez](https://github.com/santinic/audiblez)) for intelligent text chunking, extracts chapters from PDF TOC or EPUB structure, and **skips headers/footers/page numbers** (like [pdf-narrator](https://github.com/mateogon/pdf-narrator)). **Supports WAV, MP3, and M4B (audiobook format with chapter markers) output.** Track progress in real-time with **character-based progress** (~60 chars/sec on M2 CPU), ETA estimation, and manage your audiobook library with full playback controls.

![PDF Reader & Audiobook Creator](assets/03-pdf-audiobook-creator.png)

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
- **Audiobook Creator**: Convert full documents to audiobook files (WAV/MP3) with progress tracking and playback controls
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

### Quick Examples

```bash
# Kokoro TTS (fast British/American voices)
./bin/mimika kokoro "Hello, world!" --voice bf_emma --output hello.wav
./bin/mimika kokoro input.txt --voice bm_george --speed 1.2

# Qwen3 Custom Voice (preset speakers)
./bin/mimika qwen3 "Hello, world!" --speaker Ryan --style "professional narration"
./bin/mimika qwen3 book.epub --speaker Sohee --output audiobook.wav

# Qwen3 Voice Clone (clone from reference audio)
./bin/mimika qwen3 "Hello, world!" --clone --reference Alina.wav
./bin/mimika qwen3 book.pdf --clone --reference Bella.wav --output book.wav

# XTTS Voice Clone
./bin/mimika xtts "Hello, world!" --voice Alina --language en
./bin/mimika xtts document.docx --voice Bella --output output.wav

# List available voices
./bin/mimika voices --engine kokoro
./bin/mimika voices --engine qwen3
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MIMIKA_API_URL` | `http://localhost:8000` | Backend API URL |

### Command Reference

#### `mimika kokoro` - Fast British/American TTS

Generate high-quality speech using Kokoro TTS (82M parameters, sub-200ms latency).

```bash
./bin/mimika kokoro <input> [options]
```

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `input` | | *required* | Text string or file path (.txt, .pdf, .epub, .docx, .doc) |
| `--voice` | `-v` | `bf_emma` | Voice ID (see `mimika voices --engine kokoro`) |
| `--speed` | `-s` | `1.0` | Speech speed multiplier (0.5-2.0) |
| `--output` | `-o` | `<input>.wav` | Output WAV file path |

**Available Kokoro Voices:**

| Voice ID | Name | Gender | Accent |
|----------|------|--------|--------|
| `bf_emma` | Emma | Female | British RP |
| `bf_isabella` | Isabella | Female | British |
| `bf_alice` | Alice | Female | British |
| `bf_lily` | Lily | Female | British |
| `bm_george` | George | Male | British |
| `bm_lewis` | Lewis | Male | British |
| `bm_daniel` | Daniel | Male | British |
| `af_heart` | Heart | Female | American |
| `af_bella` | Bella | Female | American |
| `af_nicole` | Nicole | Female | American |
| `af_aoede` | Aoede | Female | American |
| `af_kore` | Kore | Female | American |
| `af_sarah` | Sarah | Female | American |
| `af_sky` | Sky | Female | American |
| `am_michael` | Michael | Male | American |
| `am_adam` | Adam | Male | American |
| `am_echo` | Echo | Male | American |
| `am_liam` | Liam | Male | American |
| `am_onyx` | Onyx | Male | American |
| `am_puck` | Puck | Male | American |
| `am_santa` | Santa | Male | American |

**Examples:**

```bash
# Simple text-to-speech
./bin/mimika kokoro "Welcome to MimikaStudio!" --voice bf_emma

# Convert PDF to audiobook at 1.2x speed
./bin/mimika kokoro document.pdf --voice bm_george --speed 1.2 --output audiobook.wav

# Convert EPUB with American voice
./bin/mimika kokoro novel.epub --voice af_heart --output novel.wav
```

---

#### `mimika qwen3` - Voice Clone & Custom Voice

Generate speech using Qwen3-TTS with voice cloning or preset speakers.

```bash
./bin/mimika qwen3 <input> [options]
```

**Common Parameters:**

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `input` | | *required* | Text string or file path (.txt, .pdf, .epub, .docx, .doc) |
| `--output` | `-o` | `<input>.wav` | Output WAV file path |
| `--model` | `-m` | `1.7B` | Model size: `0.6B` (fast) or `1.7B` (quality) |
| `--language` | `-l` | `auto` | Language code (auto, en, zh, ja, ko, de, fr, ru, pt, es, it) |
| `--temperature` | | `0.9` | Generation randomness (0.1-2.0) |
| `--top-p` | | `0.9` | Nucleus sampling threshold (0.1-1.0) |
| `--top-k` | | `50` | Top-k sampling (1-100) |

**Custom Voice Mode (Preset Speakers):**

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `--speaker` | | `Ryan` | Preset speaker name |
| `--style` | | *see below* | Style instruction for voice |

Default style: `"Optimized for engaging, professional audiobook narration"`

**Available Preset Speakers:**

| Speaker | Language | Character |
|---------|----------|-----------|
| `Ryan` | English | Dynamic male, strong rhythm |
| `Aiden` | English | Sunny American male |
| `Vivian` | Chinese | Bright young female |
| `Serena` | Chinese | Warm gentle female |
| `Uncle_Fu` | Chinese | Seasoned male, mellow timbre |
| `Dylan` | Chinese | Beijing youthful male |
| `Eric` | Chinese | Sichuan lively male |
| `Ono_Anna` | Japanese | Playful female |
| `Sohee` | Korean | Warm emotional female |

**Voice Clone Mode:**

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `--clone` | | *flag* | Enable voice cloning mode |
| `--reference` | `-r` | *required* | Reference audio file (WAV, 3+ seconds) |
| `--reference-text` | | *optional* | Transcript of reference audio (improves quality) |

**Examples:**

```bash
# Custom Voice with preset speaker
./bin/mimika qwen3 "Hello, world!" --speaker Ryan --style "whisper softly"

# Professional audiobook narration
./bin/mimika qwen3 book.pdf --speaker Sohee --model 1.7B --output audiobook.wav

# Voice cloning from reference audio
./bin/mimika qwen3 "Hello!" --clone --reference Alina.wav

# Voice cloning with transcript (higher quality)
./bin/mimika qwen3 book.pdf --clone --reference speaker.wav \
    --reference-text "This is the transcript of my voice sample." \
    --output cloned_audiobook.wav

# Adjust generation parameters
./bin/mimika qwen3 "Testing parameters" --speaker Ryan \
    --temperature 0.7 --top-p 0.8 --top-k 40
```

---

#### `mimika xtts` - Multi-language Voice Cloning

Generate speech using XTTS2 with your saved voice samples.

```bash
./bin/mimika xtts <input> [options]
```

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `input` | | *required* | Text string or file path |
| `--voice` | `-v` | *required* | Voice name from your library |
| `--language` | `-l` | `en` | Language code |
| `--speed` | `-s` | `1.0` | Speech speed (0.5-2.0) |
| `--output` | `-o` | `<input>.wav` | Output WAV file path |

**Supported XTTS Languages:**

`en`, `es`, `fr`, `de`, `it`, `pt`, `pl`, `tr`, `ru`, `nl`, `cs`, `ar`, `zh`, `ja`, `hu`, `ko`

**Examples:**

```bash
# Generate with custom voice
./bin/mimika xtts "Bonjour le monde!" --voice Alina --language fr

# Convert document with speed adjustment
./bin/mimika xtts document.txt --voice Bella --speed 0.9 --output slow.wav
```

---

#### `mimika voices` - List Available Voices

List all available voices for a specific engine or all engines.

```bash
./bin/mimika voices [options]
```

| Parameter | Short | Default | Description |
|-----------|-------|---------|-------------|
| `--engine` | `-e` | *all* | Filter by engine: `kokoro`, `qwen3`, `xtts` |

**Examples:**

```bash
# List all voices across all engines
./bin/mimika voices

# List only Kokoro voices
./bin/mimika voices --engine kokoro

# List Qwen3 preset speakers
./bin/mimika voices --engine qwen3

# List your saved XTTS voice samples
./bin/mimika voices --engine xtts
```

---

### Supported File Formats

The CLI automatically extracts text from various document formats:

| Format | Extension | Requirements |
|--------|-----------|--------------|
| Plain Text | `.txt` | Built-in |
| PDF | `.pdf` | `PyPDF2` |
| EPUB | `.epub` | `ebooklib`, `beautifulsoup4` |
| Word Document | `.docx` | `python-docx` |
| Legacy Word | `.doc` | `docx2txt` |
| Markdown | `.md` | Built-in |

Install optional dependencies:

```bash
pip install PyPDF2 ebooklib beautifulsoup4 python-docx docx2txt
```

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
| `/api/kokoro/audio/list` | GET | List generated audio files |
| `/api/kokoro/audio/{filename}` | DELETE | Delete audio file |
| **XTTS** |||
| `/api/xtts/generate` | POST | Generate cloned voice audio |
| `/api/xtts/voices` | GET/POST/DELETE | Voice management |
| **Audiobook Creator** |||
| `/api/audiobook/generate` | POST | Start audiobook generation from text |
| `/api/audiobook/generate-from-file` | POST | Start generation from uploaded file (PDF/EPUB/TXT/DOCX) |
| `/api/audiobook/status/{job_id}` | GET | Get job progress (chars/sec, ETA, chapters) |
| `/api/audiobook/cancel/{job_id}` | POST | Cancel in-progress job |
| `/api/audiobook/list` | GET | List all generated audiobooks (WAV/MP3/M4B) |
| `/api/audiobook/{job_id}` | DELETE | Delete audiobook file |
| **Emma IPA** |||
| `/api/ipa/samples` | GET | List IPA sample texts |
| `/api/ipa/generate` | POST | Generate British IPA transcription |
| `/api/ipa/pregenerated` | GET | Get pregenerated IPA with audio |
| **LLM Configuration** |||
| `/api/llm/config` | GET/POST | Get or update LLM provider settings |
| `/api/llm/ollama/models` | GET | List locally available Ollama models |

### Audiobook Generation API

Generate audiobooks from documents using background job processing with progress tracking.

**Performance**: ~60 chars/sec on M2 MacBook Pro CPU (matching [audiblez](https://github.com/santinic/audiblez) benchmark).

**Start Generation (from text):**

```bash
curl -X POST http://localhost:8000/api/audiobook/generate \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Your long document text here...",
    "title": "My Audiobook",
    "voice": "bf_emma",
    "speed": 1.0,
    "output_format": "m4b"
  }'
```

**Start Generation (from file upload):**

```bash
curl -X POST http://localhost:8000/api/audiobook/generate-from-file \
  -F "file=@mybook.pdf" \
  -F "title=My Audiobook" \
  -F "voice=bf_emma" \
  -F "output_format=m4b"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `text` / `file` | string/file | *required* | Document text or uploaded file |
| `title` | string | `"Untitled"` | Audiobook title |
| `voice` | string | `"bf_emma"` | Kokoro voice ID |
| `speed` | float | `1.0` | Playback speed (0.5-2.0) |
| `output_format` | string | `"wav"` | Output format: `"wav"`, `"mp3"`, or `"m4b"` |
| `subtitle_format` | string | `"none"` | Subtitle format: `"none"`, `"srt"`, or `"vtt"` |

**Supported File Formats**: PDF (with TOC/chapter extraction), EPUB, TXT, MD, DOCX

**Subtitle Formats**:
- **SRT**: SubRip format - widely compatible with video players (VLC, media players)
- **VTT**: WebVTT format - web-friendly, works in browsers with `<video>` tags

Response:
```json
{
  "job_id": "abc123",
  "status": "started",
  "total_chunks": 20,
  "total_chars": 45000,
  "chapters": 5,
  "output_format": "m4b",
  "subtitle_format": "srt"
}
```

**Poll Progress (with ETA):**

```bash
curl http://localhost:8000/api/audiobook/status/abc123
```

Response:
```json
{
  "job_id": "abc123",
  "status": "processing",
  "current_chunk": 5,
  "total_chunks": 20,
  "percent": 25.0,
  "total_chars": 45000,
  "processed_chars": 11250,
  "chars_per_sec": 58.3,
  "eta_seconds": 578.5,
  "eta_formatted": "9m 38s",
  "current_chapter": 2,
  "total_chapters": 5,
  "output_format": "m4b"
}
```

**Completed Response (with subtitles):**
```json
{
  "job_id": "abc123",
  "status": "completed",
  "audio_url": "/audio/audiobook-abc123.m4b",
  "subtitle_url": "/audio/audiobook-abc123.srt",
  "subtitle_format": "srt",
  "duration_seconds": 3600.5,
  "file_size_mb": 45.2,
  "final_chars_per_sec": 62.1
}
```

**Output Formats:**
- **WAV**: Lossless, larger file size (~10MB/minute)
- **MP3**: Compressed, smaller file size (~1.5MB/minute at 192kbps)
- **M4B**: Audiobook format with chapter markers (requires ffmpeg)

**Subtitle Formats:**
- **SRT**: Standard subtitle format, compatible with VLC, media players
- **VTT**: WebVTT format for web video players and HTML5 `<track>` element

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

## System Requirements

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | macOS 12+ (Monterey or later) |
| **CPU** | Apple Silicon (M1/M2/M3/M4) or Intel |
| **RAM** | 8GB minimum, 16GB+ recommended |
| **Storage** | 10GB for models and dependencies |
| **Python** | 3.10 or later |
| **Flutter** | 3.x with macOS desktop support |

### Required System Dependencies

Install via Homebrew:

```bash
# Required for Kokoro TTS phonemization
brew install espeak-ng

# Required for MP3/M4B audiobook export
brew install ffmpeg
```

### Optional

- **CUDA GPU** (NVIDIA) - for faster inference on Linux/Windows
- **Apple Silicon** (M1/M2/M3/M4) - uses MPS acceleration where supported

---

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/BoltzmannEntropy/MimikaStudio.git
cd MimikaStudio
```

### Step 2: Install System Dependencies (macOS)

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required dependencies
brew install espeak-ng ffmpeg python@3.11

# Optional: Install spaCy model for robust sentence tokenization
# (The app will fall back to regex if not installed)
```

### Step 3: Set Up Python Backend

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt

# Install Qwen3-TTS for voice cloning
pip install -U qwen-tts soundfile

# Install spaCy for robust sentence tokenization (optional but recommended)
pip install spacy

# Verify installation
python -c "import kokoro; print('Kokoro OK')"
python -c "from qwen_tts import QwenTTS; print('Qwen3-TTS OK')"
```

### Step 4: Set Up Flutter Frontend

```bash
cd ../flutter_app

# Get Flutter dependencies
flutter pub get

# Verify Flutter setup
flutter doctor

# Build macOS app (optional - mimikactl will do this automatically)
flutter build macos --release
```

### Step 5: Initialize Database

```bash
cd ..
./bin/mimikactl db seed
```

### Step 6: Download Models (Optional - Auto-downloads on First Use)

```bash
# Pre-download Kokoro model (~300MB)
./bin/mimikactl models download kokoro

# Pre-download Qwen3-TTS models (~4GB for 1.7B)
./bin/mimikactl models download qwen3
```

### Step 7: Start MimikaStudio

```bash
# Start all services (Backend + MCP + Flutter UI)
./bin/mimikactl up

# Or start backend only (for API usage)
./bin/mimikactl up --no-flutter
```

The app will open automatically. Access the API at `http://localhost:8000`.

---

## Quick Start (TL;DR)

```bash
# One-liner for macOS with Homebrew
brew install espeak-ng ffmpeg python@3.11 && \
cd MimikaStudio/backend && \
python3 -m venv venv && source venv/bin/activate && \
pip install -r requirements.txt qwen-tts soundfile spacy && \
cd .. && ./bin/mimikactl db seed && ./bin/mimikactl up
```

---

## Running Tests

```bash
cd backend
source venv/bin/activate

# Run all tests (fast, mocks models)
pytest tests/

# Run with actual model tests (slow, requires models downloaded)
RUN_MODEL_TESTS=1 pytest tests/

# Run specific test file
pytest tests/test_audiobook.py -v
```

---

## Troubleshooting

### Common Issues

**"espeak-ng not found"**
```bash
brew install espeak-ng
# Or on Linux: sudo apt install espeak-ng
```

**"ffmpeg not found" (for MP3/M4B export)**
```bash
brew install ffmpeg
```

**"spaCy not available" (warning, not error)**
```bash
pip install spacy
# The app will use regex fallback if spaCy is not installed
```

**Models not downloading**
- Ensure you have internet access
- Models are stored in `~/.cache/huggingface/` (Qwen3) and `backend/models/` (Kokoro)

**Flutter build fails**
```bash
flutter clean
flutter pub get
flutter build macos --release
```

**Port 8000 already in use**
```bash
# Find and kill the process
lsof -i :8000
kill -9 <PID>
```

### Performance Tips

- **Apple Silicon**: Qwen3-TTS runs on CPU but Kokoro uses MPS when available
- **Audiobook generation**: Expect ~60 chars/sec on M2 MacBook Pro (matching audiblez benchmark)
- **Memory**: Close other apps when generating long audiobooks with 1.7B model

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

## Similar Projects

MimikaStudio was inspired by and builds upon ideas from these excellent projects:

| Project | Description | Key Features |
|---------|-------------|--------------|
| [**audiblez**](https://github.com/santinic/audiblez) | EPUB to audiobook converter using Kokoro TTS | spaCy sentence tokenization, M4B output with chapters, ~60 chars/sec on M2 CPU |
| [**pdf-narrator**](https://github.com/mateogon/pdf-narrator) | PDF to audiobook with smart text extraction | Skips headers/footers/page numbers, TOC-based chapter splitting, pause/resume |
| [**abogen**](https://github.com/denizsafak/abogen) | Full-featured audiobook generator GUI | Voice mixer, subtitle generation, batch processing, chapter markers |
| [**Qwen3-Audiobook-Converter**](https://github.com/WhiskeyCoder/Qwen3-Audiobook-Converter) | Qwen3-TTS audiobook tool | Style instructions for professional narration |

### What MimikaStudio Adds

MimikaStudio combines the best features from all these projects into a unified desktop experience:

- **From audiblez**: spaCy-based sentence tokenization, character-based progress tracking (~60 chars/sec benchmark), M4B output with chapter markers
- **From pdf-narrator**: Smart PDF extraction that skips headers/footers/page numbers, TOC-based chapter detection
- **From abogen**: Multiple output formats (WAV/MP3/M4B), real-time progress with ETA, chapter-aware processing
- **Unique to MimikaStudio**: Native macOS Flutter UI, 3-second voice cloning, unified voice library across multiple TTS engines, Emma IPA transcription, MCP server integration

---

## License

MIT License

## Acknowledgments

- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) - 3-second voice cloning with CustomVoice
- [Kokoro TTS](https://github.com/hexgrad/kokoro) - Fast, high-quality English TTS
- [Coqui TTS](https://github.com/coqui-ai/TTS) - XTTS2 voice cloning
- [Flutter](https://flutter.dev) - Cross-platform UI framework
- [FastAPI](https://fastapi.tiangolo.com) - Python API framework
- [spaCy](https://spacy.io) - Industrial-strength NLP for sentence tokenization
- [PyMuPDF](https://pymupdf.readthedocs.io) - Smart PDF text extraction
