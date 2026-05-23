import Foundation

/// Server-Sent Events consumer using `URLSessionDataDelegate`. Never uses
/// `URLSession.bytes(for:)` because Apple's CFNetwork buffers SSE responses
/// when read that way. Reconnects with exponential backoff 1/2/4/8/16/30 s
/// (resets to 1 on a clean open).
final class SSEClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let bearer: String
    private let onEvent: @Sendable (SmoothieEventWire) -> Void
    private let onState: @Sendable (State) -> Void

    enum State: Sendable {
        case connecting
        case connected
        case retrying(Int)            // seconds until next attempt
        case stopped
        /// Server responded with a terminal status (404 = session no
        /// longer exists; 401 = pairing token revoked; 410 = gone).
        /// Distinct from `.retrying`/`.stopped` so the UI can present
        /// an actionable banner — and so the client *stops* retrying
        /// instead of spinning on a dead resource.
        case gone(reason: String)
    }

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var lineBuffer = ""
    private var currentEvent: String?
    private var dataBuffer: [String] = []
    private var backoffStep: Int = 0
    private var stopped: Bool = false
    private let lock = NSLock()

    /// Cap on consecutive failed reconnects. After this many backoff
    /// cycles we surface `.gone` with a user-actionable message instead
    /// of silently spinning forever. The previous behaviour with no cap
    /// was the root cause of the "infinity connecting" complaint —
    /// e.g. a misbehaving Tailscale proxy returning 502 on every probe
    /// kept the banner stuck at "Reconnecting in 30s…" indefinitely.
    private static let maxRetries: Int = 6
    private var retryCount: Int = 0

    init(
        url: URL,
        bearer: String,
        onEvent: @escaping @Sendable (SmoothieEventWire) -> Void,
        onState: @escaping @Sendable (State) -> Void = { _ in }
    ) {
        self.url = url
        self.bearer = bearer
        self.onEvent = onEvent
        self.onState = onState
        super.init()
        let cfg = URLSessionConfiguration.default
        // Request timeout = 60s for the initial handshake — if the daemon
        // doesn't respond with status in a minute, the network's broken.
        // Resource timeout = 600s (10 min) as an upper bound on a single
        // SSE pipe; long enough for idle sessions, short enough that a
        // half-open TCP connection eventually drops and reconnect kicks
        // in. Both were `.infinity` previously, which is why a hung
        // proxy / NAT timeout would leave the iOS app stuck on
        // "Connecting…" forever with no way out.
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 600
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpAdditionalHeaders = ["Accept": "text/event-stream"]
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start() {
        lock.lock()
        stopped = false
        // Reset the retry counter on explicit start so a manual reconnect
        // (via SessionLiveStore.reconnect) gets a fresh attempt budget.
        retryCount = 0
        backoffStep = 0
        lock.unlock()
        onState(.connecting)
        openConnection()
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        onState(.stopped)
    }

    // MARK: - Internals

    private func openConnection() {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // 60s handshake timeout. The configuration-level resource timeout
        // governs the whole streaming pipe; this one is just for the
        // initial response headers.
        req.timeoutInterval = 60
        guard let session else { return }
        let t = session.dataTask(with: req)
        task = t
        t.resume()
    }

    private func scheduleReconnect() {
        lock.lock()
        if stopped { lock.unlock(); return }
        retryCount += 1
        let attempt = retryCount
        let nextStep = min(backoffStep + 1, 6)
        backoffStep = nextStep
        lock.unlock()

        // After N consecutive failed reconnects we stop spinning and
        // surface .gone so the user can either tap Reconnect (which
        // resets retryCount via start()) or pair a different Mac. Before
        // this cap landed, a misbehaving network kept the banner stuck
        // on "Reconnecting in 30s…" forever — the visible "infinity
        // connecting" symptom from the regression report.
        if attempt > Self.maxRetries {
            stopAndMarkGone(
                reason: "Couldn't reach your Mac after \(Self.maxRetries) attempts. Check the daemon is running and tap Reconnect."
            )
            return
        }

        let delays = [1, 2, 4, 8, 16, 30]
        let delay = delays[min(nextStep - 1, delays.count - 1)]
        onState(.retrying(delay))

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if !self.isStopped() {
                self.onState(.connecting)
                self.openConnection()
            }
        }
    }

    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        switch http.statusCode {
        case 200:
            // Successful handshake — reset both the backoff cursor AND
            // the retry counter so a later transient blip doesn't share
            // a budget with prior failures.
            lock.lock()
            backoffStep = 0
            retryCount = 0
            lock.unlock()
            onState(.connected)
            completionHandler(.allow)
        case 404:
            // Session id is gone — daemon restarted, user killed it, or
            // we hit a stale handle. Don't retry; tell the UI.
            stopAndMarkGone(reason: "The session no longer exists on your Mac. Pull to refresh or start a new one.")
            completionHandler(.cancel)
        case 401, 403:
            stopAndMarkGone(reason: "Pairing token was rejected. Re-pair this Mac from the menubar.")
            completionHandler(.cancel)
        case 410:
            stopAndMarkGone(reason: "Session ended on the Mac.")
            completionHandler(.cancel)
        case 502, 503, 504:
            // Gateway / upstream error. Likely a misconfigured proxy or
            // the daemon temporarily overloaded. We DO want to retry
            // these, but the global retry cap in scheduleReconnect()
            // will eventually flip us to .gone instead of spinning.
            completionHandler(.cancel)
        default:
            // Other non-200s — let the existing retry path handle it
            // via didCompleteWithError + the retry cap.
            completionHandler(.cancel)
        }
    }

    /// Mark the connection as terminally gone — flips `stopped` so the
    /// reconnect timer doesn't fire and emits a `.gone` state.
    private func stopAndMarkGone(reason: String) {
        lock.lock(); stopped = true; lock.unlock()
        onState(.gone(reason: reason))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<nl])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            processLine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Any termination — clean EOF or error — triggers a reconnect.
        lock.lock()
        let stopped = self.stopped
        lock.unlock()
        if !stopped {
            scheduleReconnect()
        }
    }

    private func processLine(_ line: String) {
        if line.isEmpty {
            flushFrame()
            return
        }
        if line.hasPrefix(":") {
            // Comment line, e.g. ": connected"
            return
        }
        guard let colon = line.firstIndex(of: ":") else { return }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event":
            currentEvent = value
        case "data":
            dataBuffer.append(value)
        case "id":
            break    // not used
        case "retry":
            break    // honour server-suggested retry? Skipping for now.
        default:
            break
        }
    }

    private func flushFrame() {
        let bodyString = dataBuffer.joined(separator: "\n")
        let eventName = currentEvent
        currentEvent = nil
        dataBuffer.removeAll()
        guard !bodyString.isEmpty else { return }
        guard let data = bodyString.data(using: .utf8) else { return }
        do {
            let event = try JSONDecoder().decode(SmoothieEventWire.self, from: data)
            onEvent(event)
        } catch {
            // Drop malformed frames silently — server should never emit them,
            // but we don't want one bad frame to tear the stream.
            _ = eventName
        }
    }
}
