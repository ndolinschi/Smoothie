import Foundation
import Shared

/// Bridges the on-disk prompts/ directory into the Kotlin SafetyPromptManager.
/// On startup, looks for prompts/base/safety.md and prompts/<cli>/system.md +
/// resume.md, loads them, pushes the text into the Kotlin manager. Provides
/// the assembled system prompt the ProcessHost passes at session start.
@MainActor
final class SafetyHost {
    static let shared = SafetyHost()

    private let manager = SafetyPromptManager()
    private var loaded = false

    /// Call once at app launch. Tries the repo path first (handy in dev) and
    /// falls back to the bundled `Resources/prompts/` directory in release.
    func loadPrompts() {
        guard !loaded else { return }
        loaded = true

        let bases = candidatePromptRoots()
        guard let root = bases.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return  // no prompts dir found — manager stays empty, adapters get nil system prompt
        }

        let baseSafetyPath = (root as NSString).appendingPathComponent("base/safety.md")
        if let text = try? String(contentsOfFile: baseSafetyPath, encoding: .utf8) {
            manager.setBasePrompt(text: text)
        }

        for cli in CLIType.entries {
            let folder = (root as NSString).appendingPathComponent(folderName(for: cli))
            let systemPath = (folder as NSString).appendingPathComponent("system.md")
            if let text = try? String(contentsOfFile: systemPath, encoding: .utf8) {
                manager.setSystemPrompt(cli: cli, text: text)
            }
            let resumePath = (folder as NSString).appendingPathComponent("resume.md")
            if let text = try? String(contentsOfFile: resumePath, encoding: .utf8) {
                manager.setResumePrompt(cli: cli, text: text)
            }
        }
    }

    func assembledSystemPrompt(for cli: CLIType) -> String {
        let text = manager.assembledSystemPrompt(cli: cli)
        return text.isEmpty ? "" : text
    }

    func resumePromptTemplate(for cli: CLIType) -> String? {
        manager.resumePromptTemplate(cli: cli)
    }

    private func folderName(for cli: CLIType) -> String {
        switch cli {
        case .claudeCode:  return "claude-code"
        case .gemini:      return "gemini"
        case .openCode:    return "opencode"
        case .antigravity: return "antigravity"
        default:           return cli.name.lowercased()
        }
    }

    private func candidatePromptRoots() -> [String] {
        var roots: [String] = []
        // Bundled resources (when running an installed .app)
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("prompts").path {
            roots.append(bundled)
        }
        // Dev: walk up from the executable looking for a prompts/ next to a
        // shared/ directory. Covers Xcode-run builds.
        var url = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = url.appendingPathComponent("prompts")
            roots.append(candidate.path)
            url.deleteLastPathComponent()
        }
        return roots
    }
}
