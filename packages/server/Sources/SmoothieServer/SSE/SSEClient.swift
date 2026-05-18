import Foundation

/// Streams SSE frames from a server-sent-events endpoint. Foundation's
/// `URLSession.bytes(for:)` buffers SSE responses on macOS in ways that break
/// real-time delivery, so we use a `URLSessionDataDelegate` instead.
final class SSEClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private let onLine: @Sendable (String) -> Void
    private let onError: @Sendable (Error?) -> Void
    private var buffer = ""
    private let lock = NSLock()

    init(onLine: @escaping @Sendable (String) -> Void, onError: @escaping @Sendable (Error?) -> Void) {
        self.onLine = onLine
        self.onError = onError
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = .infinity
        cfg.timeoutIntervalForResource = .infinity
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpShouldUsePipelining = false
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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            lock.unlock()
            onLine(line)
            lock.lock()
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onError(error)
    }
}
