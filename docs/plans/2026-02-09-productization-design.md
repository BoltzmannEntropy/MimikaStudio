# MimikaStudio Productization Design

**Date:** 2026-02-09
**Status:** Approved
**Target:** macOS Desktop Application with Commercial Licensing

---

## Overview

Transform MimikaStudio from an open-source project into a professional commercial macOS desktop application, similar to VoiceInk (tryvoiceink.com).

### Key Decisions

| Decision | Choice |
|----------|--------|
| Pricing Model | One-time purchase + 7-day trial |
| Price Point | $39.99 USD |
| License Management | Polar.sh |
| Versioning | Date-based (2026.02.1) |
| Auto-Updates | Sparkle framework |
| Model Manager | New sidebar tab (not popup) |
| Output Folder | Global setting in preferences |

---

## 1. Licensing & Trial System

### Architecture

```
License Flow:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  First Run  │───▶│  7-Day      │───▶│  Purchase   │
│  (No Key)   │    │  Trial      │    │  Required   │
└─────────────┘    └─────────────┘    └─────────────┘
                          │                  │
                          ▼                  ▼
                   ┌─────────────┐    ┌─────────────┐
                   │  Full       │◀───│  License    │
                   │  Access     │    │  Key Entry  │
                   └─────────────┘    └─────────────┘
```

### Implementation Components

#### 1.1 License Screen (`flutter_app/lib/screens/license_screen.dart`)
- Trial status display (days remaining)
- License key input field with validation
- "Buy License" button → Polar.sh checkout
- Visual feedback for valid/invalid keys

#### 1.2 License Service (`flutter_app/lib/services/license_service.dart`)
- Store license key in macOS Keychain (secure storage)
- Validate key on app launch (offline-first)
- Periodic online validation (every 7 days)
- Track trial start date in local preferences
- Graceful degradation if offline

#### 1.3 Backend License Endpoints
```
POST /api/license/validate    - Validate license key with Polar.sh
GET  /api/license/trial-status - Get trial days remaining
POST /api/license/activate    - Activate a new license
```

#### 1.4 Trial Behavior
- Full functionality during 7-day trial
- Clear banner showing "X days remaining in trial"
- After trial expires: app launches to license screen
- Cannot proceed to main app without valid license

---

## 2. UI Enhancements

### New Tab Structure (8 tabs)

```
Current (6 tabs):
[TTS] [Qwen3] [Chatterbox] [IndexTTS-2] [PDF] [MCP]

New (8 tabs):
[TTS] [Qwen3] [Chatterbox] [IndexTTS-2] [PDF] [Models] [Settings] [About]
```

### 2.1 Models Tab (`flutter_app/lib/screens/models_screen.dart`)

Full-screen model management replacing the popup dialog:

- Grid/list view of all 8 models
- Download progress bars with percentage
- Size indicators (GB)
- Engine grouping (Kokoro, Qwen3, Chatterbox, IndexTTS-2)
- One-click download/delete
- Real-time status updates (polling every 3s)
- Search/filter functionality

### 2.2 Settings Tab (`flutter_app/lib/screens/settings_screen.dart`)

Organized preference sections:

**General:**
- Output Folder: Directory picker for generated audio
- Default audio format (WAV/MP3)
- Default sample rate

**License:**
- View current license status
- Enter/change license key
- Trial days remaining
- Link to purchase

**Appearance:**
- Theme selection (Light/Dark/System)
- Font size adjustment

**Updates:**
- Enable/disable auto-updates
- Check frequency (daily/weekly)
- Manual "Check Now" button

**Advanced:**
- Cache management
- Clear model data
- Reset preferences
- Debug logging toggle

### 2.3 About Tab (`flutter_app/lib/screens/about_screen.dart`)

Professional about screen:

- MimikaStudio logo (centered)
- Version: 2026.02.1
- Website link: https://boltzmannentropy.github.io/mimikastudio.github.io/
- GitHub repository link
- License information (GPL v3.0)
- Credits/attributions for TTS engines:
  - Kokoro TTS
  - Qwen3-TTS (Alibaba)
  - Chatterbox
  - IndexTTS-2
- Support/feedback link
- Copyright notice

### 2.4 App Bar Updates

- Remove Model Manager button (now a tab)
- Keep system stats display (CPU/RAM/GPU)
- Add version badge in corner
- Trial banner when in trial mode

---

## 3. Versioning & Build System

### Version Management

Single source of truth files:

**`backend/version.py`:**
```python
VERSION = "2026.02.1"
BUILD_NUMBER = 1
VERSION_NAME = "Initial Release"
```

