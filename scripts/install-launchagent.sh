#!/usr/bin/env bash
set -euo pipefail

# Installs the Smoothie macOS menubar app as a LaunchAgent so it boots
# at login. Builds a Release binary first; copies the .app to
# /Applications; writes the LaunchAgent plist; loads it.
#
# Idempotent — re-running upgrades the binary and reloads the agent.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_DIR="$REPO_ROOT/macOS"
APP_NAME="SmoothieMac.app"
INSTALL_PATH="/Applications/$APP_NAME"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/dev.smoothie.menubar.plist"
LOG_DIR="$HOME/Library/Logs/Smoothie"

echo "▶ Verifying toolchain…"
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen missing — brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild missing — install Xcode command-line tools"; exit 1; }

echo "▶ Building shared K/N framework (Release)…"
( cd "$REPO_ROOT" && ./gradlew :shared:assemble )

echo "▶ Regenerating SmoothieMac.xcodeproj…"
( cd "$MAC_DIR" && xcodegen generate )

echo "▶ Archiving Release build…"
ARCHIVE_PATH="$(mktemp -d)/SmoothieMac.xcarchive"
xcodebuild -project "$MAC_DIR/SmoothieMac.xcodeproj" \
  -scheme SmoothieMac \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

BUILT_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "✗ Built .app missing at $BUILT_APP" >&2
  exit 1
fi

echo "▶ Installing to $INSTALL_PATH…"
if [[ -d "$INSTALL_PATH" ]]; then
  sudo rm -rf "$INSTALL_PATH"
fi
sudo cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "▶ Writing LaunchAgent plist to $PLIST_PATH…"
mkdir -p "$PLIST_DIR" "$LOG_DIR"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.smoothie.menubar</string>
  <key>Program</key>
  <string>/Applications/$APP_NAME/Contents/MacOS/SmoothieMac</string>
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

echo "▶ (Re)loading LaunchAgent…"
launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/dev.smoothie.menubar"
launchctl kickstart -k "gui/$UID/dev.smoothie.menubar"

echo
echo "✓ Smoothie installed and running."
echo "  App:    $INSTALL_PATH"
echo "  Logs:   $LOG_DIR/"
echo "  Status: launchctl print gui/$UID/dev.smoothie.menubar"
echo "  Uninstall: ./scripts/uninstall-launchagent.sh"
