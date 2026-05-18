import Foundation
import Darwin

/// Spawns a child process attached to a pseudo-terminal (PTY).
///
/// Uses `posix_openpt` / `posix_spawnp` rather than the unsafe `fork()` so that
/// only async-signal-safe code runs in the child. The master fd is set non-blocking
/// and surfaced as an `AsyncStream<Data>` for streaming reads. Process exit is
/// detected via `DispatchSourceProcess`.
final class PTYProcess: @unchecked Sendable {
    private(set) var pid: pid_t = 0
    private var masterFd: Int32 = -1
    private var exitSource: DispatchSourceProcess?
    private let exitContinuation: AsyncStream<Int32>.Continuation
    let exitStream: AsyncStream<Int32>
    private var terminated = false
    private let lock = NSLock()

    init(executable: String, args: [String], cwd: String, env: [String: String]) throws {
        var stream: AsyncStream<Int32>.Continuation!
        self.exitStream = AsyncStream<Int32> { cont in stream = cont }
        self.exitContinuation = stream

        try spawn(executable: executable, args: args, cwd: cwd, env: env)
    }

    deinit {
        if !terminated { terminate() }
        if masterFd >= 0 { close(masterFd) }
    }

    private func spawn(executable: String, args: [String], cwd: String, env: [String: String]) throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw PTYError.openMaster(errno) }
        var ok = false
        defer { if !ok, master >= 0 { close(master) } }

        if grantpt(master)  != 0 { throw PTYError.grantpt(errno) }
        if unlockpt(master) != 0 { throw PTYError.unlockpt(errno) }

        var nameBuf = [CChar](repeating: 0, count: 128)
        let nameRes = nameBuf.withUnsafeMutableBufferPointer { buf -> Int32 in
            return ptsname_r(master, buf.baseAddress, buf.count)
        }
        if nameRes != 0 { throw PTYError.ptsname(errno) }

        let slave = nameBuf.withUnsafeBufferPointer { open($0.baseAddress!, O_RDWR | O_NOCTTY) }
        guard slave >= 0 else { throw PTYError.openSlave(errno) }
        defer { close(slave) }

        var ws = winsize(ws_row: 40, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, UInt(TIOCSWINSZ), &ws)

        let flags = fcntl(master, F_GETFL, 0)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw PTYError.spawn(errno) }
        defer { posix_spawn_file_actions_destroy(&actions) }

        posix_spawn_file_actions_addclose(&actions, master)
        posix_spawn_file_actions_adddup2(&actions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, slave)
        _ = posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&attrs) == 0 else { throw PTYError.spawn(errno) }
        defer { posix_spawnattr_destroy(&attrs) }

        var spawnFlags: Int16 = 0
        spawnFlags |= Int16(POSIX_SPAWN_SETPGROUP)
        posix_spawnattr_setflags(&attrs, spawnFlags)
        posix_spawnattr_setpgroup(&attrs, 0)

        // argv: [executable, args..., NULL]
        let argvStrings = [executable] + args
        let cArgv: [UnsafeMutablePointer<CChar>?] = argvStrings.map { strdup($0) } + [nil]
        defer { cArgv.forEach { if let p = $0 { free(p) } } }

        // envp: [KEY=VALUE..., NULL]
        let envStrings = env.map { "\($0.key)=\($0.value)" }
        let cEnvp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil]
        defer { cEnvp.forEach { if let p = $0 { free(p) } } }

        var pid: pid_t = 0
        let result = cArgv.withUnsafeBufferPointer { argvBuf in
            cEnvp.withUnsafeBufferPointer { envpBuf in
                posix_spawnp(
                    &pid,
                    executable,
                    &actions,
                    &attrs,
                    UnsafeMutablePointer(mutating: argvBuf.baseAddress),
                    UnsafeMutablePointer(mutating: envpBuf.baseAddress)
                )
            }
        }
        guard result == 0 else { throw PTYError.spawn(result) }

        self.masterFd = master
        self.pid = pid
        ok = true

        // Exit monitor
        let src = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            self.exitContinuation.yield(status)
            self.exitContinuation.finish()
        }
        src.resume()
        self.exitSource = src
    }

    /// Read chunks from the master fd. The stream finishes on EOF/EIO.
    func read() -> AsyncStream<Data> {
        let fd = self.masterFd
        return AsyncStream<Data> { continuation in
            let task = Task.detached { [weak self] in
                var buffer = [UInt8](repeating: 0, count: 4096)
                while !Task.isCancelled {
                    let n = buffer.withUnsafeMutableBufferPointer { buf -> ssize_t in
                        return Darwin.read(fd, buf.baseAddress, buf.count)
                    }
                    if n > 0 {
                        continuation.yield(Data(bytes: buffer, count: n))
                    } else if n == 0 {
                        break
                    } else {
                        let err = errno
                        if err == EAGAIN || err == EWOULDBLOCK {
                            try? await Task.sleep(nanoseconds: 25_000_000)
                            continue
                        }
                        if err == EINTR { continue }
                        // EIO when child closes its end → done
                        break
                    }
                    // Stop if we know we're terminated
                    if self?.terminated == true { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Write to the master fd. Retries on `EAGAIN`.
    func write(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard !terminated, masterFd >= 0 else { throw PTYError.alreadyTerminated }

        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            var remaining = bytes.count
            var offset = 0
            while remaining > 0 {
                let n = Darwin.write(masterFd, base.advanced(by: offset), remaining)
                if n < 0 {
                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK {
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    if err == EINTR { continue }
                    throw PTYError.write(err)
                }
                offset += n
                remaining -= n
            }
        }
    }

    func terminate() {
        lock.lock()
        let wasTerminated = terminated
        terminated = true
        let fd = masterFd
        let p = pid
        lock.unlock()

        guard !wasTerminated, p > 0 else { return }
        kill(p, SIGTERM)
        // Best-effort SIGKILL after grace period
        let killPid = p
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            kill(killPid, SIGKILL)
        }
        if fd >= 0 { _ = close(fd) }
        // exitSource event handler will fire and finish exitStream
    }
}
