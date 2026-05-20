# Contributing to Smoothie

Thanks for your interest. Smoothie is a Kotlin Multiplatform Native +
Swift macOS + Swift iOS project. Contributions are welcome — read this
file end-to-end before sending a PR so we both spend less time on
mechanical comments.

## Code of conduct

Be respectful. Disagree on technical merits, not on people. We follow
the spirit of [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
Maintainers may close issues or PRs that breach this.

## Quick links

- High-level architecture, build commands, hard rules:
  [AGENTS.md](./AGENTS.md)
- Working with AI agents on this repo (Claude Code in particular):
  [CLAUDE.md](./CLAUDE.md)
- Phase-by-phase rolling plan with verification checkpoints:
  `.claude/plans/smoothie-mvp-prompt-soft-melody.md`
- License: [MIT](./LICENSE)

## Setting up your dev environment

```bash
# 1. Clone + bootstrap
git clone https://github.com/ndolinschi/Smoothie.git
cd Smoothie
brew install xcodegen

# 2. Shared framework (~3 min first time, ~30s incremental)
./gradlew :shared:assemble

# 3. Regen Xcode projects
xcodegen --spec macOS/project.yml --project macOS
xcodegen --spec iOS/project.yml   --project iOS

# 4. Open the workspace
open Smoothie.xcworkspace
```

You need:

- macOS 14+ on Apple Silicon
- iOS 26+ device or simulator (target locked)
- Xcode 16+
- One CLI agent on PATH if you want to actually drive sessions while
  you work (`claude`, `gemini`, `opencode`, or `agy`)

## Filing an issue

Before opening: search existing issues first. Then include:

- **macOS version** + **iOS version** (`sw_vers`, sim/device info)
- **Xcode version**
- **Which CLI agent** is involved (and its `--version` output)
- **Reproduction steps** — fewer is better; the minimum sequence to
  trigger
- **Expected vs actual**
- **Daemon logs** if the daemon is involved. Run with Xcode attached,
  copy stderr.

For UX bugs include a screenshot or screen recording.

## Branch + commit conventions

- Branch from `main`. Name branches with a scope prefix:
  `phase/p22-x`, `fix/picker-drill`, `docs/contributing`,
  `refactor/sessionlivestore`.
- One topic per PR. If you find yourself making unrelated changes,
  split them.
- Commits use this style (matches `git log`):

  ```
  <scope>: <one-line summary in present tense>

  <optional body — explain WHY, not WHAT>
  ```

  Examples from the existing history:

  ```
  p21: antigravity (agy) adapter + visible drill-in affordance in folder picker
  ui: drop per-entry card in DiffSheet, separate entries with a hairline
  fix: tailscale auto-detect only when /Applications/Tailscale.app exists
  ```

- Prefer **new commits** over `--amend`. Pre-commit hooks are not
  configured today but plan to land — write commit messages that will
  read well in `git log --oneline`.
- Do **not** include emojis in commits or code comments unless the
  user explicitly requests it.

## What a good PR looks like

1. **Tied to a tracked issue or phase.** If you're freelancing a
   change, open an issue first so we agree on scope.
2. **Architecture-aware.** Read the K/N ↔ Swift boundary section in
   AGENTS.md. If your change crosses it (parsing, session state, SSE
   fan-out), the work probably belongs in `shared/`.
3. **Uses design tokens.** Pull from
   `iOS/Sources/UI/Components/DesignTokens.swift`. No raw `Color(hex:)`
   or `Color.white.opacity(...)` outside that file.
4. **Doesn't reintroduce glass.** The Liquid Glass aesthetic was
   intentionally dropped in P16 in favour of flat dark coral. If you
   genuinely need a material effect, raise it in the issue first.
5. **Doesn't add cloud calls.** Smoothie's tailnet-only promise is
   load-bearing. The one allowed exception (Gemini Flash for handoff
   compression) is opt-in with the user's own key.
6. **Builds clean.** Run both `xcodebuild` invocations from AGENTS.md
   before opening the PR. Warnings allowed for now; new errors are not.
7. **Updates AGENTS.md / CLAUDE.md / README.md when relevant.** New
   adapter? Add the recipe. New hard rule? Add it. Changed the
   K/N ↔ Swift surface? Update the boundary section.

## Adding a new CLI adapter

The canonical recipe is in [AGENTS.md § "How to add a CLI adapter"](./AGENTS.md#how-to-add-a-cli-adapter).
Short version:

1. `shared/.../model/CLIType.kt` — new enum case
2. `iOS/.../Networking/WireTypes.swift::CLIWire` — mirror the case
3. `iOS/Sources/Widget/WidgetSnapshot.swift` + widget switch — mirror
4. `shared/.../adapters/<Name>Adapter.kt` — parser implementing
   `AdapterParser`
5. `shared/.../adapters/AdapterRegistry.kt` — register it
6. `macOS/Sources/Process/<Name>Host.swift` — host class conforming to
   `SessionHost` (clone the closest existing host: Claude / Gemini /
   OpenCode / Antigravity)
7. `macOS/Sources/Process/ProcessRegistry.swift` — branch on the new
   case in `spawn`
8. `prompts/<cli>/{system,resume}.md`
9. `iOS/Sources/UI/Components/ProviderIcon.swift` — branded glyph
10. `iOS/Sources/UI/Session/SmoothieSuggestions.swift` — three starter
    prompts

The Antigravity addition (`p21`) is a good worked example — see commit
`3cea037`.

## Style notes

- **Swift**: Swift 6 strict concurrency. `@MainActor` on view types and
  observable stores. No force unwraps in production paths.
- **Kotlin**: `kotlinx.serialization` for wire types. Coroutines for
  async; `Mutex` for shared mutable state inside actor-like classes.
  Don't add Kotlin reflection.
- **No `0.0.0.0` binds, ever.** Tailscale CGNAT (gated by
  `/Applications/Tailscale.app` existence) or `127.0.0.1`.
- **Destructive ops require user confirm.** Encoded in
  `prompts/base/safety.md`. Don't relax it.
- **Comments are sparse and explain WHY.** Skip line-level commentary;
  call out non-obvious decisions, perf rationales, security trade-offs.

## Testing

Honest truth: there is no automated test suite yet. We rely on
per-phase checkpoints from the plan file and manual smoke runs:

1. Pair macOS daemon ↔ iOS simulator
2. Hit `/health` (no auth) → `{"healthy":true,"version":"0.2.0"}`
3. Hit `/adapters` (bearer) → all installed CLIs listed with
   `installed: true`
4. Create a session for each CLI you can install, send a message,
   observe live SSE events
5. Multipart photo attach on Claude returns a description of the image

Adding tests (XCTest for Swift, K/N test target for `shared/`) is
welcome. Open an issue first so we can agree on what to cover.

## Security disclosure

Found a security issue? **Don't open a public issue.** Email
`security@smoothie.dev` (placeholder — replace with actual contact if
you fork this) with a description and minimal reproduction. We'll
acknowledge within 72 hours.

The threat model is:

- **Trust boundary** = the user's Tailscale network (or Cloudflare
  Tunnel `*.trycloudflare.com` URL). Bearer token is the only
  credential. Token rotates via the menubar "Re-pair" button.
- **Off-tailnet attackers** should never see anything but `/health`.
- **On-tailnet attackers without the token** should never see anything
  but `/health`.
- **A compromised CLI subprocess** is a fact of life — Smoothie wraps
  agents that read your filesystem; we can't sandbox them while still
  doing useful work.

## License

By contributing, you agree your contributions are licensed under the
[MIT License](./LICENSE).
