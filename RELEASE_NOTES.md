# MimikaStudio v2026.03.8 Release Notes

**Release Date:** March 18, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's Fixed In v2026.03.8

- Restored **Hebrew Dicta diacritization** for **Chatterbox Multilingual** after the MLX backend migration.
- Fixed the regression where Hebrew Chatterbox generation could silently fall back to a broken tokenizer path and log:
  `Dicta.__init__() missing 1 required positional argument: 'model_path'`
- Rewired MimikaStudio's Chatterbox engine to preload the Dicta ONNX model into the tokenizer module actually used by the MLX runtime before model load.

---

## User Impact

- **Hebrew Chatterbox smoke tests** now run without the Dicta initialization warning.
- **Full Hebrew voice-clone renders** complete successfully again on the patched MLX path.
- Existing Hebrew Dicta installs are now picked up from:
  - `DICTA_ONNX_MODEL_PATH`
  - bundled app model path
  - Mimika runtime data model path

---

## Technical Notes

- Updated the backend Chatterbox engine to resolve an explicit Dicta ONNX path instead of relying on a zero-argument `Dicta()` constructor.
- Patched both supported tokenizer import paths so Hebrew preprocessing is applied consistently across the MLX-backed Chatterbox runtime.
- Verified generation with:
  - a short Hebrew smoke test
  - a full Hebrew `parashat_hashavua.txt` render using a custom uploaded reference voice

---

## Previous Release: v2026.03.7

- Sandboxed release entitlement update and release-build hardening.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of March 18, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.
