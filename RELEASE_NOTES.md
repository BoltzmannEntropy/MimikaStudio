# MimikaStudio v2026.02.1 Release Notes

**Release Date:** February 2026
**Platform:** macOS (Apple Silicon optimized)

---

## Highlights

This release marks a major architectural shift to **MLX-Audio**, Apple's native machine learning framework. MimikaStudio now runs entirely on Metal GPU acceleration without requiring PyTorch, resulting in faster startup times, lower memory usage, and better performance on Apple Silicon Macs.

---

## Major Changes

### MLX-Audio Migration (Breaking Change)

**Before:** PyTorch-based TTS engines with CUDA/MPS backends
**After:** Native MLX-Audio framework optimized for Apple Silicon

| Aspect | PyTorch (Old) | MLX-Audio (New) |
|--------|---------------|-----------------|
| Startup time | ~15-20 seconds | ~3-5 seconds |
| Memory usage | 4-8 GB | 1-3 GB |
| Dependencies | torch, torchaudio, transformers | mlx-audio (single package) |
| GPU Backend | MPS (via PyTorch) | Metal (native) |
| Model format | .safetensors/.bin | MLX-optimized |

**Benefits:**
- No more PyTorch installation (~2GB saved)
- Native Metal acceleration on M1/M2/M3/M4 chips
- Unified TTS API through mlx-audio package
- Faster model loading and inference

### Simplified TTS Engine Stack

Removed IndexTTS-2 engine to focus on three high-quality, well-maintained engines:

| Engine | Purpose | Languages |
|--------|---------|-----------|
| **Kokoro** | Fast British English TTS | English (8 voices) |
| **Qwen3-TTS** | Voice cloning & custom voices | Multilingual (EN, ZH, JP, KO) |
| **Chatterbox** | Zero-shot voice cloning | Multilingual |

**Removed:**
- IndexTTS-2 engine and screen
- Emma IPA transcription widget
- LLM integration module (backend/llm/)

### Removed Features

The following features have been removed to streamline the application:

- **IndexTTS-2 Engine**: Removed due to limited MLX support
- **LLM Integration**: Removed Claude/OpenAI/Codex provider modules
- **IPA Generator**: Removed phonetic transcription features
- **Hebrew Voice Samples**: Consolidated into single voices folder

---

## New Features

### Models Screen (Full Page)

The model manager has been promoted from a popup dialog to a dedicated tab:

- Grid view of all available models
- Download progress with percentage
- Size indicators (GB)
- Source URLs linking to HuggingFace repos
- One-click download/delete
- Real-time status polling

### Settings Screen

New centralized settings management:

- **Output Folder**: Configure where generated audio files are saved
- Persistent settings stored in SQLite database
- Expandable for future preferences (theme, auto-update, etc.)

### About Screen

Professional about page with:

- App version and build number
- Website and GitHub links
- Credits for TTS engines (Kokoro, Qwen3, Chatterbox)
- License information

### PDF Reader Improvements

- **Voice Cards**: Horizontal selection chips for quick voice switching
- **Inline Speed Control**: Adjust TTS speed without sidebar
- **Read Aloud Button**: Restored prominent play/pause/stop controls
- **Character Counter**: Shows "X chars ready" before reading

### Build System

- **DMG Builder**: Automated macOS installer creation
- **SHA256 Hashing**: Integrity verification for downloads
- **Version Bumper**: Synchronized versioning across backend and Flutter

---

## Technical Changes

### Dependencies

**Added:**
```
mlx-audio>=0.3.0    # Unified TTS engine
```

**Removed:**
```
torch
torchaudio
transformers
accelerate
indextts  # IndexTTS-2 package
```

### Backend API

**Removed Endpoints:**
- `/api/llm/*` - LLM chat endpoints
- `/api/ipa/*` - IPA generation endpoints
- `/api/indextts/*` - IndexTTS-2 endpoints

**Modified Endpoints:**
- All TTS endpoints now use MLX-Audio backend
- Model registry updated for MLX model paths

### File Structure

**Removed:**
```
backend/llm/                    # LLM providers
backend/language/               # IPA generator
backend/tts/indextts2_engine.py
backend/tts/_indextts_compat.py
flutter_app/lib/screens/indextts2_screen.dart
flutter_app/lib/widgets/emma_ipa_widget.dart
```

**Added:**
```
flutter_app/lib/screens/models_screen.dart
flutter_app/lib/screens/settings_screen.dart
flutter_app/lib/screens/about_screen.dart
flutter_app/lib/version.dart
backend/version.py
scripts/build_dmg.sh
scripts/bump_version.py
```

### Navigation

Tab structure changed from 6 to 8 tabs:

**Before:** TTS | Qwen3 | Chatterbox | IndexTTS-2 | PDF | MCP
**After:** Models | TTS | Qwen3 | Chatterbox | PDF | MCP | Settings | About

---

## Migration Guide

### For Users

1. **Clean Install Recommended**: Due to major dependency changes, a fresh install is recommended
2. **Re-download Models**: MLX models have different paths; existing PyTorch models won't be used
3. **Voice Samples**: Custom voice samples in the old `chatterbox_voices/` and `qwen3_voices/` folders should be moved to the unified `voices/` folder

### For Developers

1. **Update Requirements**: Run `pip install -r backend/requirements.txt`
2. **No PyTorch**: Remove any PyTorch-related code or imports
3. **Use MLX-Audio API**: See `backend/tts/kokoro_engine.py` for the new pattern:
   ```python
   from mlx_audio.tts.utils import load_model
   model = load_model("mlx-community/Kokoro-82M-bf16")
   ```

---

## System Requirements

- **OS**: macOS 13.0 (Ventura) or later
- **Chip**: Apple Silicon (M1/M2/M3/M4) - Intel not supported
- **RAM**: 8 GB minimum, 16 GB recommended
- **Storage**: 5-10 GB for models

---

## Known Issues

- Chatterbox exaggeration parameter defaults to 0.1 (was 0.5 in PyTorch version)
- Some pre-existing voice samples may need re-recording for optimal quality with MLX

---

## Acknowledgments

- [MLX-Audio](https://github.com/ml-explore/mlx-audio) by Apple ML Research
- [Kokoro TTS](https://huggingface.co/hexgrad/Kokoro-82M)
- [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base) by Alibaba
- [Chatterbox](https://github.com/resemble-ai/chatterbox) by Resemble AI

---

## Checksums

```
MimikaStudio-2026.02.1.dmg: [SHA256 hash will be added at build time]
```

---

**Full Changelog:** [Compare on GitHub](https://github.com/BoltzmannEntropy/MimikaStudio/compare/v2026.01...v2026.02.1)
