# MimikaStudio v2026.03.9 Release Notes

**Release Date:** March 21, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's Fixed In v2026.03.9

- Fixed long-form audiobook generation failures for very large EPUB and document inputs that exceeded spaCy's default 1,000,000-character limit during sentence splitting.
- Added a safe fallback so oversized audiobook texts use regex sentence splitting instead of aborting before chunking begins.
- Replaced the transient audiobook start-failure snackbar with a readable dialog so users can inspect the full backend error message.

---

## User Impact

- Large books that previously failed with errors like `Text Length 1015801 exceeds 1000000` can now proceed into audiobook chunking and queueing.
- Users now get a persistent error dialog when audiobook startup fails, instead of a brief bottom toast that disappears before the message can be read.
- EPUB chapter extraction remains in place; the failure was in full-document sentence splitting after extraction, not in the chapter parser itself.

---

## Technical Notes

- Updated `backend/tts/text_chunking.py` to detect texts beyond spaCy's `max_length` and fall back to the regex sentence splitter.
- Added a second fallback path for spaCy `E088` errors so oversized texts continue through audiobook chunking without raising.
- Added backend regression tests covering both oversized-input fallback and explicit `E088` fallback behavior.
- Updated the Flutter audiobook screen to present startup errors in a modal dialog with selectable text.

---

## Previous Release: v2026.03.8

- Restored Hebrew Dicta support for the MLX Chatterbox runtime.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of March 21, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.
