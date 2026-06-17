import SwiftUI

/// Elevated card rendering a single tool invocation: header (icon + mono
/// tool name + status pill + optional ×N stack badge + chevron) over an
/// optional body (key/value rows from `metadata.input`) over an optional
/// result block (mono text, 4-line clamp, tap to expand).
///
/// Replaces the prior pill-shaped `toolRow` chip + free-standing
/// `toolResult` blob in `EventRow`. The grouping into one card is owned
/// by `SessionLiveStore.groupedEvents`, which pairs each `.toolUse` with
/// its immediately-following `.toolResult` so this view stays pure.
struct ToolCallCard: View {
    enum Status { case running, completed }

    let icon: String
    let name: String
    let status: Status
    let inputFields: [(String, String)]
    let result: String?
    var stackCount: Int = 1
    var tint: Color = SmoothieColor.textPrimary.opacity(0.85)
    /// Optional small chip rendered next to the tool name in the
    /// header. Used by Claude's `Task` tool to surface the
    /// `subagent_type` (e.g. `general-purpose`, `Explore`, `Plan`)
    /// so the user can tell at a glance which subagent the parent
    /// dispatched without expanding the card.
    var subtitleBadge: String? = nil
    /// When true, the card draws a coral-tinted stroke instead of the
    /// neutral soft stroke. Used for subagent invocations so they
    /// visually pop out of the regular tool-call cadence.
    var emphasised: Bool = false
    /// P29 §5 — the CLI that produced this tool call. Drives the
    /// 2pt top-line brand accent shown while the call is `.running`
    /// or `emphasised`. Optional so previews / tests can omit it;
    /// nil falls back to `SmoothieColor.accent`.
    var cli: CLIWire? = nil

    /// Externally-owned expand state — required so the card's expanded /
    /// collapsed status survives `LazyVStack` view recycling when the user
    /// scrolls. Pre-binding versions used `@State` inside the card, which
    /// meant scrolling away and back collapsed every chevron. Callers
    /// inside the agent stream wire these to per-event-id sets on
    /// `SessionLiveStore`; previews can pass `.constant(_:)`.
    @Binding var expanded: Bool
    @Binding var resultExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                if !inputFields.isEmpty {
                    Rectangle()
                        .fill(SmoothieColor.strokeSoft)
                        .frame(height: 0.5)
                    inputsBlock
                }
                if let result, !result.isEmpty {
                    Rectangle()
                        .fill(SmoothieColor.strokeSoft)
                        .frame(height: 0.5)
                    resultBlock(result)
                }
            }
        }
        .background(SmoothieColor.bgCard)
        // P29 §5 — 2pt brand-color stripe pinned to the card's top
        // edge while the tool call is `.running` or `emphasised`.
        // Placed BEFORE the .clipShape so the rounded corners trim
        // the stripe to match the card's chrome.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(topAccentColor)
                .frame(height: 2)
                .opacity(showTopAccent ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showTopAccent)
        }
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous)
                .strokeBorder(
                    emphasised ? SmoothieColor.accent.opacity(0.45) : SmoothieColor.strokeSoft,
                    lineWidth: emphasised ? 1 : 0.5
                )
        )
        .smoothieShadow()
    }

    /// P29 §5 — show the brand stripe while a tool is actively
    /// running OR when the card is otherwise emphasised (subagent
    /// Task invocations). Completed non-emphasised cards keep their
    /// neutral chrome.
    private var showTopAccent: Bool {
        status == .running || emphasised
    }

    /// Resolved brand color for the top stripe. Falls back to the
    /// neutral accent when the call site didn't thread a CLI
    /// through (e.g. previews).
    private var topAccentColor: Color {
        if let cli {
            return SmoothieColor.brand(for: cli)
        }
        return SmoothieColor.accent
    }

    private var canExpand: Bool {
        !inputFields.isEmpty || (result?.isEmpty == false)
    }

    private var header: some View {
        Button {
            guard canExpand else { return }
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitleBadge {
                    Text(subtitleBadge)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SmoothieColor.accent.opacity(0.14), in: .capsule)
                        .lineLimit(1)
                }
                if stackCount > 1 {
                    Text("×\(stackCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(SmoothieColor.bgChip, in: .capsule)
                }
                Spacer(minLength: 8)
                statusPill
                if canExpand {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
            }
            .padding(.horizontal, SmoothieMetrics.toolCardPaddingH)
            .padding(.vertical, SmoothieMetrics.toolCardPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canExpand)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .running:   return ("running", SmoothieColor.statusThinking)
            case .completed: return ("done",    SmoothieColor.statusDone)
            }
        }()
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: .capsule)
    }

    private var inputsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(inputFields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.0.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(SmoothieColor.textTertiary)
                    Text(field.1)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, SmoothieMetrics.toolCardPaddingH)
        .padding(.vertical, 10)
    }

    private func resultBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RESULT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(SmoothieColor.textTertiary)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SmoothieColor.textSecondary)
                .lineLimit(resultExpanded ? nil : 4)
                .textSelection(.enabled)
                .onTapGesture { resultExpanded.toggle() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SmoothieMetrics.toolCardPaddingH)
        .padding(.vertical, 10)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ToolCallCard(
            icon: "wrench.adjustable",
            name: "Read",
            status: .completed,
            inputFields: [("file_path", "/Users/ndolinschi/Documents/Apps/Smoothie/iOS/Sources/UI/Session/EventRow.swift")],
            result: "1→import SwiftUI\n2→\n3→struct EventRow: View {\n4→    let event: SmoothieEventWire\n5→    @State private var expanded = false\n6→...",
            expanded: .constant(false),
            resultExpanded: .constant(false)
        )
        ToolCallCard(
            icon: "doc.text.fill",
            name: "Edit",
            status: .running,
            inputFields: [
                ("file_path", "iOS/Sources/UI/Components/DesignTokens.swift"),
                ("old_string", "static let accent = Color(hex: 0xED7C5C)"),
            ],
            result: nil,
            expanded: .constant(true),
            resultExpanded: .constant(false)
        )
        ToolCallCard(
            icon: "wrench.adjustable",
            name: "Read",
            status: .completed,
            inputFields: [],
            result: nil,
            stackCount: 5,
            expanded: .constant(false),
            resultExpanded: .constant(false)
        )
    }
    .padding()
    .background(SmoothieColor.bgPrimary)
    .preferredColorScheme(.dark)
}
#endif
