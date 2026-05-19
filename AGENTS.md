# AGENTS.md

Working guide for AI coding agents (and humans) touching this repo.

## What Smoothie is

A phone-controlled wrapper around CLI coding agents. The user's Mac
runs a long-lived menu-bar daemon that spawns and manages the agent
processes (Claude Code today; Gemini and OpenCode follow). The user's
iPhone runs a native SwiftUI app on iOS 26 (Liquid Glass) that
connects over Tailscale, controls the agents, and surfaces their
events in real time.

There is **no cloud**. Code never leaves the user's tailnet. The only
optional outgoing call is to Gemini Flash for handoff context
compression in P10 — and that's user-opt-in with their own key.

## Repo layout

```
smoothie/
├── shared/                          # Kotlin Multiplatform Native framework
│   └── src/
│       ├── commonMain/kotlin/smoothie/
│       │   ├── adapters/            # AdapterParser + ClaudeAdapter + GeminiAdapter + AdapterRegistry
│       │   ├── session/             # Session, SessionManager, Subscription (Mutex-based actors)
│       │   ├── sse/                 # SSEBroker (per-id MutableSharedFlow)
│       │   ├── safety/              # SafetyPromptManager
│       │   ├── pairing/             # PairingToken, QRPayload, SecureRandom (expect/actual)
│       │   ├── model/               # Wire types
│       │   └── util/                # Time
│       ├── appleMain/kotlin/smoothie/
│       │   ├── util/Time.apple.kt
│       │   └── pairing/SecureRandom.apple.kt (SecRandomCopyBytes)
│       └── iosMain / macosMain      # empty — no platform-specific code today
├── macOS/                           # macOS LSUIElement menu-bar app
│   ├── project.yml                  # xcodegen
│   └── Sources/
│       ├── App/                     # @main + AppDelegate + lifecycle
│       ├── Pairing/                 # KeychainStore + PairingService
│       ├── Process/                 # ProcessHost, ProcessRegistry, AdapterProbe
│       ├── Preferences/             # Preferences (~/Library/Application Support/Smoothie/preferences.json)
│       ├── Prompts/                 # SafetyHost
│       ├── Server/                  # SmoothieHTTPServer + Routes (Hummingbird 2)
│       └── UI/                      # MenubarPopover
├── iOS/                             # iOS 26 SwiftUI app
│   ├── project.yml                  # xcodegen — deploymentTarget 26.0 locked
│   └── Sources/
│       ├── App/                     # @main + RootView
│       ├── Networking/              # WireTypes, APIClient, SSEClient, PairingStore, Keychain
│       └── UI/
│           ├── Components/          # StatusBadge, ProviderIcon
│           ├── Connect/             # ConnectView, QRScannerView, ManualPairView
│           ├── Home/                # HomeView, NewSessionView, FolderPickerSheet, RecentsStore
│           └── Session/             # SessionView, AgentStream, EventRow, MessageInput,
│                                    # ComposerMenu, MentionPickerSheet, StagedAttachment
├── prompts/                         # safety + per-CLI system + resume prompts
└── Smoothie.xcworkspace             # macOS + iOS Xcode projects (xcodegen-generated)
```

## The Kotlin ↔ Swift boundary

Single rule of thumb: **if it talks POSIX, manages a subprocess, calls
Foundation, or touches AppKit/UIKit, write it in Swift.** Everything
else — parsers, session state, SSE fan-out, safety prompt assembly,
token generation, handoff serialization — lives in Kotlin
Multiplatform shared/.

Concretely:

- `shared/`: data models (Codable + Sendable Kotlin equivalents),
  adapter parsers (line-buffered, stateless about process lifecycle),
  Session (in-memory event ring + StateFlow + SharedFlow),
  SessionManager, SSEBroker, SafetyPromptManager, pairing token codec.
- `macOS/`: `Foundation.Process` + `Pipe` wrapping CLI subprocesses,
  Hummingbird HTTP server, Keychain (Security framework), CoreImage
  QR generation, NSWorkspace, AppKit menubar.
- `iOS/`: SwiftUI views (Liquid Glass), AVFoundation QR scanner,
  URLSession REST + SSE delegate, iOS Keychain.

Kotlin and Swift exchange data through:

- `Session.ingestText(text:)` — Swift hands stdout chunks (UTF-8) to
  the Kotlin parser. Kotlin emits parsed events into its SharedFlow.
- `Session.subscribeForSwift(onEvent:) -> Subscription` — Swift
  subscribes via a closure callback. The Kotlin protocol
  `Subscription.close()` tears the subscription down. Hummingbird's
  SSE route uses this to fan out frames.
- `Session.encodeUserMessage(content:) -> String` — Kotlin returns the
  exact bytes the CLI's stdin expects.

## How to add a CLI adapter

1. **Add the case in `shared/.../model/CLIType.kt`** (`val
   executableName`, `val displayName`).
