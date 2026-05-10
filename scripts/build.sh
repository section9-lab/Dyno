#!/bin/bash
# Build Impulse for release and create a local DMG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
ARCHIVE_PATH="$BUILD_DIR/Impulse.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
PROJECT_PATH="$PROJECT_DIR/Impulse.xcodeproj"
SCHEME="Impulse"
APP_NAME="Impulse"
TARGET_ARCH="arm64"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode and command line tools first."
    exit 1
fi

echo "=== Building $APP_NAME ==="
echo "Target architecture: $TARGET_ARCH"
echo

echo "Cleaning previous build output..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

cd "$PROJECT_DIR"

echo "Resolving package dependencies..."
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME"

echo
echo "Archiving..."
set +e
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="$TARGET_ARCH" \
    ONLY_ACTIVE_ARCH=YES \
    EXCLUDED_ARCHS="x86_64" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Automatic
ARCHIVE_EXIT=$?
set -e

if [ "$ARCHIVE_EXIT" -ne 0 ]; then
    echo "ERROR: Archive failed."
    exit 1
fi

echo
echo "Exporting archive..."
EXPORT_LOG="$BUILD_DIR/export.log"
rm -f "$EXPORT_LOG"
set +e
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    >"$EXPORT_LOG" 2>&1
EXPORT_EXIT=$?
set -e

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [ "$EXPORT_EXIT" -ne 0 ]; then
    if grep -q "No Team Found in Archive" "$EXPORT_LOG"; then
        echo "WARNING: Export failed because no signing team is configured for Developer ID export."
        echo "Falling back to the archived app so you can still create a local DMG."
        echo "Set your signing team in Xcode before using notarization or public release upload."
        mkdir -p "$EXPORT_PATH"
        cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"
    else
        cat "$EXPORT_LOG"
        echo "ERROR: Export failed."
        exit 1
    fi
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "ERROR: Info.plist not found at $INFO_PLIST"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"

echo
echo "Creating DMG..."
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    echo "Using create-dmg..."
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$APP_PATH"
else
    echo "Using hdiutil fallback (install create-dmg for a prettier DMG: brew install create-dmg)"
    STAGING_DIR="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_PATH" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING_DIR"
fi

echo
echo "=== Build Complete ==="
echo "App exported to: $APP_PATH"
echo "DMG created at: $DMG_PATH"
echo
echo "Next: Run ./scripts/create-release.sh to notarize and upload the existing artifacts"
