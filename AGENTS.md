# AGENTS.md

Guide for AI coding agents working on this repo.

## What Smoothie is

A phone-controlled wrapper around CLI coding agents. Your Mac runs a long-lived Swift daemon that spawns and manages CLI agent processes (OpenCode, Claude Code, eventually Gemini and Codex). Your iPhone runs a native SwiftUI app that talks to the daemon over Tailscale.

Two pieces, both Swift:

- **`packages/server`** — Swift Package, executable. Hummingbird 2.x as the only external dep. Spawns CLI agents, parses their JSON output, exposes a small REST + SSE API.
- **`packages/mobile`** — iOS app (SwiftUI, iOS 17+). Xcode project generated from `project.yml` via xcodegen.

There is no JavaScript, no React Native, no shared TypeScript types, no web layer. Both sides are Swift. Wire types are duplicated by hand between server `Models.swift` and mobile `Wire.swift` — keep them in sync.

## Running locally

```bash
# Server (one terminal)
cd packages/server
swift run

# iOS app (one-time setup)
cd packages/mobile
./setup.sh                 # installs xcodegen if needed, runs `xcodegen generate`
open Smoothie.xcodeproj    # then build & run in Xcode
```

The server prints its bind address on start. The iOS app's connect screen takes either a Tailscale IP (`100.64.0.10`) or a local one (`127.0.0.1:7749`).

## Where things live

```
packages/server/Sources/SmoothieServer/
  main.swift               # entry point — startup + shutdown
  Config.swift             # port, allowed roots, Tailscale IP resolution
  Models.swift             # wire types (Codable structs)
  PTY/PTYProcess.swift     # posix_spawn-based PTY child process
  Adapters/
    AdapterProtocol.swift  # AgentAdapter protocol
    AdapterRegistry.swift  # discovers which CLIs are installed
    OpenCodeAdapter.swift  # HTTP transport via `opencode serve`
    ClaudeAdapter.swift    # PTY transport via `claude -p --output-format stream-json`
    GeminiAdapter.swift    # stub — throws notImplemented
    CodexAdapter.swift     # stub — throws notImplemented
  Session/
    Session.swift          # actor wrapping one adapter + subscriber list
    SessionManager.swift   # actor managing all sessions
  SSE/
    SSEBroker.swift        # SSE frame formatter
    SSEClient.swift        # SSE consumption (delegate-based URLSession)
  API/Router.swift         # Hummingbird routes
  Sleep/SleepPrevention.swift  # IOKit assertion

packages/mobile/Smoothie/
  SmoothieApp.swift        # @main App
  Theme/Theme.swift        # colors, fonts
  Models/Wire.swift        # mirrors server Models.swift
  Networking/
    API.swift              # REST client (URLSession async)
    SSEClient.swift        # SSE consumption (delegate-based URLSession)
  State/
    ServerStore.swift      # @Observable — connection state, health polling
    SessionStore.swift     # @Observable — one session's events + state
  Notifications/LocalNotifier.swift
  Views/                   # SwiftUI screens
```

## Adding a new CLI adapter

1. Add the case to `CLIType` in `Models.swift` (server) **and** `Wire.swift` (mobile).
2. Add the executable name to `AdapterRegistry.executableName`.
3. Implement `Adapters/<Name>Adapter.swift` conforming to `AgentAdapter`. The adapter owns its own transport — PTY, HTTP, JSON-RPC over stdio, whatever fits. The protocol only requires:
   - `var events: AsyncStream<SmoothieEvent>`
   - `func send(_ content: String) async throws`
   - `func terminate() async`
   - `func currentState() -> SessionState`
   - `static func make(config: AdapterStartConfig) async throws -> any AgentAdapter`
4. Add the case to `AdapterRegistry.make(cli:config:)` and `AdapterRegistry.supportedCLIs`.
5. Drop a system prompt at `prompts/<name>/system.md` — the router reads it and passes to the adapter via `AdapterStartConfig.systemPromptText`.
6. Add a label and icon mapping in the mobile `CLIType.label` extension.

## Hard rules

- **Never bind to `0.0.0.0`.** The server only binds to its detected Tailscale IP or `127.0.0.1`. Enforced in `Config.swift`.
- **No tokens stored anywhere.** Each CLI handles its own auth on the Mac. Smoothie never sees credentials.
- **No cloud, ever.** No telemetry. No analytics. No third-party services. Tailscale is the only network layer.
- **Single external Swift dep on server.** Hummingbird. That's it. No NIO add-ons, no JSON libraries, no logging frameworks — Foundation and the standard library are enough.
- **No JavaScript, no React Native, no Expo.** The app is native Swift.
- **Project paths are validated.** `Config.isPathAllowed(_:)` rejects anything outside the configured roots.
- **No background work on iOS we don't need.** Long-lived SSE doesn't survive backgrounding — that's accepted. Use local notifications (`LocalNotifier`) to re-engage the user.

## Common edits

- **Bump Hummingbird:** `packages/server/Package.swift`, then `swift package update`.
- **Add a server route:** `API/Router.swift`. Use the `jsonResponse(_:)` helper for typed responses; `errorResponse(status:message:)` for failures.
- **Add a wire field:** edit `Models.swift` and `Wire.swift` together. Test JSON round-trip in both directions.
- **Tweak SSE event mapping:** each adapter has its own translation logic (e.g. `OpenCodeAdapter.handleEvent` and `ClaudeAdapter.handleLine`). Don't centralize prematurely — the wire shapes vary too much across CLIs.

## Debugging tips

- Server logs go to stderr. `swift run | tee /tmp/smoothie.log` if you want to keep them.
- The server prints its bind address and the list of discovered adapters at startup. If an adapter is `stub`, the binary is installed but no Smoothie code drives it yet. If it's `missing`, the executable isn't on PATH.
- iOS: SwiftUI previews work — each view file has a `#Preview` block.
- SSE from curl: `curl -N http://127.0.0.1:7749/sessions/<UUID>/stream`.
