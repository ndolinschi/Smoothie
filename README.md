# Smoothie

Mobile-first AI agent controller. Your Mac runs the CLI agents (Claude
Code today, Gemini and OpenCode soon); your iPhone controls them over
Tailscale. No cloud — code never leaves your tailnet.

```
┌──────────────┐   Tailscale + Bearer    ┌────────────────────┐   pipe stdin/stdout    ┌────────────────────┐
│  iPhone app  │ ◄────────────────────►  │   macOS menubar    │ ◄────────────────────► │  CLI agent process │
│  (SwiftUI,   │   HTTP + SSE            │   daemon           │   (Foundation.Process) │  (claude / gemini  │
│  iOS 26      │                         │   (Hummingbird +   │                        │   / opencode)      │
│  Liquid      │                         │   K/N business     │                        │                    │
│  Glass)      │                         │   logic)           │                        │                    │
└──────────────┘                         └────────────────────┘                        └────────────────────┘
```

## Status

- ✅ End-to-end pairing — Mac shows a QR + bearer token; iPhone scans or
  types it; Keychain-persisted on both sides.
- ✅ End-to-end Claude Code sessions from the phone, with real-time SSE.
- ✅ Cursor-style folder picker — drill into any Mac subfolder, pin
  recents.
- ✅ Liquid Glass UI everywhere (`.glassEffect()`,
  `.buttonStyle(.glass | .glassProminent)`). iOS 26+ only.
- ✅ ComposerMenu — model / reasoning effort / mode pickers, slash
  commands, file attach (`.fileImporter`), @-mention picker over
  project files.
- ✅ Restart-on-change — switching model / effort / mode confirms with
  the user, spawns a fresh session in the same project.
- 🚧 Gemini multi-turn host — parser ready, persistent-session wiring
  in v1.5.
- 🚧 OpenCode adapter — `opencode serve` HTTP transport in v1.5.
- 🚧 Handoff between CLIs — needs the above; v1.5.
- 🚧 macOS Dashboard / Providers / Projects / Security tabs — v1.5.
- 🚧 iOS Live Activities — deferred (needs Apple Dev Team + APNs); v1
  uses local notifications.

## Requirements

- macOS 14 or later. Sonoma-and-up is what's tested.
- iOS 26 or later. **Locked at 26.0 for native Liquid Glass.**
- Tailscale on both ends (`brew install --cask tailscale`, sign in).
- One CLI agent on PATH:
  - `claude` (Claude Code) — `npm i -g @anthropic-ai/claude-code`
- Xcode 16+ for building.
- Homebrew for `xcodegen`.

## Three-step start

```bash
# 1. Clone + bootstrap
git clone https://github.com/ndolinschi/smoothie.git && cd smoothie
brew install xcodegen
./gradlew :shared:assemble                 # ~3 min first time
cd macOS && xcodegen generate && cd -
cd iOS   && xcodegen generate && cd -

# 2. Build + run the menubar daemon
open macOS/SmoothieMac.xcodeproj
# In Xcode: scheme "SmoothieMac" → ⌘R
# Menu bar shows a waveform icon. Click it.

# 3. Build + run the iOS app on your iPhone (or simulator)
open iOS/SmoothieiOS.xcodeproj
# Scheme "SmoothieiOS" → pick your device → ⌘R
# Connect screen → "Scan QR" (from the Mac popover) or "Enter
# manually" (with the host/port/token from the popover).
```

After pairing, the iPhone shows the home screen. Tap "Start a new
session", pick a project via the folder picker, pick Claude, send a
message. Events stream live.

## Architecture in one paragraph

A single **Kotlin Multiplatform Native** module (`shared/`) holds the
business logic: data models, adapter parsers (stream-json JSONL line
buffers), session state machines, SSE broker, safety prompt assembly,
pairing token codec. It compiles to a static `Shared.framework` for
`iosArm64 + iosSimulatorArm64 + macosArm64` and is consumed by two
thin SwiftUI shells.

The **macOS app** is `LSUIElement = true` — no Dock icon, just a menu
bar item. AppDelegate boots a Hummingbird HTTP server bound to the
Tailscale IP (or `127.0.0.1` with a UI warning if Tailscale isn't
running). Every route except `/health` is gated by a
`BearerAuthMiddleware`. CLI subprocesses are owned in Swift via
`Foundation.Process` + `Pipe`; stdout bytes are pumped into Kotlin's
`Session.ingestText(...)` which fans out parsed events to the
SharedFlow that the SSE route consumes.

The **iOS app** is a SwiftUI app on iOS 26 with `deploymentTarget:
"26.0"` so every surface uses Liquid Glass natively
(`.glassEffect()`, `.buttonStyle(.glassProminent)`). It pairs via QR
or a manual host/port/token form, persists the pairing in Keychain,
opens an SSE stream via `URLSessionDataDelegate` (Apple's
`URLSession.bytes(for:)` buffers SSE — don't use it), and reconnects
with exponential backoff.

See [AGENTS.md](./AGENTS.md) for the contributor guide.

## Dev cheatsheet

```bash
# Rebuild + assemble all shared targets
./gradlew :shared:assemble

# Regenerate Xcode projects after editing project.yml or adding files
cd macOS && xcodegen generate && cd -
cd iOS   && xcodegen generate && cd -

# Run macOS app from CLI
xcodebuild -project macOS/SmoothieMac.xcodeproj -scheme SmoothieMac \
  -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/SmoothieMac-*/Build/Products/Debug/SmoothieMac.app

# Run iOS app from CLI (iPhone 17 simulator)
xcodebuild -project iOS/SmoothieiOS.xcodeproj -scheme SmoothieiOS \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -configuration Debug build
xcrun simctl install booted "$(find ~/Library/Developer/Xcode/DerivedData -name SmoothieiOS.app -path '*iphonesimulator*' | head -1)"
xcrun simctl launch booted dev.smoothie.ios

# Health probe (no auth)
curl http://127.0.0.1:7749/health

# Read the live token from Keychain (for manual curl)
TOKEN=$(security find-generic-password -s dev.smoothie.menubar -a pairing-token -w)
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7749/adapters
```

## License

TBD.
