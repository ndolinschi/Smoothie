import Foundation

/// Swift-native Decodable mirrors of the JSON the macOS HTTP server emits.
/// Kept separate from `Shared` framework types because Kotlin's K/N exports
/// aren't Codable from Swift's perspective.

struct MeWire: Codable, Sendable, Equatable {
    let username: String
    let fullName: String
    let hostname: String

    /// Short greeting handle — uses the first word of fullName when
    /// available (so "Nichita Dolinschi" → "Nichita"), falling back to
    /// the POSIX username (`ndolinschi`) if the full name is empty.
    var greetingName: String {
        let first = fullName.split(separator: " ").first.map(String.init)
        return first?.isEmpty == false ? first! : username
    }
}

enum CLIWire: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case gemini
    case openCode = "open_code"
    case antigravity
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .gemini:      return "Gemini"
        case .openCode:    return "OpenCode"
        case .antigravity: return "Antigravity"
        case .codex:       return "Codex"
        case .cursor:      return "Cursor"
        }
    }

    /// Server expects the same lowercased token the Kotlin enum's `.name`
    /// produces (`claude_code`, `gemini`, `codex`, `open_code`).
    var wireValue: String { rawValue }

    /// Pretty model name shown in the composer — the wire `id` (sent as
    /// `--model` to the CLI) is usually an alias like `sonnet` that's
    /// useless to the user. Maps known aliases to family+version
    /// labels — the brand chip is conveyed by the provider context
    /// (toolbar shows the CLI's display name elsewhere), so the model
    /// label itself only needs to disambiguate within the family.
    func friendlyModelName(_ id: String) -> String {
        switch self {
        case .claudeCode:
            switch id.lowercased() {
            case "sonnet":  return "Sonnet 4.6"
            case "haiku":   return "Haiku 4.5"
            case "opus":    return "Opus 4.7"
            default:        return id
            }
        case .gemini:
            switch id.lowercased() {
            case "auto-gemini-3":         return "Gemini 3 · auto"
            case "gemini-3-flash-preview": return "Gemini 3 Flash"
            case "gemini-3.1-flash-lite":  return "Gemini 3.1 Flash Lite"
            default:                       return id
            }
        case .openCode:
            return id
        case .antigravity:
            // agy v1.0.0 has no `--model` flag; the active model is picked by
            // the user's desktop Antigravity profile. We display whatever the
            // server returned, falling back to a friendly placeholder.
            return id.isEmpty ? "Antigravity" : id
        case .codex:
            switch id.lowercased() {
            case "gpt-5-codex":   return "GPT-5 Codex"
            case "gpt-4.1-codex": return "GPT-4.1 Codex"
            default:              return id
            }
        case .cursor:
            switch id.lowercased() {
            case "auto":          return "Auto"
            case "sonnet-4.5":    return "Sonnet 4.5"
            case "gpt-5":         return "GPT-5"
            case "gpt-5-codex":   return "GPT-5 Codex"
            default:              return id
            }
        }
    }

    /// One-line descriptor shown beneath the model name in the compact
    /// dropdown (P25.b). Returns nil for providers that don't have a
    /// per-model marketing line.
    func modelDescriptor(_ id: String) -> String? {
        switch self {
        case .claudeCode:
            switch id.lowercased() {
            case "opus":   return "Most capable for ambitious work"
            case "sonnet": return "Responsive everyday work"
            case "haiku":  return "Fastest, most efficient"
            default:       return nil
            }
        case .gemini:
            switch id.lowercased() {
            case "auto-gemini-3":          return "Auto-routed across Gemini 3"
            case "gemini-3-flash-preview": return "Fast preview model"
            case "gemini-3.1-flash-lite":  return "Lightest, fastest"
            default:                       return nil
            }
        case .codex:
            switch id.lowercased() {
            case "gpt-5-codex":   return "OpenAI's coding-tuned flagship"
            case "gpt-4.1-codex": return "Older, cheaper Codex variant"
            default:              return nil
            }
        case .cursor:
            switch id.lowercased() {
            case "auto":          return "Cursor picks the right model per turn"
            case "sonnet-4.5":    return "Anthropic Sonnet 4.5 via Cursor"
            case "gpt-5":         return "OpenAI flagship via Cursor"
            case "gpt-5-codex":   return "OpenAI coding variant via Cursor"
            default:              return nil
            }
        case .openCode, .antigravity:
            return nil
        }
    }
}

