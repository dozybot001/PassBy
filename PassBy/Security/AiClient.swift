import Foundation

/// The only place in the app that talks to a model provider.
///
/// It sends one request, to the address the person entered, when the person has just pressed Send
/// on the page that showed them the request. It keeps nothing: no log, no cookie, no cache, no retry.
enum AiClient {
    enum Problem: Equatable { case off, address, noKey, network, timeout, redirect, status, tooLarge, cancelled }

    /// `status` is the HTTP status for `.status` and `.redirect`. The response body is never kept,
    /// and no text from the system is carried: such text can hold a request header, and with it the key.
    struct Failure: Error, Equatable {
        let problem: Problem
        var status: Int?

        init(_ problem: Problem, status: Int? = nil) {
            self.problem = problem
            self.status = status
        }
    }

    /// A request body exactly as it was shown to the person, who then chose to send it.
    struct Approved {
        let body: String
    }

    static let connectTimeout: TimeInterval = 20
    static let readTimeout: TimeInterval = 60

    static var userAgent: String {
        "PassBy-iOS/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    /// Returns the text the model wrote. `progress` is told how many characters and how many
    /// suggestions have arrived so far. Throws `Failure` and sends nothing when a condition is not
    /// met. Cancelling the task that waits here closes the connection.
    static func send(settings: AiSettings, approved: Approved,
                     progress: @escaping @Sendable (_ chars: Int, _ items: Int) -> Void = { _, _ in }) async throws -> String {
        guard let config = settings.load() else { throw Failure(.off) }
        guard let endpoint = AiGrouping.endpoint(config.endpoint) else { throw Failure(.address) }
        // Read for this host and port only; a key saved for another is not returned.
        guard let key = settings.key(host: endpoint.authority).flatMap(AiGrouping.apiKey) else { throw Failure(.noKey) }
        // The address was checked with one parser and is used through another; the two have to agree on where it leads.
        guard let url = URL(string: endpoint.url), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == endpoint.host, (url.port ?? 443) == endpoint.port,
              url.user == nil, url.password == nil else { throw Failure(.address) }
        return try await post(url: url, key: key, body: approved.body, progress: progress)
    }

    /// Refuses redirects, and notes when the request has gone out, which is when the connection is known to be made.
    private final class Watcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var isConnected = false
        private var gaveUp = false

        var connected: Bool { lock.withLock { isConnected } }
        var timedOut: Bool { lock.withLock { gaveUp } }
        func markConnected() { lock.withLock { isConnected = true } }
        /// True when the connection had not been made, in which case this is now a timeout.
        func giveUpIfNotConnected() -> Bool {
            lock.withLock {
                if !isConnected { gaveUp = true }
                return gaveUp
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            // Not followed: the 3xx itself becomes the response, and the caller treats it as a failure.
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            markConnected()
        }
    }

    /// One POST. Only `send` calls this, after its checks.
    static func post(url: URL, key: String, body: String, configuration: URLSessionConfiguration = .ephemeral,
                     progress: @escaping @Sendable (Int, Int) -> Void) async throws -> String {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        // The longest wait between two pieces of data.
        configuration.timeoutIntervalForRequest = readTimeout

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        // The default would name the app's build and the system's network library.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // The system adds this header whatever is done; left alone it lists the languages set on the iPhone.
        request.setValue("*", forHTTPHeaderField: "Accept-Language")

        let session = URLSession(configuration: configuration)
        let watcher = Watcher()
        let work = Task { () throws -> String in
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: request, delegate: watcher)
            watcher.markConnected()
            guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure(.network) }
            if (300...399).contains(status) { throw Failure(.redirect, status: status) }
            // An error body can repeat part of the key or the request, so it is not read.
            guard (200...299).contains(status) else { throw Failure(.status, status: status) }
            var reader = AiGrouping.StreamReader()
            // Not `bytes.lines`: that reads a whole line, however long, before any limit applies.
            var lines = AiGrouping.LineReader()
            var read = 0
            func take(_ line: String) throws {
                let before = reader.received
                try reader.line(line)
                if reader.received != before { progress(reader.received, reader.items) }
            }
            for try await byte in bytes {
                read += 1
                if read > AiGrouping.maxResponseBytes { throw Failure(.tooLarge) }
                if let line = try lines.feed(byte) {
                    try take(line)
                    if reader.done { break }
                }
            }
            if !reader.done, let last = lines.finish() { try take(last) }
            try Task.checkCancellation()
            return try reader.content()
        }
        // The system has one timeout for both connecting and waiting; connecting gets less.
        let watchdog = Task {
            try await Task.sleep(for: .seconds(connectTimeout))
            if watcher.giveUpIfNotConnected() { work.cancel() }
        }
        defer { watchdog.cancel() }
        do {
            return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        } catch {
            // Nothing but a Failure leaves here, and it carries no text from the error.
            if Task.isCancelled { throw Failure(.cancelled) }
            if watcher.timedOut { throw Failure(.timeout) }
            if let failure = error as? Failure { throw failure }
            if error is AiGrouping.UnusableAnswer { throw Failure(.tooLarge) }
            if (error as? URLError)?.code == .timedOut { throw Failure(.timeout) }
            throw Failure(.network)
        }
    }
}
