#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$REPO_ROOT/packages/server"
INSTALL_BIN="/usr/local/bin/smoothie-server"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/dev.smoothie.server.plist"
LOG_DIR="$HOME/Library/Logs/Smoothie"

echo "▶ Building release binary…"
cd "$SERVER_DIR"
swift build -c release

BIN_SRC="$SERVER_DIR/.build/release/SmoothieServer"
if [[ ! -x "$BIN_SRC" ]]; then
  echo "✗ Release binary not found at $BIN_SRC" >&2
  exit 1
fi

echo "▶ Installing to $INSTALL_BIN (sudo)…"
sudo install -m 0755 "$BIN_SRC" "$INSTALL_BIN"

echo "▶ Writing plist to $PLIST_PATH…"
mkdir -p "$PLIST_DIR" "$LOG_DIR"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.smoothie.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/smoothie.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/smoothie.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF

echo "▶ Loading LaunchAgent…"
launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/dev.smoothie.server"
launchctl kickstart "gui/$UID/dev.smoothie.server"

echo
echo "✓ Smoothie server installed and running."
echo "  Logs: $LOG_DIR/"
echo "  Status: launchctl print gui/$UID/dev.smoothie.server"
echo "  Uninstall: ./scripts/uninstall-launchagent.sh"
