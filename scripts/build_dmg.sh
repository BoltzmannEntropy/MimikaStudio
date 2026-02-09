#!/bin/bash
set -e

# MimikaStudio DMG Builder
# Usage: ./scripts/build_dmg.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== MimikaStudio DMG Builder ==="

# 1. Read version from version.py
VERSION=$(python3 -c "exec(open('$PROJECT_DIR/backend/version.py').read()); print(VERSION)")
BUILD_NUMBER=$(python3 -c "exec(open('$PROJECT_DIR/backend/version.py').read()); print(BUILD_NUMBER)")

echo "Building version: $VERSION (build $BUILD_NUMBER)"

# 2. Build directories
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="MimikaStudio"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

# 3. Build Flutter app (release mode)
echo "Building Flutter app..."
cd "$PROJECT_DIR/flutter_app"
flutter build macos --release

FLUTTER_APP="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release/mimika_studio.app"

if [ ! -d "$FLUTTER_APP" ]; then
    echo "Error: Flutter build failed - app not found at $FLUTTER_APP"
    exit 1
fi

# 4. Copy app to build directory
echo "Preparing app bundle..."
cp -R "$FLUTTER_APP" "$BUILD_DIR/$APP_NAME.app"

# 5. Create DMG
echo "Creating DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create DMG using hdiutil (basic method)
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$BUILD_DIR/$APP_NAME.app" || {
            echo "create-dmg failed, using hdiutil..."
            hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/$APP_NAME.app" -ov -format UDZO "$DMG_PATH"
        }
else
    echo "create-dmg not found, using hdiutil..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/$APP_NAME.app" -ov -format UDZO "$DMG_PATH"
fi

# 6. Generate SHA256 hash
echo "Generating SHA256 hash..."
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
SHA256=$(cat "$DMG_NAME.sha256" | cut -d' ' -f1)

echo ""
echo "=== Build Complete ==="
echo "DMG: $DMG_PATH"
echo "SHA256: $SHA256"
echo ""
echo "To code sign (requires Developer ID):"
echo "  codesign --deep --force --verify --verbose --sign 'Developer ID Application: YOUR_NAME' '$BUILD_DIR/$APP_NAME.app'"
echo ""
echo "To notarize (requires Apple Developer account):"
echo "  xcrun notarytool submit '$DMG_PATH' --apple-id YOUR_APPLE_ID --password YOUR_APP_PASSWORD --team-id YOUR_TEAM_ID --wait"
