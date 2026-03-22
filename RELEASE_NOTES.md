# MimikaStudio v2026.03.10 Release Notes

**Release Date:** March 22, 2026  
**Platform:** macOS (Apple Silicon)

---

## What's New In v2026.03.10

- Added desktop drag-and-drop import to the Audiobooks document library for PDF, EPUB, DOCX, HTML, RTF, ODT, DOC, TXT, and Markdown files.
- Added explicit in-app drop messaging so the Audiobooks screen now clearly signals where to drop supported documents.
- Made the Audiobooks Documents pane collapsible and draggable to resize.
- Made the Generated Audiobooks pane collapsible and draggable to resize.
- Split Voice Prompts upload into a dedicated Upload Voice pane that is now collapsible and draggable to resize.

---

## User Impact

- You can now drag supported book/document files straight into the Audiobooks workflow instead of importing them only through the picker.
- Long-form generation controls are easier to manage because the Documents and Generated Audiobooks areas can be collapsed when you want more room for preview and settings.
- Voice Prompt Management has a clearer layout: upload stays in its own pane, while search/filter/audition work remains focused in the table below.

---

## Technical Notes

- Added the `desktop_drop` Flutter dependency and updated the macOS plugin registrant for native file-drop handling.
- Refactored `flutter_app/lib/screens/audiobook_screen.dart` to support dropped local files, explicit drop states, and split-pane resizing/collapse controls.
- Refactored `flutter_app/lib/screens/voice_prompt_management_screen.dart` to separate upload controls into their own resizable pane above the shared voice library table.

---

## Previous Release: v2026.03.9

- Fixed long-form audiobook generation failures for oversized extracted texts and replaced the transient audiobook start-failure snackbar with a readable dialog.

---

## Distribution Notes

### Unsigned DMG (Apple Gatekeeper)

As of March 22, 2026, the MimikaStudio DMG is not yet signed/notarized by Apple.  
macOS may block first launch until you explicitly allow it in security settings.

1. Open the DMG and drag MimikaStudio.app to Applications.
2. In Applications, right-click MimikaStudio.app and select Open.
3. Click Open in the warning dialog.
4. If macOS still blocks launch, go to: System Settings -> Privacy & Security -> Open Anyway (for MimikaStudio), then confirm with password/Touch ID.
5. On first launch, wait for the bundled backend to start.
6. On first use, click Download for required models in-app.
