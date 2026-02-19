# MimikaStudio v2026.02.3 Release Notes

**Release Date:** February 19, 2026
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.02.3

- Hardened bundled backend startup for DMG distributions.
- Added explicit app-exit shutdown flow so backend is stopped when the window is closed.
- Added close-time "Stopping Server" UX to avoid silent orphaned backend processes.
- Improved backend startup failure messaging to avoid stale log-based false errors.
- Added stronger DMG build-time smoke checks for backend health and bundled PDF serving.

---

## Reliability Improvements

### Backend startup and packaging

- Runtime signature verification and retry now protect against partially signed native dependencies.
- Build pipeline now fails fast if bundled backend import smoke test fails.
- Build pipeline now starts the staged bundled backend and verifies:
  - `GET /api/health`
  - `GET /api/pdf/list`
  - direct fetch of a bundled PDF from `/pdf/...`

### Exit behavior

- Desktop app close now intercepts exit requests.
- Backend stop is triggered before final app termination.
- Users see an explicit shutdown progress dialog while backend teardown runs.

---

## Distribution Notes

- DMG remains unsigned/not notarized as of February 19, 2026.
- First launch may require Gatekeeper approval via right-click `Open`, then `Open Anyway` in Privacy & Security.

---

## System Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3/M4)
- 8 GB RAM minimum (16 GB recommended)

---

## Checksums

`MimikaStudio-2026.02.3-arm64.dmg` SHA256:

`b048327159689eacbe78a9f20d9becfa84f8725e9178c81c7254158539f1538d`

---

**Full Changelog:** https://github.com/BoltzmannEntropy/MimikaStudio/compare/v2026.02.2...v2026.02.3
