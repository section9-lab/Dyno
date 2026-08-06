#!/bin/bash
# Downloads the official standalone `pi` coding-agent binary release
# (https://github.com/earendil-works/pi) for the architectures pi-work needs,
# and stages it under PiWork/Resources/PiAgent/<arch>/ so the app can bundle
# it as a Resource and spawn it as a subprocess. Nobody running pi-work needs
# Bun, Node, or npm installed — the binary is fully standalone.
#
# Usage: scripts/fetch-pi-binary.sh [version]
# Default version is pinned below; bump deliberately when upgrading.

set -euo pipefail

PI_VERSION="${1:-0.83.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_ROOT="$ROOT_DIR/PiWork/Resources/PiAgent"
BASE_URL="https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}"

fetch_arch() {
  local arch="$1"      # arm64 | x64
  local dest="$DEST_ROOT/$arch"
  local archive="pi-darwin-${arch}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"

  echo "==> Fetching pi ${PI_VERSION} for darwin-${arch}"
  curl -fsSL -o "$tmp/$archive" "$BASE_URL/$archive"

  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xzf "$tmp/$archive" -C "$dest" --strip-components=1
  rm -rf "$tmp"

  chmod +x "$dest/pi"
  echo "==> Staged $(file "$dest/pi" | sed 's/^[^:]*: //') at $dest/pi"
}

fetch_arch "arm64"
fetch_arch "x64"

echo "==> Done. Re-run 'xcodegen generate' if this is the first fetch (Resources folder membership is picked up by xcodegen)."
