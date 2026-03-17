# TTS-Story vs MimikaStudio: Full Audiobook Generation Comparison

## At a Glance

| | **TTS-Story** | **MimikaStudio** |
|---|---|---|
| **Author** | Xerophayze (Eric Thorup) + 1 contributor | BoltzmannEntropy (solo) |
| **Stars** | 100 | 347 |
| **Architecture** | Flask web app (Python + vanilla JS) | Flutter desktop + FastAPI backend |
| **Platform** | **Windows-first** (Linux/macOS contributed) | **macOS Apple Silicon ONLY** |
| **GPU Backend** | NVIDIA CUDA | Apple Metal (MLX) |
| **License** | Apache 2.0 | BSL-1.1 (converts to GPL-2.0 later) |
| **Commits** | ~154 (since Nov 2025) | ~106 (since Jan 2026) |
| **Releases** | None (no tags) | Weekly versioned releases (v2026.03.5) |

---

## Model-by-Model Comparison

### Shared Models (available in both)

#### 1. Kokoro-82M

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Backend** | PyTorch (CUDA GPU) | MLX (Metal) |
| **Voices** | 46 across 7 languages | 21 (British + American English) |
| **Languages** | EN, ES, FR, HI, JA, ZH, PT | EN only |
| **Cloud option** | Yes (Replicate API) | No |
| **Speed** | ~2s per 500-word chunk (RTX 3090) | ~60 chars/sec, <200ms latency (M2) |
| **Custom blends** | Yes -- mix voices with weighted ratios | No |
| **Winner** | **TTS-Story** -- more voices, more languages, cloud fallback, voice blending |

#### 2. Qwen3-TTS

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Modes** | 3 separate engines: Custom Voice, Clone, Voice Creation | Unified engine: presets + cloning |
| **Model variants** | Not specified | 0.6B and 1.7B, each in bf16 and 8-bit quant |
| **Preset speakers** | Not specified | 9 (Ryan, Aiden, Vivian, Serena, etc.) |
| **Languages** | Multi-language | 10 languages |
| **Cloning min audio** | Reference audio required | 3 seconds minimum |
| **Streaming** | No | Yes (real-time PCM) |
| **Winner** | **MimikaStudio** -- quantization options, streaming, well-documented parameters |

#### 3. Chatterbox

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Backend** | PyTorch (CUDA, ~8GB VRAM) | MLX (Metal, ~6GB RAM) |
| **Languages** | English only | **23 languages** |
| **Cloud option** | Yes (Replicate API) | No |
| **Emotion control** | Exaggeration parameter | Event tags (`[laugh]`, `[sigh]`, etc.) + exaggeration |
| **Known issues** | Requires monkey-patching (fragile) | Installed with `--no-deps` (fragile) |
| **Winner** | **MimikaStudio** -- 23 languages vs 1, richer emotion control |

#### 4. IndexTTS-2

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Backend** | PyTorch (CUDA/MPS/CPU) | PyTorch (CUDA/CPU -- not MLX-native) |
| **Isolation** | Separate `uv` venv (subprocess worker) | Installed with `--no-deps` |
| **Emotion control** | Yes -- emotion audio, 8-value vector, text description | No |
| **FP16 support** | Yes (halves VRAM) | Not mentioned |
| **DeepSpeed** | Supported | Not supported |
| **Batch mode** | Yes (eliminates per-chapter model reload) | No |
| **Winner** | **TTS-Story** -- emotion control, FP16, DeepSpeed, batch mode |

### Models Exclusive to TTS-Story

| Model | Type | GPU | Cloning | Languages | Notable |
|---|---|---|---|---|---|
| **VoxCPM 1.5** | Local GPU | ~6GB VRAM | Yes + auto-transcription (SenseVoice ASR) | EN, ZH | Automatic reference audio transcription |
| **Pocket TTS** | CPU-only | None | Yes (clone variant) | EN | 8 parallel workers, great for CPU-only setups |
| **KittenTTS** | CPU-only | None | No | EN | Ultra-lightweight (<25MB model), 8 voices |

### Models Exclusive to MimikaStudio