enum SessionStateWire: String, Codable, Sendable {
    case starting, thinking, waiting, done, error
    case limitReached = "limit_reached"
    /// Fallback for state strings introduced by a newer daemon that this
    /// iOS build doesn't recognise yet. The default `String`-backed
    /// `Codable` synthesis would throw on decode and crash the SSE
    /// pipeline; a tolerant decoder lets the app keep ticking and just
    /// render the session in an unknown-but-non-fatal pose.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionStateWire(rawValue: raw) ?? .unknown
    }

    /// Treated as completed in the HomeView filter — the agent isn't going to
    /// produce more events without a manual restart.
    var isCompleted: Bool {
        switch self {
        case .done, .error, .limitReached: return true
        case .starting, .thinking, .waiting, .unknown: return false
        }
    }
}

enum EventTypeWire: String, Codable, Sendable {
    case message, thinking
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case fileEdit = "file_edit"
    case waiting, done, error
    case limitReached = "limit_reached"
    /// Phase 2 of the Cursor redesign — daemon emits these to update the
    /// token budget bar in the iOS status footer. The payload (JSON
    /// ContextSnapshot) rides in `event.metadata`; the visible event
    /// stream filter in `AgentStream` treats these as invisible so the
    /// agent transcript stays clean.
    case contextUpdate = "context_update"
    /// Same forward-compat fallback as `SessionStateWire.unknown` — a
    /// new event type from a newer daemon decodes as `.unknown` instead
    /// of crashing the whole event stream parser.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventTypeWire(rawValue: raw) ?? .unknown
    }
}

/// Reply from GET /sessions/:id/branches. `current` is nil for empty
/// or non-git working trees; `branches` is empty in that case too.
struct BranchListingWire: Codable, Sendable {
    let current: String?
    let branches: [String]
}

/// Single MCP server descriptor in `MCPListingWire.available`. The
/// daemon discovers these from per-CLI config files (Claude:
/// `~/.claude.json`; Gemini: `~/.gemini/settings.json`; opencode:
/// `~/.config/opencode/config.json`). Antigravity returns nothing.
struct MCPServerWire: Codable, Sendable, Identifiable, Hashable {
    /// Stable id used by the picker's enable/disable toggle. Matches the
    /// server's key in the originating CLI config.
    let id: String
    let name: String
    let description: String?
    let command: String?
    /// File path the daemon read this entry from — surfaced in the
    /// picker's subtitle as a debugging aid when discovery looks wrong.
    let source: String
}

/// Reply from GET/POST /sessions/:id/mcp-servers. `available` is the
/// full discovery set; `enabled` is the per-session override the
/// daemon will pass to the CLI on the next host spawn.
struct MCPListingWire: Codable, Sendable {
    let available: [MCPServerWire]
    let enabled: [String]
}

/// Per-category breakdown of how much of the model's context window is
/// occupied. Phase 2 of the Cursor redesign exposes this as the
/// segmented bar + collapsible list in `ContextBudgetPanel`. Daemon
/// emits this either via `GET /sessions/:id/context` (pull, used on
/// mount) or via SSE `context_update` events (push, debounced ~500ms).
struct ContextSnapshotWire: Codable, Sendable, Hashable {
    /// Sum of every category. Reported separately so the daemon can
    /// account for tokenizer overhead the per-category counts don't see.
    let total: Int
    /// Model's hard context window cap. `0` means "unknown" — the iOS
    /// footer hides the percent ring in that case rather than dividing
    /// by zero.
    let max: Int
    /// Ordered breakdown — daemon owns the canonical order so the
    /// segmented bar always reads the same way across iOS / Mac.
    let breakdown: [ContextCategoryWire]
}

