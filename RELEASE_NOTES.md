# MimikaStudio v2026.03.5 Release Notes

**Release Date:** March 9, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.03.5

- Added unified **Voice Prompt Management** workflows to create user voices by:
  - Uploading local WAV voice files, and
  - Importing from **YouTube URL** via `yt-dlp`, then extracting a 20-second speech segment for cloning prompts.
- Added explicit voice-name uniqueness validation in backend and UI to prevent collisions with existing voice prompts and default voices.
- Voice prompt lists now refresh immediately after add/edit/delete/import so newly introduced voices are instantly available in clone workflows.

---

## Voice Clone Workflow Changes

- Moved user-voice creation surfaces out of clone screens and centralized them in **Voice Prompts**.
- Updated clone screens to point users to Voice Prompt management and refresh voice choices when returning to clone tabs.
- Verified compatibility of custom voice prompts for both **Qwen3 Clone** and **Chatterbox** workflows.
- Moved **MCP**, **Pro**, and **About** into **Settings** as sub-tabs to reduce top-level navigation clutter.

---

## Reliability and Pre-Production Hardening

- Added YouTube source URL allowlist checks (`youtube.com` / `youtu.be`) for safer import handling.
- Added serialized voice mutation guards to reduce race-condition collisions on upload/update/delete/import endpoints.
- Added failure cleanup paths to avoid orphaned audio/transcript/meta files when import/upload writes fail.
- Added pre-production regression tests for voice prompt import validation and file-cleanup failure paths.
- Added additional `OsxSkills` pre-production guardrail tests for:
  - skill metadata/front matter integrity,
  - required release script presence,
  - shell script syntax checks.

---

## Previous Release: v2026.03.4

- Added a new copy-text action in **Qwen3 Clone -> Audio Library** so users can copy the source text used for a generated voice clone directly from each item.
- Added a new copy-text action in the **Jobs** tab so users can copy the input text for completed/active generation jobs.
- Extended job payload handling to retain source text for newly created jobs (with truncation safeguards), enabling copy behavior across Jobs and voice-clone audio list responses.

---

## Supertonic UI Update

- Added automatic **British** badge support in Supertonic voice cards when backend voice metadata indicates UK/British variants.
- Current Supertonic runtime still exposes generic style IDs (`F1..F5`, `M1..M5`), so badge display activates when metadata becomes available.

---

## Reliability Improvements

- Added bounded text retention controls for job records via `MIMIKA_MAX_JOB_TEXT_CHARS` (default `20000`) to avoid unbounded in-memory text growth.
- Avoided storing full audiobook source text in job history to keep long-form flows lightweight.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of March 2, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
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