| Model | Type | Backend | Cloning | Languages | Notable |
|---|---|---|---|---|---|
| **Supertonic-2** | ONNX preset TTS | ONNX Runtime | No | EN, KO, ES, PT, FR | Thread-safe, 10 voices, ~100MB |
| **CosyVoice3** | ONNX preset TTS | ONNX Runtime | No | 10 languages | 10 voices, ~3.8GB, warm session caching |

### Model Count Summary

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Distinct model families** | 7 | 6 |
| **Engine configurations** | 12 | 6 |
| **Voice cloning engines** | 5 (Chatterbox, VoxCPM, Qwen3, IndexTTS, Pocket TTS) | 3 (Chatterbox, Qwen3, IndexTTS) |
| **CPU-only options** | 2 (Pocket TTS, KittenTTS) | 0 (all require Metal or CUDA) |
| **Cloud API options** | 2 (Kokoro Replicate, Chatterbox Replicate) | 0 |

---

## Long-Form Audiobook Generation (Critical Comparison)

| Feature | TTS-Story | MimikaStudio |
|---|---|---|
| **Chunking strategy** | Word-based (500 words) OR character-based (450/500 chars), configurable per-engine | spaCy sentencizer, max 1500 chars |
| **Sentence boundary respect** | Yes, with smart fallback chain | Yes, with regex fallback |
| **Chapter detection** | From text structure, toggleable separate files per chapter | From document TOC (PDF, EPUB spine) |
| **Chapter audio output** | Per-chapter files AND/OR single combined audiobook | Combined output with chapter markers |
| **M4B with chapters** | No | **Yes** -- proper M4B with FFMETADATA1 chapter timestamps |
| **Pause/Resume** | **Yes** -- chapter manifest saved to disk, resume on restart | No explicit pause/resume |
| **YouTube timestamps** | **Yes** -- auto-generated with drift adjustment | No |
| **Crossfade** | 250ms default, configurable | 40ms default, configurable |
| **Intro silence** | 1500ms, configurable 0-2000ms | Not configurable |
| **Inter-chunk silence** | 550ms, configurable 0-2000ms | Not configurable |
| **Subtitles (SRT/WebVTT)** | No | **Yes** |
| **Loudness normalization** | Yes (dBFS-based via pydub) | Not explicit |
| **Progress tracking** | Chunk-based | Character-based (chars/sec, ETA %) |
| **AI text preprocessing** | **Yes** -- Gemini/OpenAI/Claude/LM Studio/Ollama for manuscript cleanup & speaker tagging | LLM used only for IPA phonetics, not preprocessing |
| **Input formats** | 9 (TXT, MD, PDF, DOCX, DOC, RTF, EPUB, ODT, HTML) | 5 (PDF, EPUB, DOCX, TXT, MD) |
| **Batch model loading** | IndexTTS batch mode avoids per-chapter reload | Singleton lazy-load, one engine at a time |

**Verdict for long books:** **TTS-Story wins decisively.** Its pause/resume, AI-powered manuscript preprocessing, 9 input formats, configurable silence/crossfade controls, YouTube timestamp generation, and batch model loading make it the far superior tool for book-length content. MimikaStudio counters with M4B chapter markers and subtitle generation, which are valuable for distribution.

---

## Multi-Speaker / Character Dialogue

| Feature | TTS-Story | MimikaStudio |
|---|---|---|
| **Speaker tagging** | `[speaker]text[/speaker]` with auto-detection | **None** -- single voice per audiobook |
| **Per-speaker voice assignment** | Yes, with per-speaker pitch/speed/tone | No |
| **Auto-assign voices** | Fuzzy-matches voice names to character names | No |
| **Speaker memory across chapters** | Yes, via LLM context carry-forward | No |
| **Tag validation** | Mismatch detection, fuzzy consolidation, auto-correction | No |

**Verdict:** **TTS-Story is the only option** for multi-character audiobooks. MimikaStudio has zero multi-speaker support -- it generates single-voice audiobooks only.

---

## Voice Cloning