struct ContextCategoryWire: Codable, Sendable, Hashable, Identifiable {
    /// Stable id matching the category color map in
    /// `ContextBudgetBar` (system_prompt / tool_definitions / rules /
    /// skills / mcp / subagent_definitions / conversation).
    let id: String
    /// Human label rendered in the list — daemon picks the wording so we
    /// don't drift between platforms.
    let label: String
    let tokens: Int
}

struct SmoothieEventWire: Codable, Sendable, Identifiable {
    let type: EventTypeWire
    let content: String
    let metadata: [String: AnyCodable]?
    let timestamp: Int64
    /// Client-stamped UUID — guarantees `ForEach`/`LazyVStack` row identity
    /// even when two events share the same `(timestamp, type, content)`
    /// tuple (e.g. two near-simultaneous `thinking: "starting"` events).
    /// Wire-side this field is absent; the custom CodingKeys below makes
    /// the decoder skip it and the default value stays UUID-fresh per
    /// decoded instance.
    var clientId: String = UUID().uuidString

    private enum CodingKeys: String, CodingKey {
        case type, content, metadata, timestamp
    }

    var id: String { clientId }

    /// Convenience initializer for client-synthesised events (mode-switch
    /// dividers, etc.) that aren't decoded from the wire.
    init(type: EventTypeWire, content: String, metadata: [String: AnyCodable]?, timestamp: Int64) {
        self.type = type
        self.content = content
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

enum SessionOriginWire: String, Codable, Sendable {
    case smoothie
    case terminal
}

struct SessionDescriptorWire: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let projectPath: String
    let projectName: String
    let cli: CLIWire
    let model: String?
    let reasoningEffort: String?
    let mode: String?
    let state: SessionStateWire
    let createdAt: Int64
    /// Provider-side conversation id (Claude/Gemini `session_id`, OpenCode
    /// `session.id`). Decoded from the server; nil for newly-created
    /// sessions before the first event lands, or for providers like
    /// Antigravity that don't expose one.
    let providerSessionId: String?
    /// Tags Terminal-discovered sessions (vs Smoothie-spawned). The
    /// HomeView surfaces a small Terminal badge on `.terminal` rows.
    let origin: SessionOriginWire

    /// Custom decoder so older daemons (pre-P22) that don't emit the new
    /// fields still parse — both default to nil / `.smoothie`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        projectName = try c.decode(String.self, forKey: .projectName)
        cli = try c.decode(CLIWire.self, forKey: .cli)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        state = try c.decode(SessionStateWire.self, forKey: .state)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        providerSessionId = try c.decodeIfPresent(String.self, forKey: .providerSessionId)
        origin = (try c.decodeIfPresent(SessionOriginWire.self, forKey: .origin)) ?? .smoothie
    }

    init(
        id: String, projectPath: String, projectName: String, cli: CLIWire,
        model: String?, reasoningEffort: String?, mode: String?,
        state: SessionStateWire, createdAt: Int64,
        providerSessionId: String? = nil, origin: SessionOriginWire = .smoothie
    ) {
        self.id = id
        self.projectPath = projectPath
        self.projectName = projectName
        self.cli = cli
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.mode = mode
        self.state = state
        self.createdAt = createdAt
        self.providerSessionId = providerSessionId
        self.origin = origin
    }

    /// Return a copy with `mode` swapped. Used by the soft mode-switch path
    /// (P17) so the composer chip flips instantly without a session restart.
    func withMode(_ newMode: String?) -> SessionDescriptorWire {
        SessionDescriptorWire(
            id: id, projectPath: projectPath, projectName: projectName, cli: cli,
            model: model, reasoningEffort: reasoningEffort, mode: newMode,
            state: state, createdAt: createdAt,
            providerSessionId: providerSessionId, origin: origin
        )
    }
}

