import Foundation

/// Discovers which CLI binaries are installed on the host and which of those
/// have adapter implementations in this build. Cached at server start.
actor AdapterRegistry {
    private(set) var info: [AdapterInfo] = []

    static let supportedCLIs: Set<CLIType> = [.opencode, .claude]

    static let executableName: [CLIType: String] = [
        .opencode: "opencode",
        .claude: "claude",
        .gemini: "gemini",
        .codex: "codex"
    ]

    func discoverAll() async {
        var collected: [AdapterInfo] = []
        for cli in CLIType.allCases {
            guard let name = Self.executableName[cli] else { continue }
            let path = await Self.which(name)
            let installed = path != nil
            let version = installed ? await Self.versionOf(path: path!) : nil
            collected.append(AdapterInfo(
                cli: cli,
                installed: installed,
                version: version,
                supported: Self.supportedCLIs.contains(cli)
            ))
        }
        info = collected
    }

    func adapter(for cli: CLIType) -> AdapterInfo? {
        info.first { $0.cli == cli }
    }

    static func make(cli: CLIType, config: AdapterStartConfig) async throws -> any AgentAdapter {
        switch cli {
        case .opencode:
            return try await OpenCodeAdapter.make(config: config)
        case .claude:
            return try await ClaudeAdapter.make(config: config)
        case .gemini, .codex:
            throw AdapterError.notImplemented(cli)
        }
    }

    private static func which(_ name: String) async -> String? {
        await runCapturing(path: "/usr/bin/which", args: [name])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func versionOf(path: String) async -> String? {
        let raw = await runCapturing(path: path, args: ["--version"], timeout: 3)
        return raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init)
    }

    private static func runCapturing(path: String, args: [String], timeout: TimeInterval = 3) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = args
                let out = Pipe()
                let err = Pipe()
                proc.standardOutput = out
                proc.standardError = err
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil); return
                }
                let deadline = DispatchTime.now() + timeout
                while proc.isRunning, DispatchTime.now() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning { proc.terminate() }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
