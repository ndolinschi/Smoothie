import SwiftUI

/// Shared building blocks for the NavigationStack-based picker sheets
/// (branch / model / MCP / repo / past-chats / mention). Each sheet
/// previously hand-rolled its own search field, section header, and
/// error/retry state — ~40-60 lines of near-identical chrome per file.
/// These three small views centralise that so the picker family stays
/// visually consistent and a tweak lands in one place. Logic (loading,
/// filtering, the rows themselves) stays in each sheet.

/// Standard rounded search field used at the top of every picker sheet:
/// magnifying glass + a bound query field + an optional clear button.
struct SheetSearchField: View {
    let placeholder: String
    @Binding var query: String
    /// When true a trailing clear (x) button appears once `query` is
    /// non-empty. Sheets that filter live want this; one-shot fields
    /// can leave it off.
    var showsClear: Bool = false

    var body: some View {
        HStack(spacing: SmoothieMetrics.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SmoothieColor.textTertiary)
            TextField(placeholder, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
            if showsClear, !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
                .buttonStyle(.smoothiePress)
            }
        }
        .padding(.horizontal, SmoothieMetrics.space14)
        .padding(.vertical, 11)
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
    }
}

/// Uppercase section label + content, the grouping used inside every
/// picker sheet ("MODELS", "BRANCHES", "AVAILABLE", …).
struct SheetSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.leading, SmoothieMetrics.space6)
            content()
        }
    }
}

/// Centred error + retry block for a failed load. `title` is the
/// human framing ("Couldn't list branches"), `message` the detail,
/// `onRetry` re-runs the sheet's loader.
struct SheetErrorState: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: SmoothieMetrics.space8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.statusErr)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .tint(SmoothieColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SmoothieMetrics.space24)
    }
}