**`flutter_app/lib/version.dart`:**
```dart
const String appVersion = "2026.02.1";
const int buildNumber = 1;
const String versionName = "Initial Release";
```

### DMG Build Process

**`scripts/build_dmg.sh`:**

```bash
#!/bin/bash
# MimikaStudio DMG Builder

# 1. Read version from version.py
VERSION=$(python3 -c "exec(open('backend/version.py').read()); print(VERSION)")

# 2. Build Flutter app (release mode)
cd flutter_app && flutter build macos --release

# 3. Bundle backend with PyInstaller
cd ../backend && pyinstaller mimikastudio.spec

# 4. Create .app bundle
# ... bundle creation logic

# 5. Code sign with Developer ID
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: YOUR_NAME" \
  "MimikaStudio.app"

# 6. Create DMG with create-dmg
create-dmg \
  --volname "MimikaStudio" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 185 \
  "MimikaStudio-${VERSION}.dmg" \
  "MimikaStudio.app"

# 7. Generate SHA256 hash
shasum -a 256 "MimikaStudio-${VERSION}.dmg" > "MimikaStudio-${VERSION}.dmg.sha256"

# 8. Notarize with Apple
xcrun notarytool submit "MimikaStudio-${VERSION}.dmg" \
  --apple-id "$APPLE_ID" \
  --password "$APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# 9. Staple the notarization
xcrun stapler staple "MimikaStudio-${VERSION}.dmg"

echo "Build complete: MimikaStudio-${VERSION}.dmg"
```

### Sparkle Auto-Update

**`appcast.xml`** (hosted on GitHub Pages):
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MimikaStudio Updates</title>
    <link>https://boltzmannentropy.github.io/mimikastudio.github.io/appcast.xml</link>
    <description>MimikaStudio update feed</description>
    <language>en</language>
    <item>
      <title>Version 2026.02.1</title>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>Initial commercial release</li>
          <li>7-day free trial</li>
          <li>Professional licensing system</li>
        </ul>
      ]]></description>
      <pubDate>Sun, 09 Feb 2026 12:00:00 +0000</pubDate>
      <sparkle:version>2026.02.1</sparkle:version>
      <sparkle:shortVersionString>2026.02.1</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/BoltzmannEntropy/MimikaStudio/releases/download/v2026.02.1/MimikaStudio-2026.02.1.dmg"
        sparkle:dsaSignature="..."
        length="..."
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

**Flutter Sparkle Integration:**
- Native Swift plugin for macOS
- Check for updates on app launch
- User prompt before downloading
- Background download with progress

### Release Artifacts

Each release produces:
- `MimikaStudio-2026.02.1.dmg` - Main installer
- `MimikaStudio-2026.02.1.dmg.sha256` - Checksum file
- `appcast.xml` - Updated manifest
- `CHANGELOG.md` - Release notes

---

## 4. Website Updates

### Pricing Section Design

Add to `/Volumes/SSD4tb/Dropbox/DSS/artifacts/all-web/Mimika/index.html`:

```
┌─────────────────────────────────────────────────────────────┐
│                       PRICING                                │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │      FREE TRIAL     │    │         PRO LICENSE         │ │
│  │                     │    │                             │ │
│  │  7 Days Full Access │    │         $39.99              │ │
│  │  ─────────────────  │    │     One-time purchase       │ │
│  │  ✓ All TTS Engines  │    │  ───────────────────────    │ │
│  │  ✓ Voice Cloning    │    │  ✓ Everything in Trial      │ │
│  │  ✓ PDF Reader       │    │  ✓ Lifetime updates         │ │
│  │  ✓ Audiobook Gen    │    │  ✓ Priority support         │ │
│  │                     │    │  ✓ Auto-updates via Sparkle │ │
│  │  [Start Free Trial] │    │  ✓ Commercial use allowed   │ │
│  │                     │    │                             │ │
│  │                     │    │  [Buy Now via Polar.sh]     │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Additional Website Changes

1. **Navigation:** Add "Pricing" and "Get License" links
2. **Download Button:** Show version number, link to latest DMG
3. **FAQ Section:** Licensing questions (refunds, device limits, updates)
4. **Footer:** Add Polar.sh badge, version info

### Polar.sh Integration

1. Create product on polar.sh dashboard
2. Configure $39.99 one-time purchase
3. Set up webhook for license key delivery
4. Embed checkout link in website and app

---

## 5. Backend Enhancements

### New Endpoints

```python
# License endpoints
@app.post("/api/license/validate")
async def validate_license(key: str) -> LicenseStatus

