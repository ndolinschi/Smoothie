# CLAUDE.md

Project memory for [Claude Code](https://claude.com/claude-code) sessions
working on this repo. Read [AGENTS.md](./AGENTS.md) first — it has the
universal architecture and rules. This file adds Claude-Code-specific
notes that don't generalise to other agents.

## TL;DR for fresh sessions

- This is **Smoothie**: a Kotlin-Multiplatform shared/ + Swift macOS
  daemon + Swift iOS app. The Mac spawns CLI agents; the phone drives
  them over Tailscale.
- The current phase plan is in
  `.claude/plans/smoothie-mvp-prompt-soft-melody.md`. **Read it before
  starting anything substantial.** The plan documents P0 → P21 with
  per-phase checkpoints; P21 (Antigravity adapter) is the latest.
- Design language is **flat dark coral**, not glass. Tokens in
  `iOS/Sources/UI/Components/DesignTokens.swift`. Don't reintroduce
  `.glassEffect()` / `.ultraThinMaterial`.
- iOS target is **26.0 locked**; macOS daemon target is **14+**.

## Build cycle Claude should follow

```bash
# After K/N changes, force a shared rebuild so framework headers refresh:
./gradlew :shared:compileKotlinMacosArm64 \
          :shared:compileKotlinIosArm64 \
          :shared:compileKotlinIosSimulatorArm64

# After adding new Swift files, regen Xcode projects:
xcodegen --spec macOS/project.yml --project macOS
xcodegen --spec iOS/project.yml   --project iOS

# Then build both:
xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieMac \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -workspace Smoothie.xcworkspace -scheme SmoothieiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If the iOS build fails with "switch must be exhaustive" on `CLIWire` or
`WireCLI`, the widget extension's switches need the new case too — they
live in `iOS/SmoothieWidget/SessionWidgetView.swift`.

## Run cycle Claude should follow

```bash
# Kill stale daemon (Claude often hits a stale PID from a previous run):
pgrep -f "SmoothieMac.app/Contents/MacOS" | xargs -I{} kill -9 {}

# Launch fresh daemon
open ~/Library/Developer/Xcode/DerivedData/Smoothie-*/Build/Products/Debug/SmoothieMac.app

# Verify health
curl http://127.0.0.1:7749/health
# Expected: {"healthy":true,"version":"0.2.0"}

# Install + launch iOS app on the booted sim
SIM=$(xcrun simctl list devices booted -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print([v[0]['udid'] for v in d.values() if v][0])")
APP=$(find ~/Library/Developer/Xcode/DerivedData -name SmoothieiOS.app -path '*iphonesimulator*' | head -1)
xcrun simctl terminate "$SIM" dev.smoothie.ios 2>/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" dev.smoothie.ios
```

## Adapter probes (Claude does these often when adding a new CLI)

```bash
# Read the live pairing token from Keychain
TOKEN=$(security find-generic-password -s dev.smoothie.menubar -w)

# List adapters — confirm new CLI shows up with installed=true
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7749/adapters \
  | python3 -m json.tool
```

Common file paths Claude reaches for repeatedly:

- `macOS/Sources/Process/ProcessRegistry.swift` — per-CLI host branch.
- `macOS/Sources/Process/SessionHost.swift` — protocol every host
  conforms to.
- `shared/src/commonMain/kotlin/smoothie/adapters/AdapterRegistry.kt`
  — register new parsers here.
- `iOS/Sources/UI/Session/SessionView.swift` — `SessionLiveStore` lives
  inline (long file; flagged in the audit for extraction).
- `iOS/Sources/UI/Session/MessageInput.swift` — composer; voice +
  attachments + repo chip row.
- `iOS/Sources/Networking/PairingStore.swift` — multi-pair store; keys
  by SHA256 prefix of `host:port:scheme`.

## Workflow conventions

1. **Read the plan file before shipping a phase.** It documents the
   contract for what the user expects, including the named checkpoints
   they'll run to verify.
2. **Mark TaskUpdate `in_progress` / `completed` as you go.** Tasks
   visible in the user's UI; updating them is how you signal what's
   happening.
3. **Use the audit findings.** When the user asks for an audit, write
   it to chat (don't create a `.md` audit file unless asked).
4. **Don't write docs the user didn't ask for.** No proactive README /
   AGENTS / CLAUDE updates; the user calls those out explicitly.
5. **Avoid emojis in code or commits** unless the user asks. Comments
   inside files should be prose with WHY context.
6. **Commits use this style** (matches recent history):
   ```
   <phase>: <one-line summary in present tense>

   <optional 2–4 line body explaining WHY>

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   ```
   Don't use `--amend` unless the user asks. Don't push without
   explicit "push to origin" from the user.

## Common gotchas

- **DerivedData path** is
  `Smoothie-ghnvgljlsinkqxdmdcqtvmsaiskd/Build/Products/...` (workspace
  build). NOT the older `SmoothieMac-dbhpnqqsjngyrxdfizisuzlwdcsr`
  path. If you launch the wrong `.app`, the daemon is stale.
- **Tailscale false-positive on VPN interfaces.** The CGNAT range
  100.64.0.0/10 is shared with corporate VPNs. `PairingService` gates
  the auto-detect behind a check for `/Applications/Tailscale.app`. If
  Tailscale GUI isn't installed, bind to `127.0.0.1`.
- **Shared framework header staleness.** After any K/N signature
  change, Swift compile may fail with "cannot find type" until a
  clean shared rebuild. Force-rebuild all three targets.
- **xcodegen needs regen** every time a new Swift file is added —
  otherwise Xcode shows "cannot find X in scope".
- **Don't read `URLSession.bytes(for:)` for SSE.** Apple's
  implementation buffers; use `URLSessionDataDelegate` (see
  `iOS/Sources/Networking/SSEClient.swift`).
- **`agy` (Antigravity) outputs plain markdown**, not stream-json. The
  one-shot host buffers stdout and injects `MESSAGE` + `WAITING` events
  directly via `Session.injectEvent` on clean exit.

## Plan file conventions

When the user invokes `/loop`, work the next-unchecked phase in the
plan file. Update the plan with risks discovered during the phase and a
"Next action when execution resumes" pointer. Don't mark a phase
complete until the verification checkpoint is met locally.

## What Claude Code is NOT for in this repo

- Generating commits or pushes proactively.
- Adding cloud calls (any call outside the user's tailnet).
- Touching the user's provider tokens (Anthropic API key, Gemini API
  key, etc.). Those belong to the CLIs Smoothie wraps.
- Reintroducing Liquid Glass styling.
- Bypassing safety prompts in `prompts/base/safety.md`.
