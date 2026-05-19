#!/usr/bin/env bash
set -euo pipefail

# Tears down the Smoothie LaunchAgent and removes the installed app.

PLIST_PATH="$HOME/Library/LaunchAgents/dev.smoothie.menubar.plist"
INSTALL_PATH="/Applications/SmoothieMac.app"

echo "▶ Unloading LaunchAgent…"
launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true

if [[ -f "$PLIST_PATH" ]]; then
  echo "▶ Removing $PLIST_PATH…"
  rm "$PLIST_PATH"
fi

if [[ -d "$INSTALL_PATH" ]]; then
  echo "▶ Removing $INSTALL_PATH (sudo)…"
  sudo rm -rf "$INSTALL_PATH"
fi

echo "✓ Smoothie uninstalled."
echo "  (Pairing token in Keychain is left in place — re-installing reuses it. Use the popover's Re-pair to rotate.)"
