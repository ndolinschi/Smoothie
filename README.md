# Smoothie

Phone-controlled wrapper for CLI coding agents. Your Mac runs the agent
(Claude Code, Gemini, OpenCode, or Antigravity). Your iPhone drives it
over Tailscale or Cloudflare Tunnel. No cloud — code never leaves your
tailnet.

```
┌──────────────┐   Tailscale / Cloudflare    ┌────────────────────┐   pipe stdio / HTTP    ┌────────────────────┐
│  iPhone app  │ ◄────────────────────────►  │   macOS menubar    │ ◄────────────────────► │  CLI agent process │
│  (SwiftUI    │     HTTP + SSE              │   daemon           │   Foundation.Process   │  claude / gemini / │
│   iOS 26)    │     Bearer token            │   Hummingbird +    │   or local HTTP        │  opencode / agy    │
│              │                             │   K/N business     │   (per provider)       │                    │
└──────────────┘                             │   logic            │                        └────────────────────┘
                                             └────────────────────┘
```

## Status

Shipped end-to-end (`main` is green):

- **Pairing** — Mac shows a QR + bearer token; iPhone scans or types it;
  Keychain-persisted on both sides; multiple Macs from one phone.
- **Four CLI adapters** — Claude Code (pipe-based stream-json), Gemini
  (one-shot `gemini -p` with `--resume`), OpenCode (`opencode serve` over
  REST + SSE), Antigravity / `agy` (one-shot with `-c` continue).
- **Cross-network** — auto-detect Tailscale CGNAT IP if the GUI is
  installed; otherwise bind `127.0.0.1`. Optional Cloudflare Tunnel host
  for use over LTE without Tailscale.
- **Composer** — model / reasoning effort / mode pickers per provider,
  slash commands sheet, @-mentions, file attach, **photo attach** for
  Claude (full base64-image content blocks in stream-json), voice
  dictation with live amplitude waveform.
- **Soft mode switching** — Code ↔ Plan keeps the same session running;
  a divider lands in the stream once the in-flight turn finishes.
- **Live chat polish** — markdown renderer with syntax-highlighted code
  blocks (regex-based, no deps), unified `+`/`-` diff sheet, collapsible
  thinking blocks, sticky scroll-to-bottom, abort button in the send
  slot while the agent thinks.
- **Home & widget** — REF-styled tasks list (All / Completed filters,
  dismissible tip banner, dashed-circle row icons, swipe-to-delete) plus
  a Lock-Screen / Home-Screen widget showing live session state via App
  Group snapshot.
- **Notifications** — local `UNUserNotificationCenter` fires on
  `waiting` / `done` while the app is backgrounded; tapping deep-links
  into the session.

Deferred to v1.5:

- Handoff between CLIs (HandoffView UI ready, `ContextSerializer` /
  `ContextCompressor` / Gemini-Flash compression not wired).
- macOS Dashboard / Providers / Projects / Security tabs.
- iOS Live Activities + APNs push (needs a paid Apple Dev Team +
  user-provided `.p8`).
- Codex (dropped).

## Requirements

- **macOS 14 or later** (Sonoma+). The menubar daemon is not sandboxed
  because it spawns subprocesses.
- **iOS 26 or later** — locked at `26.0` in `iOS/project.yml`.
- **Xcode 16+** for building.
- **Homebrew** for `xcodegen`.
- At least one CLI agent on PATH (pick any combination):
  - `claude` (Claude Code) — `npm i -g @anthropic-ai/claude-code`
  - `gemini` (Gemini CLI) — `npm i -g @google/gemini-cli`
  - `opencode` (OpenCode) — `brew install sst/tap/opencode`
  - `agy` (Antigravity) — `brew install --cask antigravity`
- Cross-network connectivity — pick one:
  - **Tailscale** — `brew install --cask tailscale`, sign in on both
    devices. Smoothie auto-detects the CGNAT IP. **Recommended.**
  - **Cloudflare Tunnel** — `brew install cloudflared`. Toggle in the
    menubar popover; spawns `cloudflared tunnel --url
    http://127.0.0.1:7749` and pairs over the `*.trycloudflare.com`
    URL.

