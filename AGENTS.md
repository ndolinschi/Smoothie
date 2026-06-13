# AGENTS.md

Working guide for AI coding agents (and humans) touching this repo. If
you're using Claude Code, also read [CLAUDE.md](./CLAUDE.md) for
Claude-specific notes; everything else applies to all agents.

## What Smoothie is

A phone-controlled wrapper around CLI coding agents. The user's Mac
runs a long-lived menu-bar daemon that spawns and manages the agent
processes (Claude Code, Gemini, OpenCode, and Antigravity / `agy`). The
user's iPhone runs a native SwiftUI app on iOS 26 that connects over
Tailscale (or Cloudflare Tunnel), controls the agents, and surfaces
their events in real time.

**There is no cloud.** Code never leaves the user's tailnet. The only
optional outgoing call is to Gemini Flash for handoff context
compression (v1.5) — opt-in with the user's own API key.

## Repo layout

```
Smoothie/
├── shared/                          # Kotlin Multiplatform Native framework
│   └── src/
│       ├── commonMain/kotlin/smoothie/
│       │   ├── adapters/            # AdapterParser + Claude/Gemini/OpenCode/Antigravity adapters + Registry
│       │   ├── session/             # Session, SessionManager, Subscription (Mutex-based actors)
│       │   ├── sse/                 # SSEBroker (per-id MutableSharedFlow)
│       │   ├── safety/              # SafetyPromptManager (base + per-CLI system + resume templates)
│       │   ├── pairing/             # PairingToken, QRPayload, SecureRandom (expect/actual)
│       │   ├── model/               # Wire types: CLIType, SessionDescriptor, SmoothieEvent, ProviderFeatures
│       │   └── util/                # nowEpochMillis, expect/actual
│       └── appleMain/kotlin/smoothie/
│           ├── util/Time.apple.kt
│           └── pairing/SecureRandom.apple.kt   # SecRandomCopyBytes
├── macOS/                           # macOS LSUIElement menu-bar app
│   ├── project.yml                  # xcodegen
│   └── Sources/
│       ├── App/                     # @main + AppDelegate + lifecycle
│       ├── Pairing/                 # KeychainStore + PairingService + CloudflaredHost
│       ├── Process/                 # SessionHost protocol + ProcessHost (Claude) + GeminiOneshotHost
│       │                            #   + OpenCodeServeHost + AntigravityOneshotHost + ProcessRegistry + AdapterProbe
│       ├── Preferences/             # ~/Library/Application Support/Smoothie/preferences.json
│       ├── Prompts/                 # SafetyHost — loads prompts/ into K/N SafetyPromptManager
│       ├── Server/                  # SmoothieHTTPServer + Routes (Hummingbird 2, multipart + SSE)
│       └── UI/                      # MenubarPopover (status pill, QR, Cloudflare toggle, re-pair)
├── iOS/                             # iOS 26 SwiftUI app + Widget extension
│   ├── project.yml                  # xcodegen — deploymentTarget 26.0 locked
│   ├── Sources/
│   │   ├── App/                     # SmoothieApp + URL handler + deep links
│   │   ├── Networking/              # APIClient, SSEClient (URLSessionDataDelegate),
│   │   │                            #   PairingStore (multi-pair), Keychain, WireTypes,
│   │   │                            #   APIError+Cancellation
│   │   ├── Notifications/           # LocalNotifier
│   │   ├── UI/Components/           # DesignTokens, StatusBadge, ProviderIcon, SheetRow,
│   │   │                            #   SmoothieBottomSheet, DashedBanner, DashedCircleIcon,
│   │   │                            #   VoiceWaveform, Date+Relative
│   │   ├── UI/Connect/              # ConnectView, QRScannerView, ManualPairView
│   │   ├── UI/Home/                 # HomeView (REF-4 tasks list), FolderPickerSheet,
│   │   │                            #   NewSessionView, RecentsStore
│   │   ├── UI/Pairings/             # PairingsSheet — list every paired Mac
│   │   ├── UI/Session/              # SessionView + SessionLiveStore + AgentStream + EventRow
│   │   │                            #   MessageInput + ModeChip + RepoChip + AttachSheet
│   │   │                            #   ImagePickerSheet + StagedAttachment + ComposerMenu
│   │   │                            #   ModeSheet + ActionChipsRow + DiffSheet + MarkdownText
│   │   │                            #   SyntaxHighlighter + VoiceDictator + VoiceUnavailableSheet
│   │   │                            #   SuggestionsBar + SmoothieSuggestions + MentionPickerSheet
│   │   └── Widget/                  # WidgetSnapshot + WidgetSnapshotStore (App Group bridge)
│   └── SmoothieWidget/              # WidgetKit extension target
├── prompts/                         # base safety + per-CLI system + resume templates
│   ├── base/safety.md
│   ├── claude-code/{system,resume}.md
│   ├── gemini/{system,resume}.md
│   └── opencode/{system,resume}.md
├── scripts/                         # install/uninstall LaunchAgent helpers
├── Smoothie.xcworkspace             # top-level workspace (macOS + iOS Xcode projects)
└── .claude/plans/                   # phase plan files (P0–P21) tracked here for /loop
```

