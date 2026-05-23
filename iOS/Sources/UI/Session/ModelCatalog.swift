import SwiftUI

/// Client-side tier metadata for model strings the daemon exposes via
/// `ProviderFeaturesWire.availableModels`. Phase 3 of the Cursor redesign
/// (see plan) calls for tier badges (Fast / Medium / Slow) in the
/// composer's `ModelChip` + the picker rows. The daemon doesn't ship
/// this data today — when it does, this static map becomes a fallback.
enum ModelCatalog {
    enum Tier {
        case fast      // sonnet / haiku / flash — sub-second tokens
        case medium    // mid-tier reasoning, mainstream cost
        case slow      // opus / o1 / heavy reasoning — best quality, slowest

        var label: String {
            switch self {
            case .fast:   return "Fast"
            case .medium: return "Medium"
            case .slow:   return "Max"
            }
        }

        var symbol: String {
            switch self {
            case .fast:   return "bolt.fill"
            case .medium: return "brain"
            case .slow:   return "tortoise.fill"
            }
        }

        /// Subtle accent color for the tier dot — kept restrained so the
        /// chip doesn't fight the mono palette. Medium/Slow share the
        /// neutral track; Fast gets a soft green nod to "snappy".
        var dotColor: Color {
            switch self {
            case .fast:   return SmoothieColor.statusDone
            case .medium: return SmoothieColor.textSecondary
            case .slow:   return SmoothieColor.modePlan
            }
        }
    }

    /// Resolve a tier for a `(cli, model)` pair. Returns `.medium` when
    /// the model is unknown so the chip still renders without breaking.
    static func tier(cli: CLIWire, model: String?) -> Tier {
        guard let model = model?.lowercased() else { return .medium }
        switch cli {
        case .claudeCode:
            if model.contains("haiku") { return .fast }
            if model.contains("opus")  { return .slow }
            return .medium               // sonnet
        case .gemini:
            if model.contains("flash") || model.contains("lite") { return .fast }
            if model.contains("pro") { return .slow }
            return .medium               // auto / unknown
        case .openCode:
            if model.contains("haiku") || model.contains("mini") { return .fast }
            if model.contains("opus") || model.contains("o1") { return .slow }
            return .medium
        case .antigravity:
            return .medium               // single profile, no real tier
        }
    }

    /// Short friendly label suitable for the composer chip. Strips
    /// provider prefixes (`anthropic/`), drops dated suffixes, etc.
    static func displayLabel(cli: CLIWire, model: String?) -> String {
        guard let model = model, !model.isEmpty else {
            return cli.displayName
        }
        // Strip "<vendor>/" prefix that opencode uses
        var trimmed = model
        if let slash = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[trimmed.index(after: slash)...])
        }
        return trimmed
    }
}