@app.get("/api/license/trial-status")
async def get_trial_status() -> TrialStatus

@app.post("/api/license/activate")
async def activate_license(key: str) -> ActivationResult

# Settings endpoints
@app.get("/api/settings")
async def get_settings() -> Settings

@app.put("/api/settings")
async def update_settings(settings: Settings) -> Settings

@app.get("/api/settings/output-folder")
async def get_output_folder() -> str

@app.put("/api/settings/output-folder")
async def set_output_folder(path: str) -> bool
```

### Settings Storage

New SQLite table for user settings:

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Default settings
INSERT INTO settings (key, value) VALUES
    ('output_folder', '~/MimikaStudio/outputs'),
    ('theme', 'system'),
    ('auto_update', 'true'),
    ('update_frequency', 'weekly');
```

### License Storage

```sql
CREATE TABLE license (
    id INTEGER PRIMARY KEY,
    license_key TEXT,
    email TEXT,
    activated_at TIMESTAMP,
    last_validated TIMESTAMP,
    is_valid BOOLEAN DEFAULT FALSE
);

CREATE TABLE trial (
    id INTEGER PRIMARY KEY,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);
```

---

## 6. File Structure Changes

### New Files

```
backend/
├── version.py                    # NEW: Version constants
├── license/                      # NEW: License module
│   ├── __init__.py
│   ├── polar_client.py          # Polar.sh API client
│   ├── license_service.py       # License validation logic
│   └── trial_manager.py         # Trial tracking
└── settings/                     # NEW: Settings module
    ├── __init__.py
    └── settings_service.py

flutter_app/lib/
├── version.dart                  # NEW: Version constants
├── screens/
│   ├── models_screen.dart       # NEW: Full models page
│   ├── settings_screen.dart     # NEW: Settings page
│   ├── about_screen.dart        # NEW: About page
│   └── license_screen.dart      # NEW: License/trial page
└── services/
    ├── license_service.dart     # NEW: License management
    └── settings_service.dart    # NEW: Settings persistence

scripts/
├── build_dmg.sh                 # NEW: DMG builder
├── bump_version.py              # NEW: Version bumper
└── generate_appcast.py          # NEW: Appcast generator
```

### Modified Files

```
flutter_app/lib/
├── main.dart                    # Update tab structure
└── services/
    └── api_service.dart         # Add license/settings endpoints

backend/
├── main.py                      # Add new endpoints, import version
└── database.py                  # Add settings/license tables
```

---

## 7. Implementation Order

### Phase 1: Foundation
1. Create version files (backend/version.py, flutter_app/lib/version.dart)
2. Add LICENSE file (GPL v3.0)
3. Create settings infrastructure (backend + frontend)
4. Implement output folder selection

### Phase 2: UI Restructure
5. Create Models screen (move from dialog)
6. Create Settings screen
7. Create About screen
8. Update main.dart tab structure
9. Update app bar

### Phase 3: Licensing
10. Create license backend module
11. Set up Polar.sh integration
12. Create License screen
13. Implement trial tracking
14. Add license validation flow

### Phase 4: Build System
15. Create build_dmg.sh script
16. Add SHA256 hash generation
17. Set up Sparkle integration
18. Create appcast.xml template
19. Document code signing process

### Phase 5: Website
20. Add pricing section to website
21. Add FAQ section
22. Update download links
23. Integrate Polar.sh checkout

### Phase 6: Skill Update
24. Update flutter-python-fullstack skill with productization patterns

---

## 8. Testing Checklist

### License Testing
- [ ] Fresh install shows trial screen
- [ ] Trial countdown is accurate
- [ ] Trial expiration blocks app access
- [ ] Valid license key unlocks app
- [ ] Invalid license key shows error
- [ ] Offline license validation works
- [ ] License persists across restarts

### UI Testing
- [ ] All 8 tabs render correctly
- [ ] Models screen shows accurate status
- [ ] Settings persist across restarts
- [ ] Output folder selection works
- [ ] About page links work

### Build Testing
- [ ] DMG builds successfully
- [ ] SHA256 hash is generated
- [ ] App launches from DMG
- [ ] Code signing passes verification
- [ ] Sparkle update check works

---

## Appendix: Reference Links

- VoiceInk: https://tryvoiceink.com/
- VoiceInk GitHub: https://github.com/Beingpax/VoiceInk
- Polar.sh: https://polar.sh/
- Sparkle Framework: https://sparkle-project.org/
- MimikaStudio Website: https://boltzmannentropy.github.io/mimikastudio.github.io/
