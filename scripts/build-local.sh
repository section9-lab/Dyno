#!/bin/bash
# Build pi-work for local install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/local"
DERIVED_DATA="$BUILD_DIR/DerivedData"
PROJECT_PATH="$PROJECT_DIR/pi-work.xcodeproj"
SCHEME="PiWork"
APP_NAME="PiWork"
INSTALL_DIR="/Applications"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$PROJECT_DIR"

xcodebuild -resolvePackageDependencies -project "$PROJECT_PATH" -scheme "$SCHEME" >/dev/null

CERT_HASH=$(security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Development/ {print $2; exit}')
if [ -z "${CERT_HASH:-}" ]; then
    echo "ERROR: No 'Apple Development' identity found in keychain."
    exit 1
fi

xcodebuild build     -project "$PROJECT_PATH"     -scheme "$SCHEME"     -configuration Release     -destination "platform=macOS,arch=arm64"     -derivedDataPath "$DERIVED_DATA"     ONLY_ACTIVE_ARCH=YES     CODE_SIGNING_ALLOWED=NO     CODE_SIGNING_REQUIRED=NO     CODE_SIGN_IDENTITY="" >/dev/null

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ENTITLEMENTS="$PROJECT_DIR/PiWork/Resources/PiWork.entitlements"
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$CERT_HASH" "$APP_PATH"

echo "Built: $APP_PATH"
