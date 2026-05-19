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
    }

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var lineBuffer = ""
    private var currentEvent: String?
    private var dataBuffer: [String] = []
    private var backoffStep: Int = 0
    private var stopped: Bool = false
    private let lock = NSLock()

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
        cfg.timeoutIntervalForRequest = .infinity
        cfg.timeoutIntervalForResource = .infinity
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpAdditionalHeaders = ["Accept": "text/event-stream"]
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start() {
        lock.lock(); stopped = false; lock.unlock()
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
        req.timeoutInterval = .infinity
        guard let session else { return }
        let t = session.dataTask(with: req)
        task = t
        t.resume()
    }

    private func scheduleReconnect() {
        lock.lock()
        if stopped { lock.unlock(); return }
        let nextStep = min(backoffStep + 1, 6)
        backoffStep = nextStep
        lock.unlock()

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
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            backoffStep = 0
            onState(.connected)
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
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
