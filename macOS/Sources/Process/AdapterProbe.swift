import Foundation
import Shared

/// One-shot host-side discovery: `which <bin>` + `<bin> --version` for each
/// known CLI, pushes the resulting `AdapterInfo` into Kotlin's
/// `AdapterRegistry`. Keeps adapter feature flags (from the parser's static
/// defaults) intact; only `installed` and `version` are updated.
@MainActor
enum AdapterProbe {
    static func probeAll(into registry: AdapterRegistry) async {
        for cli in CLIType.entries {
            let binary = cli.executableName
            let path = which(binary)
            let installed = path != nil
            var version: String? = nil
            if let p = path {
                version = await captureVersion(executable: p, args: ["--version"])
            }
            registry.setAdapterInfo(cli: cli, installed: installed, version: version)
        }
    }

    private static func which(_ binary: String) -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/\(binary)",
            "/opt/homebrew/bin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/usr/bin/\(binary)",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    private static func captureVersion(executable: String, args: [String]) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = args
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = Pipe()
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil); return
                }
                let deadline = DispatchTime.now() + 3
                while proc.isRunning, DispatchTime.now() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning { proc.terminate() }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                let firstLine = raw.split(whereSeparator: { $0.isNewline }).first.map(String.init)
                continuation.resume(returning: firstLine?.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}