## The Kotlin ↔ Swift boundary

Single rule of thumb: **if it talks POSIX, manages a subprocess, calls
Foundation, or touches AppKit/UIKit, write it in Swift.** Everything
else — parsers, session state, SSE fan-out, safety prompt assembly,
token generation, handoff serialization — lives in Kotlin Multiplatform
shared/.

Concretely:

- `shared/`: data models (`@Serializable` data classes), adapter
  parsers (line-buffered, stateless about process lifecycle), `Session`
  (in-memory event ring + `StateFlow<SessionState>` +
  `SharedFlow<SmoothieEvent>`), `SessionManager`, `SSEBroker`,
  `SafetyPromptManager`, pairing token codec.
- `macOS/`: `Foundation.Process` + `Pipe` wrapping CLI subprocesses,
  Hummingbird HTTP server, Keychain (Security framework), CoreImage QR
  generation, NSWorkspace, AppKit menubar.
- `iOS/`: SwiftUI views (flat dark coral palette — **NOT glass**),
  AVFoundation QR scanner, URLSession REST + SSE delegate, iOS
  Keychain, AVAudioEngine RMS for voice waveform, PHPickerViewController
  for image attach.

Kotlin and Swift exchange data through:

- `Session.ingestText(text:)` — Swift hands stdout chunks (UTF-8) to
  the Kotlin parser, which emits parsed events into its SharedFlow.
- `Session.injectEvent(event:)` — for HTTP-transport hosts
  (OpenCode, Antigravity), Swift skips the parser and pushes
  pre-built `SmoothieEvent`s directly.
- `Session.subscribeForSwift(onEvent:) -> Subscription` — Swift
  subscribes via a closure. Hummingbird's SSE route uses this to fan
  out frames to the iPhone.
- `Session.encodeUserMessage(content:) -> String` — Kotlin returns the
  exact bytes the CLI's stdin expects.

## Design language

The palette is a **warm, Claude-app-style** scheme: terracotta accent on
adaptive warm surfaces (cream paper in light mode, warm charcoal in dark).
It replaced the original Liquid Glass aesthetic (P16), then a brief mono
phase (P25), then the warm refresh. Tokens live in
`iOS/Sources/UI/Components/DesignTokens.swift`, where surfaces resolve via
`dynamic(light:dark:)` so they follow the system theme; accent/status/brand
hues are pinned.

| Token | Value | Role |
|---|---|---|
| `bgPrimary` | `#262624` dark / `#FAF9F5` light | screen body |
| `bgCard` | `#30302E` / `#FFFFFF` | row/card surfaces |
| `bgChip` | `#393937` / `#F0EEE6` | suggestion / chip backgrounds |
| `bgSheet` | `#30302E` / `#FAF9F5` | sheet body |
| `accent` | `#D97757` (pinned) | terracotta — send button, controls, inline code |
| `accentSoft` | `#D97757 15%` | inline-code wash |
| `bubbleUser` | `#393937` / `#F0EEE6` | user chat bubble (quiet — accent is for actions) |
| `onAccent` | white | foreground on terracotta |
| `textPrimary/Secondary/Tertiary` | system label tiers | type hierarchy |

**Don't reach for `.glassEffect()` or `.ultraThinMaterial`.** When a
new surface lands, pull from `SmoothieColor` / `SmoothieMetrics`. Glass
leftovers in older files (composer menu sheets, ProviderChip, etc.)
are being migrated incrementally.

## How to add a CLI adapter

1. **Add the case in `shared/.../model/CLIType.kt`** (`val
   executableName`, `val displayName`).
2. **Mirror the case in `iOS/.../Networking/WireTypes.swift::CLIWire`**
   and its `displayName` mapping. Also mirror in
   `iOS/Sources/Widget/WidgetSnapshot.swift::WireCLI` and the widget
   extension's `SessionWidgetView.swift` switch.
3. **Write the Kotlin parser** in
   `shared/.../adapters/<Name>Adapter.kt` conforming to
   `AdapterParser`. For stream-json CLIs, hold a line-accumulator on
   `ingest` and return `SmoothieEvent`s mapped to canonical
   `EventType`s. For HTTP-transport CLIs (OpenCode, Antigravity), a
   stub adapter with no-op `ingest` is fine — the host pushes events
   via `Session.injectEvent` directly.
4. **Register it** in `shared/.../adapters/AdapterRegistry.kt:init`.
5. **Decide the host shape** in `macOS/Sources/Process/`:
   - Persistent stream-json child (Claude) → reuse `ProcessHost`.
   - One-shot per turn (Gemini, Antigravity) → clone
     `GeminiOneshotHost` / `AntigravityOneshotHost`. Hold session-id
     and pass `--resume` / `-c` from turn 2.
   - Long-running local HTTP server (OpenCode) → clone
     `OpenCodeServeHost`. Parse the bound port from startup logs, then
     drive over REST + SSE.
   All conform to the `SessionHost` protocol.
6. **Branch on the new case in `ProcessRegistry.spawn`** to instantiate
   the right host.