| Feature | TTS-Story | MimikaStudio |
|---|---|---|
| **Cloning engines** | 5 | 3 |
| **Voice prompt library** | Shared across engines, drag-and-drop bulk upload | Shared across engines |
| **External voice library** | **500+ samples** downloadable in-app (tts-samples) | 4 bundled defaults (Yelena, Svetlana, Mikhail, Anastasia) |
| **YouTube voice import** | No | **Yes** (20-sec clips via yt-dlp) |
| **Voice prompt metadata** | Gender, language, duration, source | Basic metadata |
| **CPU-only cloning** | Yes (Pocket TTS Clone) | No |
| **Min reference audio** | 10-15s (Chatterbox), 3s+ (others) | 3s (Qwen3) |

**Verdict:** **TTS-Story** -- more cloning engines, massive sample library, CPU-only option. MimikaStudio's YouTube import is a nice touch but doesn't offset the gap.

---

## Audio Post-Processing

| Feature | TTS-Story | MimikaStudio |
|---|---|---|
| **Pitch shifting** | +-12 semitones (SoX/librosa/Rubber Band) | No |
| **Speed adjustment** | 0.5-2.0x with phase vocoder | 0.5-2.0x via resampling |
| **Tone profiles** | Warm/Bright/Neutral spectral shaping | No |
| **Audio blending** | Processed + original blend (up to 40%) | No |
| **Bundled tools** | SoX, Rubber Band, FFmpeg | FFmpeg only |

**Verdict:** **TTS-Story** -- full audio effects pipeline vs. basic speed control only.

---

## Developer / Integration

| Feature | TTS-Story | MimikaStudio |
|---|---|---|
| **API** | Flask web endpoints | 60+ REST endpoints + 60+ MCP tools + CLI |
| **MCP Server** | No | **Yes** -- JSON-RPC 2.0 on port 8010 |
| **CLI tool** | No | **Yes** (`mimika` command) |
| **Service controller** | No | **Yes** (`mimikactl`) |
| **Programmatic access** | Web UI only | REST + MCP + CLI + direct Python |

**Verdict:** **MimikaStudio** -- vastly superior programmatic access with MCP server, CLI, and service management.

---

## Platform & Deployment

| | TTS-Story | MimikaStudio |
|---|---|---|
| **Primary OS** | Windows | macOS (Apple Silicon only) |
| **Linux** | Contributed, may lag | Not supported |
| **macOS** | Contributed, may lag | Native Metal acceleration |
| **Windows** | Native | Not supported |
| **Intel** | Supported (CUDA) | **Not supported** |
| **One-click install** | Yes (Pinokio) | Yes (DMG, unsigned) |
| **GPU flexibility** | NVIDIA CUDA (any gen) | Apple Metal only |

---

## Final Verdict

### Choose **TTS-Story** if:
- You're on **Windows** or **Linux**
- You need **multi-character dialogue** in audiobooks (this is a dealbreaker -- MimikaStudio simply can't do it)
- You're processing **long books** and need pause/resume, AI preprocessing, and fine-grained silence controls
- You want the **most engine choices** (12 configs, 7 model families)
- You want **voice cloning on CPU** (Pocket TTS)
- You need **cloud API fallbacks** (Replicate)
- You want **post-processing effects** (pitch, tone, blending)
- You have an **NVIDIA GPU**

### Choose **MimikaStudio** if:
- You're on **macOS with Apple Silicon**
- You want a **polished native desktop app** (Flutter) vs a web UI
- You need **M4B audiobook format with chapter markers** for distribution
- You need **subtitles** (SRT/WebVTT) alongside audio
- You want **programmatic access** via MCP server, REST API, or CLI
- You want **Chatterbox in 23 languages** (vs English-only in TTS-Story)
- You prefer a **privacy-first, fully offline** workflow with no cloud options
- You want **Qwen3 model quantization** options (0.6B vs 1.7B, bf16 vs 8-bit)

### For Long Audiobook Production Specifically:
**TTS-Story is the clear winner.** Its multi-speaker dialogue system, LLM-powered manuscript preprocessing, pause/resume with state persistence, 9 input formats, configurable crossfade/silence timing, and YouTube chapter timestamp generation make it purpose-built for book-length content. MimikaStudio's audiobook pipeline is functional but basic -- single-voice only, no AI preprocessing, no pause/resume, and fewer input formats. The M4B chapter support in MimikaStudio is excellent for final distribution but doesn't compensate for the production workflow gaps.
