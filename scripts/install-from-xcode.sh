#!/bin/bash
# Install the most recent PiWork.app built by Xcode UI to /Applications.
set -euo pipefail

APP_NAME="PiWork"
BUNDLE_ID="com.section9lab.PiWork"
INSTALL_DIR="/Applications"

APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "$APP_NAME.app" -path "*/Build/Products/*" -prune 2>/dev/null | while read -r p; do
    printf '%s	%s
' "$(stat -f '%m' "$p")" "$p"
done | sort -rn | head -1 | cut -f2)

if [ -z "${APP_PATH:-}" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: No $APP_NAME.app found in DerivedData."
    exit 1
fi

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$INSTALL_DIR/"
open "$INSTALL_DIR/$APP_NAME.app"
