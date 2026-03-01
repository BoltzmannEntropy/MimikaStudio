# MimikaStudio v2026.03.2 Release Notes

**Release Date:** March 1, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.03.2

- Fixed a regression where `POST /api/kokoro/generate` could terminate embedded backend in long-path `.app` bundle layouts.
- Added eSpeak runtime path hardening in Kokoro engine to use a short alias path and prevent phonemizer backend crashes.
- Preserved embedded-only startup behavior from v2026.03.1 and kept local `mimikactl` aligned with DMG runtime.

---

## Reliability Improvements

- Added bundled eSpeak initialization smoke coverage to DMG build pipeline so path-related Kokoro regressions fail during build.
- Revalidated embedded app startup in sandboxed DMG mount and confirmed backend autostarts on `127.0.0.1:7693`.

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
