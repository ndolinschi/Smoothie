# Smoothie iOS Design Refresh — coral-mirror

Phase plan for bringing the Smoothie iOS app to visual parity with the
Claude Code mobile reference. macOS (Gin) is scoped as a follow-up
after iOS lands; see P26 stub at the bottom.

## Scope decisions (locked)

- **Target:** Smoothie (iOS) first. Gin (macOS) deferred to P26.
- **Patterns to deliver:** suggestion chips + repo chips, model picker
  dropdown, repository picker bottom sheet, refined composer + cloud
  badge — i.e. all four pattern groups.
- **Depth:** full design system refresh (token layer first, then
  surfaces).
- **Mockups:** written spec only. No Figma; reference screenshots
  attached to the originating session.

## Reference summary

Claude Code mobile, captured 2026-05-23:

1. Header puts the model name **centered** with a chevron — tapping
   it opens a compact rounded card listing 3–4 models, each with a
   one-line descriptor and a checkmark on the active row.
2. Below the header sits a small cloud-icon capsule (e.g. "Default")
   denoting the cloud environment / preset. Visual only in our first
   pass.
3. Idle / empty session shows a **"Suggestions"** label with a stack
   of full-width quick-action chips ("Create or update my CLAUDE.md
   file", "Search for a TODO comment and fix it", etc.).
4. A persistent repo chips row sits above the composer: a leading
   **+** button followed by GitHub-icon chips ("owner/repo"). Tapping
   + opens a repository picker bottom sheet (search, GitHub-styled
   rows, checkmark for selected).
5. Composer is a single rounded rect with "Code anything…"
   placeholder, a `</> Code` mode chip, paperclip attach, mic, and a
   coral arrow-up send button.

## Inventory anchors

Current iOS files relevant to the refresh:

- `iOS/Sources/UI/Components/DesignTokens.swift` — flat-coral tokens
  exist; lacks surface-tier layering, chip/pill style tokens, and an
  explicit env-pill style.
- `iOS/Sources/UI/Session/SessionView.swift:132-173` — toolbar with
  model chip + mode pill. Needs centered-model rebuild and a separate
  env capsule below.
- `iOS/Sources/UI/Session/MessageInput.swift` — composer already has
  a suggestions bar (lines 51–56), a single `RepoChip` (line 65), and
  an actions row. Suggestions/repo treatments need a visual refresh
  and the repo row needs to become multi-chip with a + entry point.
- `iOS/Sources/UI/Session/RepoChip.swift` — read-only chip today; no
  picker UI exists.
- `iOS/Sources/UI/Session/ComposerMenu.swift:11-204` — `ModelPickerSheet`
  today is a NavigationStack with REASONING EFFORT / MODELS sections
  and a search field. Will be replaced (or wrapped) by a centered
  dropdown popover-style menu, with the existing full sheet kept only
  for power-user search.
- `iOS/Sources/UI/Components/SmoothieBottomSheet.swift` — shared
  sheet shell. Reused for the new repo picker.
- `iOS/Sources/UI/Components/SheetRow.swift` — reusable glyph + title
  + subtitle row. Repo picker rows will conform.

## Phase plan

### P25.a — Token expansion (foundation)

Extend `DesignTokens.swift` so every later phase reads from a token
rather than a literal.

Add:

- **Surface tiers:** `surface0` (page bg, alias to `bgPrimary`),
  `surface1` (cards, alias to `bgCard`), `surface2` (chips/inputs,
  alias to `bgChip`), `surface3` (popover/menu, new — slightly
  lighter than `bgSheet`, e.g. `0x1C1C1C`).
- **Chip styles:** `chipBg`, `chipBgPressed`, `chipStroke`,
  `chipLabel`. Match the soft outlined capsule seen on the repo +
  env capsules in the reference.
- **Env pill:** `envPillBg` (same as `chipBg`), `envPillIcon`
  (textSecondary tint), `envPillStroke`.
- **Menu / dropdown:** `menuBg` (= `surface3`), `menuStroke`,
  `menuRowHover`, `menuDivider`.
- **Spacing scale:** introduce `space2/4/6/8/12/16/20/24` instead of
  ad-hoc literals. Keep existing `rowPaddingH/V` as aliases.

Checkpoint: build green; no visual diff yet because nothing reads the
new tokens.

### P25.b — Centered model dropdown

Rebuild the principal toolbar item in `SessionView.swift` so the
model name + chevron sits centered (`ToolbarItem(placement:
.principal)` with `HStack { Text; Image(systemName: "chevron.down") }`).

Replace the current full-screen `ModelPickerSheet` invocation on the
header tap with a compact popover/menu styled per screenshot 2:

- Rounded card (`cornerLg`, `surface3` bg, hairline stroke).
- Each row: model name (15pt semibold) + descriptor line (13pt
  secondary). Selected row gets a leading checkmark in `textPrimary`.
- Anchored just below the toolbar; appears via SwiftUI `Menu` or a
  custom popover. Prefer `Menu` for accessibility, but customize via
  `.menuStyle` to match the rounded-card look. If `Menu` cannot
  match, use a `.popover` with `.presentationCompactAdaptation(.popover)`.

Keep the existing search-enabled `ModelPickerSheet` reachable from
the attach menu (long power-user list); deletion comes later if it
turns out to be redundant.

Checkpoint: tapping the centered model label opens the dropdown in
~80px-wide rounded card; selecting a model switches the session.

### P25.c — Cloud env pill

Add a small `EnvPill` view rendered just below the navigation bar in
`SessionView`. Default content: cloud icon + "Default" label. Use
`envPill*` tokens. First pass is visual only — tap is a no-op or a
disabled chevron. Wiring to a real environment store is out of scope
for P25; document the binding point so P26 (or a future env phase)
can plug in.

Placement: centered, above the message stream, with `8pt` top and
`16pt` horizontal padding. Hidden when the connection banner is
visible to avoid stacking two thin pills.

Checkpoint: pill renders on every session screen; visible in empty
state screenshot side-by-side with the reference.

### P25.d — Suggestion chips refresh

`MessageInput.swift` already renders suggestions on a fresh session.
Treatments to update:

- Render under a `"Suggestions"` section header (13pt, `textSecondary`,
  uppercase off — matches the reference).
- Chips become full-width rounded rects (`cornerLg`, `chipBg`,
  `chipStroke`), 14pt label, left-aligned.
- Highlight code-like tokens (`CLAUDE.md`, `TODO`) inline with
  `accentSoft` background and `accent` foreground, monospace. Keep
  the existing bracketed-token logic; just retheme it.
- Sourcing: keep the suggestion strings hard-coded for the MVP but
  factor them out to a `SuggestionCatalog` enum so the next phase
  can introduce per-repo / per-mode variants.

Checkpoint: idle session shows 3 suggestion chips that match the
reference within a 4-px tolerance on padding.

### P25.e — Multi-repo chips row + entry point

Replace the single `RepoChip` row with a horizontally-scrolling
`RepoChipsRow`:

- Leading `+` button (32-pt circle, `chipBg`, `chipStroke`,
  `textSecondary` plus glyph). Tap opens the new repo picker
  (P25.f).
- Followed by zero-or-more `RepoChip`s, each showing a GitHub icon
  (`Image("github.mark")` or `SF Symbol: chevron.left.forwardslash.chevron.right`
  fallback) + `owner/repo` label. Active chip gets `chipStroke` =
  `accent` and bold label.
- Currently selected repo is the one with the accent stroke;
  tapping a non-active chip switches selection.

Wiring:

- Add `selectedRepoId: RepoId?` and `availableRepos: [Repo]` to
  `SessionLiveStore` (currently inlined in `SessionView.swift`).
- Repo metadata source: reuse the existing pairing/host context —
  for the first pass the `availableRepos` list is what the daemon
  reports as cloned working trees. If the daemon doesn't yet
  enumerate repos, ship with `availableRepos = [currentRepo]` and
  log a TODO.

Checkpoint: row scrolls horizontally with at least one repo chip and
a working + button.

### P25.f — Repository picker bottom sheet

New file: `iOS/Sources/UI/Session/RepoPickerSheet.swift`.

Structure (reuses `SmoothieBottomSheet`):

1. Title "Choose repository".
2. Search field at top (`magnifyingglass` + 16pt input, `surface2`
   bg, `cornerMd`). Filters rows by `owner/repo` substring.
3. Scroll list of `SheetRow`-style rows. Each row:
   - Leading: GitHub icon tile (24-pt square, `surface2` bg).
   - Title: `owner/repo` (15pt semibold).
   - Subtitle: branch + last commit summary if available (13pt
     secondary).
   - Trailing: checkmark in `accent` if currently selected.
4. Tap selects + dismisses.
5. Empty state: dashed-stroke "No repositories yet — pair a host or
   clone a repo from the macOS app." with a learn-more chevron.

Backend contract: surfaces from the existing pairing store. No new
network calls; if no repos are reported, the empty state covers it.

Checkpoint: tapping the + chip opens the sheet, search filters
correctly, selecting a repo updates the chips row.

### P25.g — Composer polish (the "Code anything…" bar)

`MessageInput.swift` already has the right primitives. Tighten:

- Placeholder string: "Code anything…" (existing default is "Code").
- Mode chip glyph: `</>` icon + "Code" label, slightly larger
  (matches reference). Use `Image(systemName: "chevron.left.forwardslash.chevron.right")`.
- Attach button: switch to `paperclip` (current code already uses
  this; verify color is `textSecondary`).
- Mic button: unchanged.
- Send button: keep the 36-pt coral circle. Confirm `arrow.up` is
  the active glyph, not `arrow.up.circle.fill`.
- Remove the inline `+` button from the actions row — its purpose
  is taken over by the repo chips row's + button. Audit callers.

Checkpoint: side-by-side with screenshot 1, composer matches within
glyph stroke weight.

### P25.h — Consolidation and a11y sweep

- Audit duplicate model picker entry points (attach menu row vs.
  centered dropdown). Pick one canonical path; deprecate the other.
- Run Dynamic Type up to XXL on all four refreshed surfaces.
  `VStack`s must keep readable line-wrapping; chips must not
  collapse.
- VoiceOver labels: `EnvPill` needs `accessibilityLabel("Environment:
  Default")`; `RepoChip` needs `accessibilityLabel("Repository:
  \(owner)/\(repo)")`.
- Color contrast: spot-check chip-label vs. `chipBg` and accent
  send vs. `bgPrimary`. Target WCAG AA where reasonable for an icon
  size.

Checkpoint: TestFlight build runs cleanly with VoiceOver enabled;
manual sweep doc updated in this file (Risks section below).

## Risks / open questions

- **Repo list source.** The daemon currently doesn't expose a
  multi-repo enumeration over the pairing API. P25.e may have to
  ship with a single-repo collapse fallback. Confirm with the
  pairing/host contract before P25.e starts.
- **Centered toolbar item width.** SwiftUI's `.principal` toolbar
  item clips on narrow devices when the title is long. Truncate
  model name to 14 chars with a tail ellipsis.
- **Env pill semantics.** "Default" maps to what exactly? Defer
  definition; render visual only until product clarifies.
- **`Menu` styling limits.** SwiftUI `Menu` styling has known gaps
  (cannot fully control corner radius pre-iOS 17 in some configs).
  iOS target is 26.0 locked per CLAUDE.md, so we're fine, but flag
  if Apple removes `MenuStyle` extensibility.
- **Suggestion catalog.** Hard-coding 3 strings is fine for MVP;
  rebuilding to a per-repo / per-mode source is its own phase.

## Phase order rationale

Tokens first (P25.a) so later phases never reach for a literal.
Header pieces (P25.b, P25.c) next because they're independent of
the composer. Then composer surface (P25.d → P25.g) in a sequence
that introduces no broken intermediate states. Sweep last (P25.h).

Each phase ships in a single commit using the project's
`<phase>: <summary>` style.

## P26 — Gin (macOS) follow-up (stub only)

After iOS lands, Gin gets the matching treatment but adapted for
the notch-bar surface:

- Token parity (`DesignTokens` is iOS-only today; Gin uses its own
  Swift assets — investigate whether tokens can be split into a
  cross-target Swift Package consumed by both).
- Centered model dropdown in the expanded notch panel.
- Suggestion chips in the expanded view's empty state.
- Repo chips row in the expanded session view; picker becomes a
  popover instead of a bottom sheet (macOS idiom).
- Env pill: probably collapsed into the notch's status row rather
  than a separate capsule.

Detailed P26 phasing deferred until P25 lands and we know which
patterns translated cleanly.

## Next action when execution resumes

Start P25.a — extend `DesignTokens.swift` with the new surface,
chip, env, and menu tokens. No visual diff expected.
