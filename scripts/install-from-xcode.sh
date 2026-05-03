#!/bin/bash
# Install the most recent Impulse.app built by Xcode UI to /Applications.
#
# Why this exists: command-line xcodebuild on Xcode 26 beta + a free
# Apple ID rejects every signing combination we throw at it, while Xcode
# UI signs cleanly. So: build from Xcode UI (⌘B), then run this script
# to drop the resulting .app into /Applications and reset TCC so screen
# recording can be granted against a stable signature.
set -euo pipefail

APP_NAME="Impulse"
BUNDLE_ID="com.section9lab.Impulse"
INSTALL_DIR="/Applications"

echo "=== Installing $APP_NAME from latest Xcode build ==="
echo

# Find every Impulse.app in any DerivedData path, take the newest one.
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name "$APP_NAME.app" \
    -path "*/Build/Products/*" \
    -prune \
    2>/dev/null \
  | while read -r p; do
        printf '%s\t%s\n' "$(stat -f '%m' "$p")" "$p"
    done \
  | sort -rn \
  | head -1 \
  | cut -f2)

if [ -z "${APP_PATH:-}" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: No $APP_NAME.app found in DerivedData."
    echo "Open Xcode and build (⌘B) first, then re-run this script."
    exit 1
fi

echo "Found: $APP_PATH"
echo "Built: $(stat -f '%Sm' "$APP_PATH")"
echo
echo "Signature:"
codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/  /' || true
echo

if codesign -dvvv "$APP_PATH" 2>&1 | grep -q "adhoc"; then
    echo "WARNING: this build is still ad-hoc signed."
    echo "Open Xcode → target Impulse → Signing & Capabilities,"
    echo "make sure Team is set to your Personal Team and rebuild."
    echo
fi

read -p "Quit running $APP_NAME, replace $INSTALL_DIR/$APP_NAME.app, and reset TCC? [y/N] " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
killall "$APP_NAME" 2>/dev/null || true

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$INSTALL_DIR/"
echo "Installed to $INSTALL_DIR/$APP_NAME.app"

# A fresh TCC entry will be created next launch, bound to the new
# signature, so the user can grant screen recording cleanly once.
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
echo "Reset TCC ScreenCapture for $BUNDLE_ID"

echo
echo "Final signature on installed app:"
codesign -dvvv "$INSTALL_DIR/$APP_NAME.app" 2>&1 | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/  /' || true

echo
read -p "Open $APP_NAME now? [y/N] " -n 1 -r
echo
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    open "$INSTALL_DIR/$APP_NAME.app"
fi
