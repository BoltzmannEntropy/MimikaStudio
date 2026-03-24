# MimikaStudio v2026.03.11 Release Notes

**Release Date:** March 24, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.03.11

- Fixed the packaged macOS app bundle so the bundled backend starts correctly on first launch from the release DMG.
- Rebuilt the embedded backend/python packaging flow so the final `.app` is re-signed and verified after resources are injected.
- Kept the existing unsigned-DMG guidance in place for Gatekeeper, while removing the broken sealed-bundle state that caused backend exit-on-start.

---

## User Impact

- New DMG installs should no longer fail with `Backend process exited before becoming healthy` on first launch.
- The bundled backend now survives the initial startup path instead of exiting with code `1` because of an invalid packaged app seal.
- Users still need the documented first-open Gatekeeper/quarantine workaround until the app is signed and notarized.

---

## Technical Notes

- Updated `scripts/build_dmg.sh` to strip copied extended attributes from the finished app bundle.
- Added a final app-bundle `codesign --deep` pass after embedding backend resources.
- Added strict post-build signature verification so broken release bundles fail during packaging instead of after shipping.

---

## Previous Release: v2026.03.10

- Added desktop drag-and-drop import to the Audiobooks workflow, plus resizable/collapsible panels for Documents, Generated Audiobooks, and Upload Voice management.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of March 24, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.
