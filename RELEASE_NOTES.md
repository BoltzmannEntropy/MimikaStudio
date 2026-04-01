# MimikaStudio v2026.04.1 Release Notes

**Release Date:** April 1, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.04.1

- Added embedded PDF page preview inside the Audiobooks document pane, with page navigation and zoom controls alongside extracted text preview.
- Disabled the old 7-day expiration messaging and removed active Polar.sh and LemonSqueezy checkout or portal flows from the in-app Pro screen.
- Removed website pricing and buying paths so downloads now point directly to GitHub releases without purchase messaging.

---

## User Impact

- Users can inspect PDF pages directly before generating audiobooks instead of relying only on extracted text.
- Users are no longer told that access expires after 7 days, and purchase links are clearly disabled in this build.
- Website visitors now see direct-download messaging instead of pricing cards or checkout prompts.

---

## Technical Notes

- Extended `flutter_app/lib/screens/audiobook_screen.dart` to support dual PDF or text preview modes using Syncfusion's PDF viewer controller.
- Simplified `flutter_app/lib/screens/pro_screen.dart` so it only reports current license state and accepts manual activation of existing keys.
- Updated the marketing site download links and release references to point at `v2026.04.1`.

---

## Previous Release: v2026.03.11

- Fixed the macOS DMG packaging regression that caused the bundled backend to exit on first launch.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of April 1, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.
