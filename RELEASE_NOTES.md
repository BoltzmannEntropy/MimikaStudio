# MimikaStudio v2026.03.1 Release Notes

**Release Date:** March 1, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.03.1

- Enforced embedded-only startup mode for `mimikactl` so local runs match DMG behavior.
- Disabled raw Flutter dev-mode startup path in `mimikactl`; startup now requires bundled app resources.
- Updated backend startup in `mimikactl` to use the embedded backend launcher (`Contents/Resources/backend/run_backend.sh`).
- Added startup guards so `mimikactl` waits for actual UI process and fails fast with logs when launch fails.
- Fixed app version display mismatch by syncing Flutter app version (`flutter_app/lib/version.dart`) with release versioning.

---

## Reliability Improvements

- Embedded app smoke-tested in isolation (no prestarted backend): app boot now auto-starts backend on `127.0.0.1:7693`.
- `mimikactl` now validates embedded bundle availability and can build missing bundle artifacts before launch.

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
