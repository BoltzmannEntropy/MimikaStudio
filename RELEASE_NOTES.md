# MimikaStudio v2026.02.7 Release Notes

**Release Date:** February 26, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.02.7

- Fixed audiobook outputs not appearing in the Read Aloud side deck when generated through API/MCP code paths.
- Added legacy-output migration in `/api/audiobook/list` so previously generated audiobook files are discovered and served correctly.
- Fixed PDF word highlighting during Read Aloud when reading from a selected text range.
- Updated MCP documentation and agentic usage examples (Codex + Claude) in project docs.

---

## Reliability Improvements

- Audiobook generation now writes outputs to the active runtime output directory used by API listing and `/audio` serving.
- Duplicate audiobook entries are avoided when scanning across primary + legacy output folders.

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
