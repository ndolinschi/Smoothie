#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/dev.smoothie.server.plist"
INSTALL_BIN="/usr/local/bin/smoothie-server"

echo "▶ Unloading LaunchAgent…"
launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true

if [[ -f "$PLIST_PATH" ]]; then
  echo "▶ Removing $PLIST_PATH…"
  rm "$PLIST_PATH"
fi

if [[ -f "$INSTALL_BIN" ]]; then
  echo "▶ Removing $INSTALL_BIN (sudo)…"
  sudo rm "$INSTALL_BIN"
fi

echo "✓ Smoothie server uninstalled."
