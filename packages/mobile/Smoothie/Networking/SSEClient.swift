import Foundation

/// Consumes a Server-Sent Events stream. Uses a `URLSessionDataDelegate` so
/// `URLSession` delivers bytes incrementally — `URLSession.bytes(for:)` buffers
/// SSE responses on Apple platforms and breaks real-time delivery.
final class SSEClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias OnEvent = @Sendable (_ type: String, _ data: String) -> Void

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private let onEvent: OnEvent
    private let onError: @Sendable (Error?) -> Void
    private let onOpen: @Sendable () -> Void
    private let lock = NSLock()
    private var lineBuffer = ""
    private var dataBuffer = ""
    private var eventType = "message"

    init(
        onOpen: @escaping @Sendable () -> Void = {},
        onEvent: @escaping OnEvent,
        onError: @escaping @Sendable (Error?) -> Void = { _ in }
    ) {
        self.onOpen = onOpen
        self.onEvent = onEvent
        self.onError = onError
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = .infinity
        cfg.timeoutIntervalForResource = .infinity
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start(url: URL) {
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = .infinity
        let t = session.dataTask(with: req)
        task = t
        t.resume()
    }

    func cancel() {
        task?.cancel()
        session.invalidateAndCancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
        onOpen()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<nl])
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            process(line: line)
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onError(error)
    }

    private func process(line raw: String) {
        let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if line.isEmpty {
            if !dataBuffer.isEmpty {
                let payload = dataBuffer
                let type = eventType
                dataBuffer = ""
                eventType = "message"
                onEvent(type, payload)
            }
            return
        }
        if line.hasPrefix(":") {
            // Comment frame (e.g. ": connected") — ignore
            return
        }
        if let colon = line.firstIndex(of: ":") {
            let field = String(line[line.startIndex..<colon])
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event":
                eventType = value
            case "data":
                if !dataBuffer.isEmpty { dataBuffer.append("\n") }
                dataBuffer.append(value)
            default:
                break
            }
        }
    }
}
