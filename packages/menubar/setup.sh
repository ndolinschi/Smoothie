#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "▶ xcodegen not found — installing via Homebrew…"
  brew install xcodegen
fi

echo "▶ Generating SmoothieMenubar.xcodeproj…"
xcodegen generate

echo
echo "✓ Done. Open the project:"
echo "    open packages/menubar/SmoothieMenubar.xcodeproj"
