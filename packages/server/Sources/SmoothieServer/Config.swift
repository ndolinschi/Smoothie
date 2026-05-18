import Foundation

struct Config: Sendable {
    let port: Int
    let bindAddress: String
    let bindAddressIsTailscale: Bool
    let allowedRoots: [String]
    let version: String
    let promptsDir: String?

    static let defaultPort = 7749
    static let defaultVersion = "0.1.0"

    static func resolve() -> Config {
        let port = Int(ProcessInfo.processInfo.environment["SMOOTHIE_PORT"] ?? "") ?? defaultPort

        let (address, isTailscale) = resolveBindAddress()

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let roots = [
            "\(home)/Developer",
            "\(home)/Projects",
            "\(home)/Documents",
            home
        ]
            .map { ($0 as NSString).standardizingPath }
            .filter { FileManager.default.fileExists(atPath: $0) }

        let promptsDir = locatePromptsDir()

        return Config(
            port: port,
            bindAddress: address,
            bindAddressIsTailscale: isTailscale,
            allowedRoots: roots,
            version: defaultVersion,
            promptsDir: promptsDir
        )
    }

    func isPathAllowed(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let resolved = (normalized as NSString).resolvingSymlinksInPath
        if resolved.contains("/..") { return false }
        return allowedRoots.contains { root in
            resolved == root || resolved.hasPrefix(root + "/")
        }
    }

    private static func resolveBindAddress() -> (String, Bool) {
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/bin/tailscale"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if let ip = runCommand(path: path, args: ["ip", "-4"]) {
                let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.contains(".") {
                    return (trimmed, true)
                }
            }
        }
        FileHandle.standardError.write(Data(
            "[smoothie] Tailscale not found — falling back to 127.0.0.1. Install Tailscale on Mac and iPhone for on-device access.\n".utf8
        ))
        return ("127.0.0.1", false)
    }

    private static func locatePromptsDir() -> String? {
        let fm = FileManager.default
        var path = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = path.appendingPathComponent("prompts")
            if fm.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            path.deleteLastPathComponent()
        }
        return nil
    }

    private static func runCommand(path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
