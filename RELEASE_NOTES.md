# MimikaStudio v2026.02.6 Release Notes

**Release Date:** February 25, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.02.6

- Read Aloud side deck now includes Genesis multi-format variants:
  - PDF
  - Markdown (.md)
  - DOCX (.docx)
  - EPUB (.epub)
- Fixed Read Aloud selection/loading for API-backed DOCX/EPUB/MD entries on desktop.
- Added Free Text Mode in Read Aloud:
  - Paste or type text into a manual document.
  - Edit/Preview toggle in the same pane.
  - Use the same voice controls and "Convert to Audiobook" flow.
- Improved text-mode Read Aloud UX:
  - Clearer Select All / Clear Selection behavior with visible feedback.
  - Inline text-view highlight behavior improved while reading.

---

## Reliability Improvements

- Queue-based Read Aloud/Audiobook flows now behave consistently across PDF, DOCX, EPUB, MD, and TXT document inputs.
- Better fallback handling in text-view mode when extraction/loading fails.

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
