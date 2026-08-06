#!/bin/bash
# Notarize and publish an existing pi-work build to GitHub Releases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
EXPORT_PATH="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
APP_NAME="PiWork"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
GITHUB_REPO="section9-lab/pi-work"
KEYCHAIN_PROFILE="pi-work"

echo "Use scripts/build.sh before creating a release."
echo "Expected app: $APP_PATH"
echo "Expected DMG directory: $DMG_DIR"
