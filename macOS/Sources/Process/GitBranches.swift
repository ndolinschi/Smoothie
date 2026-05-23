import Foundation

/// Helpers around `git branch` and `git checkout` for the workspace
/// routes. Each function spawns a short-lived `/usr/bin/env git`
/// subprocess scoped to the session's project directory. The daemon
/// rejects empty branch names upstream so caller input arrives
/// already-validated.
enum GitBranches {
    /// Run `git branch --list --format=%(refname:short)` and pair it
    /// with `git symbolic-ref --short HEAD` (or `git rev-parse --short
    /// HEAD` if the user is on a detached commit). Throws on non-zero
    /// exits with stderr surfaced as the NSError message so HTTP
    /// callers see git's own diagnostic.
    static func list(cwd: String) throws -> BranchListing {
        let branchesOut = try run(args: ["branch", "--list", "--format=%(refname:short)"], cwd: cwd)
        let branches = branchesOut
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // symbolic-ref fails on detached HEAD; fall back to a short SHA
        // with the `(detached)` suffix so the picker still has a "current"
        // value to render.
        let current: String?
        if let symbolic = try? run(args: ["symbolic-ref", "--short", "HEAD"], cwd: cwd) {
            let trimmed = symbolic.trimmingCharacters(in: .whitespacesAndNewlines)
            current = trimmed.isEmpty ? nil : trimmed
        } else if let sha = try? run(args: ["rev-parse", "--short", "HEAD"], cwd: cwd) {
            let trimmed = sha.trimmingCharacters(in: .whitespacesAndNewlines)
            current = trimmed.isEmpty ? nil : "(detached \(trimmed))"
        } else {
            current = nil
        }
        return BranchListing(current: current, branches: branches)
    }

    /// Run `git checkout <branch>`. Non-zero exit → throws NSError with
    /// stderr as the message; conflict / dirty-tree messages from git
    /// surface unchanged so the iOS picker can show them.
    static func checkout(cwd: String, branch: String) throws {
        // Defence-in-depth — reject anything that could plausibly be a
        // CLI flag injection. Branch names don't have whitespace or
        // leading dashes; if the user types one the daemon refuses.
        guard !branch.hasPrefix("-") else {
            throw NSError(
                domain: "Smoothie", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "invalid branch name"]
            )
        }
        _ = try run(args: ["checkout", branch], cwd: cwd)
    }

    /// Internal git runner. Returns stdout on exit 0; throws otherwise
    /// with stderr in the message. NSError.code is 409 for non-zero
    /// exits (treat as conflict-ish — typically uncommitted changes
    /// blocking the checkout) and 500 for spawn / I/O failures.
    private static func run(args: [String], cwd: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw NSError(
                domain: "Smoothie", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "git failed to launch: \(error.localizedDescription)"]
            )
        }
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "Smoothie", code: 409,
                userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "git failed (exit \(process.terminationStatus))" : msg]
            )
        }
        return stdout
    }
}
