#!/bin/bash
# Build pi-work for release and create a local DMG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
ARCHIVE_PATH="$BUILD_DIR/PiWork.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
PROJECT_PATH="$PROJECT_DIR/pi-work.xcodeproj"
SCHEME="PiWork"
APP_NAME="PiWork"
TARGET_ARCH="arm64"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$PROJECT_DIR"

xcodebuild -resolvePackageDependencies -project "$PROJECT_PATH" -scheme "$SCHEME"

xcodebuild archive     -project "$PROJECT_PATH"     -scheme "$SCHEME"     -configuration Release     -archivePath "$ARCHIVE_PATH"     -destination "generic/platform=macOS"     ARCHS="$TARGET_ARCH"     ONLY_ACTIVE_ARCH=YES     EXCLUDED_ARCHS="x86_64"     ENABLE_HARDENED_RUNTIME=YES     CODE_SIGN_STYLE=Automatic

echo "Archive created at $ARCHIVE_PATH"
