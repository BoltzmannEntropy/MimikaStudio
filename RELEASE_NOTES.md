# MimikaStudio v2026.02.4 Release Notes

**Release Date:** February 24, 2026
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.02.4

- Split CosyVoice3 into a real standalone ONNX model (`ayousanz/cosy-voice3-onnx`) with independent download/status.
- Removed Supertonic-core coupling from CosyVoice3 endpoints and model checks.
- Added global Jobs tab in top navigation showing all TTS, voice-clone, and audiobook jobs.
- Added audiobook visibility in Jobs with audio playback once completed.
- Added generation-event job logging coverage for TTS and voice-clone flows.
- Added DOCX and EPUB text extraction support in Read Aloud.
- Removed fixed 300-character UI text-entry limits and preserved long-text editing with scrolling.
- Added download controls for generated audio across library surfaces.

---

## Reliability Improvements

### API and runtime stability

- `/api/system/info` now probes MLX availability using a subprocess-safe check to avoid hard interpreter abort paths.
- Model registry metadata now reflects CosyVoice3 capability accurately (standalone ONNX preset-voice TTS).
- Documentation and website model catalog now align with runtime behavior for CosyVoice3 vs Supertonic.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of February 24, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start. The startup log screen below is expected for a few seconds.
6. On first use, click Download for the required model in the in-app model card.

---

## System Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3/M4)
- 8 GB RAM minimum (16 GB recommended)

---

## Checksums

`MimikaStudio-2026.02.4-arm64.dmg` SHA256 is published in:

`MimikaStudio-2026.02.4-arm64.dmg.sha256`

---

**Full Changelog:** https://github.com/BoltzmannEntropy/MimikaStudio/compare/v2026.02.3...v2026.02.4