## Three-step start

```bash
# 1. Clone + bootstrap
git clone https://github.com/ndolinschi/Smoothie.git && cd Smoothie
brew install xcodegen
./gradlew :shared:assemble                 # ~3 min first time
xcodegen --spec macOS/project.yml --project macOS
xcodegen --spec iOS/project.yml   --project iOS

# 2. Build + run the menubar daemon
open Smoothie.xcworkspace
# In Xcode: scheme "SmoothieMac" → ⌘R. Menu bar gets a waveform icon.

# 3. Build + run the iOS app on your iPhone (or simulator)
# Scheme "SmoothieiOS" → pick your device → ⌘R.
# Connect screen → "Scan QR" (from the Mac popover) or "Enter manually".
```

After pairing, the iPhone shows the home tasks list. Tap the coral `+`
button → folder picker → pick a project → tap **New session**. Pick a
provider, send a message. Events stream live.

## Architecture in one paragraph

A single **Kotlin Multiplatform Native** module (`shared/`) owns the
business logic: data models, adapter parsers (stream-json line
accumulators), `Session` (in-memory event ring + `StateFlow` +
`SharedFlow`), `SessionManager`, `SSEBroker`, `SafetyPromptManager`,
pairing token codec. It compiles to a static `Shared.framework` for
`iosArm64 + iosSimulatorArm64 + macosArm64` and is consumed by two
SwiftUI shells.

The **macOS app** is `LSUIElement = true` — no Dock icon, just a menu
bar item. AppDelegate boots a Hummingbird 2 HTTP server bound to the
Tailscale CGNAT IP (only if `/Applications/Tailscale.app` is installed)
or `127.0.0.1`. Every route except `/health` is gated by
`BearerAuthMiddleware`. CLI subprocesses are owned in Swift through one
of four host classes: `ProcessHost` (Claude — pipes), `GeminiOneshotHost`
(Gemini — one-shot per turn with `--resume`), `OpenCodeServeHost`
(OpenCode — spawns `opencode serve`, drives over REST + SSE), and
`AntigravityOneshotHost` (`agy` — one-shot with `-c`).

The **iOS app** is SwiftUI on iOS 26 with the new dark-coral palette
(`#0E0E0E` body, `#141414` card, `#1A1A1A` chip, `#ED7C5C` coral
accent — see `iOS/Sources/UI/Components/DesignTokens.swift`). It pairs
via QR or manual host/port/token, persists pairings in Keychain,
opens an SSE stream via a `URLSessionDataDelegate` (Apple's
`URLSession.bytes(for:)` buffers SSE — don't use it), and reconnects
with exponential backoff. Voice input uses `SFSpeechRecognizer` with
an `AVAudioEngine` tap that publishes RMS amplitude to drive the
waveform composer.

See [AGENTS.md](./AGENTS.md) for the contributor / agent guide and
[CONTRIBUTING.md](./CONTRIBUTING.md) for the PR flow.

## Dev cheatsheet

```bash
# Rebuild shared framework
./gradlew :shared:assemble

# Regen Xcode projects after editing project.yml or adding Swift files
xcodegen --spec macOS/project.yml --project macOS
xcodegen --spec iOS/project.yml   --project iOS

# Build macOS daemon
xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieMac \
  -configuration Debug -destination 'platform=macOS' build

# Build iOS app for the iPhone 17 simulator
xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Launch the macOS daemon
open ~/Library/Developer/Xcode/DerivedData/Smoothie-*/Build/Products/Debug/SmoothieMac.app

# Install + launch the iOS app on the booted simulator
APP=$(find ~/Library/Developer/Xcode/DerivedData -name SmoothieiOS.app -path '*iphonesimulator*' | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted dev.smoothie.ios

# Health probe (no auth required)
curl http://127.0.0.1:7749/health

# Read the live token from Keychain and list adapters
TOKEN=$(security find-generic-password -s dev.smoothie.menubar -w)
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7749/adapters
```

First `:shared:assemble` build takes ~3 min (K/N bootstraps three Apple
targets); incremental is ~30 s.

## License

[MIT](./LICENSE) © 2026 ndolinschi
