#!/bin/bash
# Build Impulse for local install — uses Apple Development signing
# (free Apple ID accounts) and skips the Developer ID archive/export
# flow that scripts/build.sh assumes. Output: .build/local/Impulse.app
# ready to drop into /Applications.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/local"
DERIVED_DATA="$BUILD_DIR/DerivedData"
PROJECT_PATH="$PROJECT_DIR/Impulse.xcodeproj"
SCHEME="Impulse"
APP_NAME="Impulse"
INSTALL_DIR="/Applications"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode and command line tools first."
    exit 1
fi

echo "=== Local build for $APP_NAME ==="
echo

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"

echo "Resolving package dependencies..."
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" >/dev/null

CERT_HASH=$(security find-identity -p codesigning -v 2>/dev/null \
    | awk '/Apple Development/ {print $2; exit}')
if [ -z "${CERT_HASH:-}" ]; then
    echo "ERROR: No 'Apple Development' identity found in keychain."
    echo "Open Xcode → Settings → Accounts, sign in with your Apple ID,"
    echo "then click 'Manage Certificates' → '+' → 'Apple Development'."
    exit 1
fi
echo "Using identity: $CERT_HASH"

echo
echo "Building Release (unsigned)..."
xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" 2>&1 | tail -5

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    exit 1
fi

echo
echo "Signing $APP_PATH with $CERT_HASH ..."
ENTITLEMENTS="$PROJECT_DIR/Impulse/Resources/Impulse.entitlements"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CERT_HASH" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -5

echo
echo "Built: $APP_PATH"
codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/  /'

echo
read -p "Install to $INSTALL_DIR/$APP_NAME.app (overwrites existing)? [y/N] " -n 1 -r
echo
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_PATH" "$INSTALL_DIR/"
    echo "Installed to $INSTALL_DIR/$APP_NAME.app"
    echo
    echo "Reset TCC so the new signature can be granted cleanly:"
    echo "  tccutil reset ScreenCapture com.section9lab.Impulse"
    echo "Then open the app and grant screen recording when prompted."
fi
