#!/bin/bash
# Notarize and publish an existing Impulse build to GitHub Releases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
EXPORT_PATH="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
APP_NAME="Impulse"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
GITHUB_REPO="section9-lab/pi-work"
KEYCHAIN_PROFILE="Impulse"
SKIP_NOTARIZATION=false
SKIP_GITHUB=false

usage() {
    cat <<EOF
Usage: ./scripts/create-release.sh [options]

Options:
  --skip-notarization   Skip app and DMG notarization
  --skip-github         Create local artifacts but do not upload a GitHub release
  --help                Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarization)
            SKIP_NOTARIZATION=true
            ;;
        --skip-github)
            SKIP_GITHUB=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

echo "=== Creating Release ==="
echo

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "ERROR: Info.plist not found at $INFO_PLIST"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
TAG="v$VERSION"
DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
SIGNED_APP=true

mkdir -p "$DMG_DIR"

echo "Version: $VERSION (build $BUILD)"
echo

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

if ! codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    SIGNED_APP=false
fi

if [ "$SKIP_NOTARIZATION" = false ] && [ "$SIGNED_APP" = false ]; then
    echo "WARNING: $APP_PATH is not signed."
    echo "Notarization requires a Developer ID-signed app."
    echo "Run this script again with --skip-notarization for local DMG creation, or configure signing in Xcode first."
    exit 1
fi

if [ "$SKIP_NOTARIZATION" = false ]; then
    echo "=== Step 1: Notarizing app ==="

    if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
        echo
        echo "No notarytool keychain profile named '$KEYCHAIN_PROFILE' was found."
        echo "Create one with:"
        echo
echo ' xcrun notarytool store-credentials "Impulse" \\'
echo ' --apple-id "your@email.com" \\'
echo ' --team-id "YOUR_TEAM_ID" \\'
echo ' --password "xxxx-xxxx-xxxx-xxxx"'
        echo
        read -r -p "Skip notarization for this release? (y/N) " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        SKIP_NOTARIZATION=true
        echo "WARNING: Skipping notarization. Users may see Gatekeeper warnings."
    else
        echo "Creating ZIP for notarization..."
        rm -f "$ZIP_PATH"
        ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

        echo "Submitting app for notarization..."
        xcrun notarytool submit "$ZIP_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait

        echo "Stapling app notarization ticket..."
        xcrun stapler staple "$APP_PATH"
        rm -f "$ZIP_PATH"
        echo "App notarization complete."
    fi

    echo
fi

echo "=== Step 2: Using existing DMG ==="
echo "DMG: $DMG_PATH"
echo

if [ "$SKIP_NOTARIZATION" = false ]; then
    echo "=== Step 3: Notarizing DMG ==="
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "Stapling DMG notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarization complete."
    echo
fi

if [ "$SKIP_GITHUB" = true ]; then
    echo "=== Step 4: Skipping GitHub release upload ==="
    echo "Local artifact: $DMG_PATH"
    exit 0
fi

echo "=== Step 4: Uploading GitHub release ==="

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found. Install it with: brew install gh"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh CLI is not authenticated. Run: gh auth login"
    exit 1
fi

RELEASE_NOTES="## $APP_NAME $TAG

### Installation
1. Download $APP_NAME-$VERSION.dmg
2. Open the DMG and drag $APP_NAME to Applications
3. Launch $APP_NAME from Applications"

if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Uploading updated DMG..."
    gh release upload "$TAG" "$DMG_PATH" --repo "$GITHUB_REPO" --clobber
else
    echo "Creating release $TAG..."
    gh release create "$TAG" "$DMG_PATH" \
        --repo "$GITHUB_REPO" \
        --title "$APP_NAME $TAG" \
        --notes "$RELEASE_NOTES"
fi

echo

echo "=== Release Complete ==="
echo "DMG: $DMG_PATH"
echo "GitHub: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
