# MimikaStudio v2026.02.5 Release Notes

**Release Date:** February 25, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.02.5

- Fixed Qwen3 voice clone failures for problematic user uploads by normalizing reference audio to safe mono PCM WAV before inference.
- Added upload-time decode/normalization guard for Qwen3 voice samples (invalid audio now returns clear 400 errors instead of generation-time 500 errors).
- Transcript is now optional when uploading Qwen3 voice samples.
- Newly uploaded Qwen3 voices now appear immediately in the voice list and are auto-selected.
- Added Settings folder view with direct open actions for key paths:
  - User home
  - Mimika user folder
  - Data folder
  - Generated audio folder
  - Log folder
  - Default voices folder (Max/Natasha/Sara/Suzan)
  - User clone voices folder
- Removed CosyVoice3 from visible desktop UI tabs/model manager surfaces.
- Added Jobs Queue showcase screenshot and documentation updates in README and website.

---

## Reliability Improvements

- Unified clone user-voice storage under one runtime-writable folder:
  `~/MimikaStudio/data/user_voices/cloners/` (or `MIMIKA_DATA_DIR` override).
- Added startup migration from legacy per-engine user voice folders into the shared cloner folder.
- Added dedicated `/api/system/folders` endpoint used by the Settings folder view.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of February 25, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.

---

## System Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3/M4)
- 8 GB RAM minimum (16 GB recommended)