struct SlashCommandWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let description: String
    var id: String { name }
}

struct ProviderFeaturesWire: Codable, Sendable, Hashable {
    let supportsModelPicker: Bool
    let supportsReasoningEffort: Bool
    let supportsModes: Bool
    let defaultModel: String?
    let availableModels: [String]
    let availableReasoningEfforts: [String]
    let availableModes: [String]
    let slashCommands: [SlashCommandWire]
}

struct AdapterInfoWire: Codable, Sendable, Identifiable {
    let cli: CLIWire
    let installed: Bool
    let version: String?
    let features: ProviderFeaturesWire?

    var id: String { cli.rawValue }
}

struct CreateSessionRequestWire: Codable, Sendable {
    let projectPath: String
    let cli: CLIWire
    let model: String?
    let reasoningEffort: String?
    let mode: String?
    /// When set, the host injects the provider's resume flag so the new
    /// subprocess picks up an existing conversation. Used by the
    /// Terminal-session → iPhone resume flow.
    let providerSessionId: String?

    init(projectPath: String, cli: CLIWire, model: String? = nil, reasoningEffort: String? = nil, mode: String? = nil, providerSessionId: String? = nil) {
        self.projectPath = projectPath
        self.cli = cli
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.mode = mode
        self.providerSessionId = providerSessionId
    }
}

struct ProjectWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let path: String
    let isGit: Bool
    var id: String { path }
}

struct BrowseEntryWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isGit: Bool
    let isAllowed: Bool
    var id: String { path }
}

struct BrowseResponseWire: Codable, Sendable {
    let current: String?
    let parent: String?
    let entries: [BrowseEntryWire]
    let roots: [String]
}

struct FileEntryWire: Codable, Sendable, Identifiable, Hashable {
    let path: String
    let fullPath: String
    let size: Int
    var id: String { fullPath }
}

struct FileContentWire: Codable, Sendable {
    let path: String
    let content: String
    let size: Int
    let truncated: Bool
}

/// Type-erased JSON value for `metadata`. Decode-only.
struct AnyCodable: Codable, Sendable, Hashable {
    enum Value: Hashable, Sendable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case object([String: AnyCodable])
    }

    let value: Value

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = .null; return }
        if let v = try? c.decode(Bool.self) { value = .bool(v); return }
        if let v = try? c.decode(Int.self) { value = .int(v); return }
        if let v = try? c.decode(Double.self) { value = .double(v); return }
        if let v = try? c.decode(String.self) { value = .string(v); return }
        if let v = try? c.decode([AnyCodable].self) { value = .array(v); return }
        if let v = try? c.decode([String: AnyCodable].self) { value = .object(v); return }
        value = .null
    }

    /// Convenience for synthesising client-side metadata (e.g. the
    /// soft-mode-switch divider flag from P24.b B5).
    init(_ value: Value) {
        self.value = value
    }

    init(_ string: String)   { self.value = .string(string) }
    init(_ int: Int)         { self.value = .int(int) }
    init(_ bool: Bool)       { self.value = .bool(bool) }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let s) = value { return s }
        return nil
    }
}

// MARK: - Widget snapshot bridges

extension CLIWire {
    var snapshotCLI: WidgetSnapshot.WireCLI {
        switch self {
        case .claudeCode:  return .claudeCode
        case .gemini:      return .gemini
        case .openCode:    return .openCode
        case .antigravity: return .antigravity
        case .codex:       return .codex
        case .cursor:      return .cursor
        }
    }
}

extension SessionStateWire {
    var snapshotState: WidgetSnapshot.WireState {
        switch self {
        case .starting:     return .starting
        case .thinking:     return .thinking
        case .waiting:      return .waiting
        case .done:         return .done
        case .error:        return .error
        case .limitReached: return .limitReached
        case .unknown:      return .starting
        }
    }
}