2. **Mirror the case in `iOS/.../Networking/WireTypes.swift`**
   (`CLIWire` enum and its `displayName` mapping).
3. **Write the Kotlin parser** in
   `shared/.../adapters/<Name>Adapter.kt` conforming to
   `AdapterParser`. Stateful line-accumulator on `ingest`. Return
   `SmoothieEvent`s mapped to the canonical `EventType`s. Declare
   `ProviderFeatures` defaults (slash commands, models, modes).
4. **Register it** in
   `shared/.../adapters/AdapterRegistry.kt:init`.
5. **Decide the host shape** in `macOS/Sources/Process/`. If the CLI
   is a persistent stream-json child like Claude, no new code needed —
   `ProcessHost` + `ProcessRegistry.spawn` handles it. If it's
   per-message respawn (Gemini) or HTTP transport (OpenCode), write a
   sibling host class that exposes the same surface to Routes.
6. **Drop a system + resume prompt** in
   `prompts/<cli>/{system,resume}.md`. `SafetyHost` loads them at
   startup and `SafetyPromptManager.assembledSystemPrompt(cli:)`
   returns the assembled text for the adapter's launch args.
7. **Add an icon mapping** in
   `iOS/Sources/UI/Components/ProviderIcon.swift`. Drop an SVG into
   `Assets.xcassets/Providers/<rawValue>.svg` for the branded glyph;
   absent that, the SF Symbol fallback runs.

## Build commands

```bash
# Shared framework only (all Apple targets):
./gradlew :shared:assemble

# macOS app:
cd macOS && xcodegen generate
xcodebuild -project SmoothieMac.xcodeproj -scheme SmoothieMac \
  -configuration Debug build

# iOS app (simulator):
cd iOS && xcodegen generate
xcodebuild -project SmoothieiOS.xcodeproj -scheme SmoothieiOS \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -configuration Debug build

# Run macOS app: open the built .app from DerivedData
# Run iOS app: xcrun simctl install booted <.app>; xcrun simctl launch booted dev.smoothie.ios
```

First build of `:shared:assemble` takes ~3 minutes (K/N compiler bootstraps three targets); incremental is ~30 s.

## Hard rules

1. **Never bind the server to `0.0.0.0`.** Tailscale IP or
   `127.0.0.1`. Enforced in `PairingService.resolveHost()` — don't
   change it without a security review.
2. **Tokens never leave the user's device.** Smoothie's pairing token
   is 32 random bytes generated locally and stored in macOS / iOS
   Keychain. The token is the *only* bearer credential — the user's
   `claude` / `gemini` / `opencode` provider tokens never pass through
   Smoothie.
3. **No cloud.** The only network call Smoothie itself makes is the
   optional Gemini Flash compression in P10's HandoffManager — and
   it's opt-in with the user's key from `Preferences.geminiFlashApiKey`.
4. **Destructive operations require explicit user confirmation.** Live
   in `prompts/base/safety.md`. Apply at runtime: never auto-`rm -rf`,
   never auto-`git push`, never `sudo`, never global package installs.
5. **Project paths must resolve under `$HOME`.**
   `Preferences.isPathAllowed(_:)` enforces it; `/sessions` POST
   rejects with 403 otherwise.
6. **Handoff between CLIs is always user-confirmed** (P10 — landing in
   v1.5). Smoothie never auto-switches providers because one ran out
   of tokens — it surfaces the LIMIT_REACHED event, lets the user pick
   the alternate from the HandoffView sheet, and only then routes the
   serialized context to the new adapter.
7. **iOS 26 Liquid Glass is a hard requirement.** Every surface uses
   `.glassEffect()` / `.buttonStyle(.glass | .glassProminent)`. No
   fallback materials for older iOS. The deployment target is locked
   at 26.0 in `iOS/project.yml`.

## What's deferred to v1.5

These are intentional cuts — the rest of the spec works without them:

- **Gemini multi-turn host** — per-message respawn with `--resume
  <session_id>` (Kotlin parser is shipped; Swift host wiring is the
  bit left).
- **OpenCode adapter** — needs HTTP-transport host (`opencode serve`
  subprocess + REST/SSE client).
- **Handoff** between CLIs (P10) — requires the above two to be wired.
  `UniversalContext` + `ContextSerializer` design is in the plan,
  implementation lands with Gemini's host.
- **macOS Dashboard / Providers / Projects / Security views** (P11) —
  today the menu-bar popover surfaces server status, pairing, and
  quit; the richer windowed settings UI follows.
- **iOS Live Activities + APNs push** — confirmed deferred. v1 uses
  local notifications only when the app is foreground or briefly
  transitioning.
- **Real provider SVG marks** — licensing pass needed; current
  ProviderIcon is SF Symbol-based with brand colours.
- **Codex adapter** — dropped per user.
