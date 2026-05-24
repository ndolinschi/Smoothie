import Foundation

/// P29 §8 — Create-PR pipeline runner.
///
/// Spawns a sequence of short-lived `/usr/bin/env git` / `/usr/bin/env
/// gh` subprocesses scoped to a session's project directory:
///   1. (Optional) `git checkout -b <branch>` — only when the iOS
///      client passed `useCurrentBranch == false`.
///   2. `git add -A` — stage every dirty path so the commit includes
///      everything the agent touched.
///   3. `git commit -m <title> -m <body>` — skipped (with a non-error
///      log) when there's nothing staged, so calling Create-PR twice
///      in a row doesn't fail on the second invocation.
///   4. `git push -u origin <branch>` — establishes the upstream so
///      `gh pr create` can find the remote.
///   5. `gh pr create --title <title> --body <body>` — captures stdout
///      for the PR URL.
///
/// On any non-zero exit the function throws `PRCreationError` with a
/// `stage` hint + the underlying stderr so the daemon can surface a
/// specific HTTP 409 body to iOS. Anything spawn-related (missing
/// binary, IO failure) throws as `.stage("launch", message:)` with a
/// 500 code.
enum GitPRCreator {
    enum Stage: String {
        case branch        // git checkout -b
        case add           // git add -A
        case commit        // git commit -m
        case push          // git push -u origin
        case pr            // gh pr create
        case launch        // failed to spawn the subprocess
    }

    struct PRCreationError: Error, LocalizedError {
        let stage: Stage
        let message: String
        var errorDescription: String? {
            "\(stage.rawValue): \(message)"
        }
    }

    /// Returns the PR URL emitted by `gh pr create`.
    static func createPR(
        cwd: String,
        title: String,
        body: String,
        branch: String,
        useCurrentBranch: Bool
    ) throws -> String {
        // Reject obvious flag-injection attempts. The iOS picker
        // doesn't allow leading dashes in either field, but defence
        // in depth.
        guard !title.hasPrefix("-"), !branch.hasPrefix("-") else {
            throw PRCreationError(stage: .branch, message: "title/branch must not start with a dash")
        }

        // 1. Optional new branch
        if !useCurrentBranch && !branch.isEmpty {
            try runOrThrow(
                tool: "git",
                args: ["checkout", "-b", branch],
                cwd: cwd,
                stage: .branch
            )
        }

        // 2. Stage everything
        try runOrThrow(tool: "git", args: ["add", "-A"], cwd: cwd, stage: .add)

        // 3. Commit. Skip silently when there's nothing to commit
        //    (git emits status 1 + "nothing to commit, working tree
        //    clean" on the second invocation).
        let commitResult = run(
            tool: "git",
            args: ["commit", "-m", title, "-m", body],
            cwd: cwd
        )
        if commitResult.exit != 0 {
            let combined = (commitResult.stderr + commitResult.stdout).lowercased()
            let isEmpty = combined.contains("nothing to commit") || combined.contains("no changes added")
            if !isEmpty {
                throw PRCreationError(
                    stage: .commit,
                    message: trim(commitResult.stderr.isEmpty ? commitResult.stdout : commitResult.stderr)
                )
            }
        }

        // 4. Push the branch upstream
        let pushArgs: [String]
        if useCurrentBranch {
            pushArgs = ["push", "-u", "origin", "HEAD"]
        } else {
            pushArgs = ["push", "-u", "origin", branch]
        }
        try runOrThrow(tool: "git", args: pushArgs, cwd: cwd, stage: .push)

        // 5. gh pr create
        let prResult = run(
            tool: "gh",
            args: ["pr", "create", "--title", title, "--body", body],
            cwd: cwd
        )
        if prResult.exit != 0 {
            throw PRCreationError(
                stage: .pr,
                message: trim(prResult.stderr.isEmpty ? prResult.stdout : prResult.stderr)
            )
        }
        // gh prints the URL as the last non-empty line. Trim other
        // chatter (e.g. "Warning: 1 uncommitted change") so the iOS
        // client gets a clean URL.
        let url = prResult.stdout
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .last(where: { $0.hasPrefix("https://") }) ?? prResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            throw PRCreationError(stage: .pr, message: "gh returned empty output")
        }
        return url
    }

    // MARK: - Precheck (gh installed + auth)

    struct ReadyResult {
        let ready: Bool
        let missing: [String]
    }

    /// Runs `gh --version` then `gh auth status`. Reports which step
    /// failed so iOS can surface a useful hint to the user.
    static func ghReady() -> ReadyResult {
        let version = run(tool: "gh", args: ["--version"], cwd: nil)
        if version.exit != 0 {
            return ReadyResult(ready: false, missing: ["gh"])
        }
        let auth = run(tool: "gh", args: ["auth", "status"], cwd: nil)
        if auth.exit != 0 {
            return ReadyResult(ready: false, missing: ["gh-auth"])
        }
        return ReadyResult(ready: true, missing: [])
    }

    // MARK: - Internals

    private struct RunResult {
        let exit: Int32
        let stdout: String
        let stderr: String
    }

    private static func runOrThrow(
        tool: String,
        args: [String],
        cwd: String,
        stage: Stage
    ) throws {
        let result = run(tool: tool, args: args, cwd: cwd)
        if result.exit != 0 {
            throw PRCreationError(
                stage: stage,
                message: trim(result.stderr.isEmpty ? result.stdout : result.stderr)
            )
        }
    }

    private static func run(tool: String, args: [String], cwd: String?) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return RunResult(
                exit: -1,
                stdout: "",
                stderr: "failed to launch \(tool): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(exit: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func trim(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "git/gh produced no diagnostic" : t
    }
}