7. **Drop a system + resume prompt** in `prompts/<cli>/{system,resume}.md`.
   `SafetyHost` loads them at startup; the assembled text is passed to
   the adapter's `launchArguments(_:systemPromptText:)`.
8. **Add an icon mapping** in
   `iOS/Sources/UI/Components/ProviderIcon.swift`. SwiftUI-drawn marks
   are preferred (no licensing risk); fallback is an SF Symbol.
9. **Add starter prompts** in
   `iOS/Sources/UI/Session/SmoothieSuggestions.swift` — three pills
   shown above the composer on a fresh session of that provider.

## Build commands

```bash
# Shared framework only (all Apple targets):
./gradlew :shared:assemble

# Regen Xcode projects after adding Swift files or editing project.yml:
xcodegen --spec macOS/project.yml --project macOS
xcodegen --spec iOS/project.yml   --project iOS

# macOS app:
xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieMac \
  -configuration Debug -destination 'platform=macOS' build

# iOS app (simulator):
xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

First `:shared:assemble` takes ~3 min; incremental is ~30 s. After K/N
signature changes, force a clean shared build:
`./gradlew :shared:compileKotlinMacosArm64 :shared:compileKotlinIosArm64
:shared:compileKotlinIosSimulatorArm64`.

## Hard rules

1. **Binding is `0.0.0.0` so the phone can reach the daemon over LAN or
   Tailscale regardless of which address `PairingService.resolveHost()`
   picked for the QR.** `resolveHost()` still chooses the *display* host
   (Tailscale CGNAT only if `/Applications/Tailscale.app` exists, else a
   private-range LAN address, else `127.0.0.1`). Because the listener is
   open on the LAN over plain HTTP, the bearer token is the only
   authority — the menubar warns when Tailscale isn't detected, and
   `BearerAuthMiddleware` throttles brute-force attempts. Tightening this
   (TLS, or re-gating the bind behind an explicit opt-in) is a tracked
   follow-up; don't loosen auth without a security review.
2. **Tokens never leave the user's device.** Pairing token is 32 random
   bytes generated by `SecureRandom` (K/N expect/actual,
   `SecRandomCopyBytes` on Apple). Stored in macOS / iOS Keychain. The
   user's provider tokens (`claude` / `gemini` / `opencode` / `agy`)
   are owned by those CLIs — Smoothie never reads or forwards them.
3. **No cloud.** The only outgoing call Smoothie itself makes is the
   optional Gemini Flash compression in `HandoffManager` (v1.5) —
   opt-in with the user's key in `Preferences.geminiFlashApiKey`.
4. **Destructive operations require explicit user confirmation.**
   Codified in `prompts/base/safety.md`. Never auto-`rm -rf`, never
   auto-`git push`, never `sudo`, never global package installs.
5. **Project paths must resolve under `$HOME`.**
   `Preferences.isPathAllowed(_:)` enforces it; `/sessions` POST
   returns 403 otherwise.
6. **Handoff between CLIs is always user-confirmed** (v1.5).
   Smoothie never auto-switches providers when one hits its limit — it
   surfaces the `LIMIT_REACHED` event, lets the user pick from the
   `HandoffView` sheet, and only then routes the serialised context to
   the new adapter.
7. **iOS 26 deployment target is locked.** We use modern SwiftUI
   features (`.contentTransition`, `.scrollContentBackground`,
   `.presentationCornerRadius`, `.presentationDragIndicator`,
   `WidgetKit` lock-screen widgets, `PHPickerViewController`). The
   deployment target is `26.0` in `iOS/project.yml`. No back-compat
   shims.
8. **Design tokens, not raw colors.** Pull from
   `iOS/Sources/UI/Components/DesignTokens.swift::SmoothieColor`
   instead of inlining `Color(hex: 0x…)` or `Color.white.opacity(…)`.
   Glass is gone (see Design language section).

## What's deferred to v1.5

Intentional cuts. The rest of the spec works without them:

- **Handoff between CLIs** — `HandoffView` UI exists; `ContextSerializer`,
  `ContextCompressor` (Gemini Flash), and `HandoffManager` not yet wired
  through the server.
- **macOS Dashboard / Providers / Projects / Security tabs** — today
  the menubar popover surfaces server status, pairing, Cloudflare
  toggle, re-pair, quit. The richer windowed settings UI follows.
- **iOS Live Activities + APNs push** — confirmed deferred. v1 uses
  local notifications via `UNUserNotificationCenter`.
- **Real provider SVG marks** — current `ProviderIcon` is hand-drawn in
  SwiftUI Canvas (Anthropic-style spokes for Claude, Google four-point
  star for Gemini, OpenAI knot for OpenCode, violet→cyan arrow for
  Antigravity). Bundling licensed vendor marks is a follow-up.
- **Codex adapter** — dropped per user.

## Plan file

Phase plans (P5 → present) live in
`.claude/plans/smoothie-mvp-prompt-soft-melody.md`. Read it before
shipping anything substantial — the file describes the rolling
checkpoint structure, design references, and risks.
