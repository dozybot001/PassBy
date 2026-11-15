import CryptoKit
import Foundation
import Network

// The transport of LAN sync (docs/sync.md 6): a little HTTP/1.1 that carries sealed frames, the
// listening side and the connecting side. HTTP is an envelope only; nothing is trusted before a
// frame opens. This is the only file in the app that opens a network connection.

/// An address the other device is reached at: a private IPv4 address written out, and a port.
struct SyncAddress: Equatable, CustomStringConvertible {
    let host: String
    let port: UInt16
    var description: String { "\(host):\(port)" }

    /// Reads `10.1.2.3:52814`. Names are not looked up, and only 10/8, 172.16/12 and 192.168/16 are accepted.
    static func parse(_ text: String) -> SyncAddress? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let halves = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let parts = halves[0].split(separator: ".", omittingEmptySubsequences: false)
        func number(_ text: Substring, max: Int, digits: Int) -> Int? {
            guard (1...digits).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), value <= max else { return nil }
            return value
        }
        guard parts.count == 4, let port = number(halves[1], max: 65535, digits: 5), port >= 1 else { return nil }
        let bytes = parts.compactMap { number($0, max: 255, digits: 3) }
        guard bytes.count == 4 else { return nil }
        let (a, b) = (bytes[0], bytes[1])
        guard a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) else { return nil }
        return SyncAddress(host: bytes.map(String.init).joined(separator: "."), port: UInt16(port))
    }

    /// This iPhone's address on the Wi-Fi or wired network it is on, or nil when it is on none.
    /// Mobile data and VPN interfaces are left out.
    static func local(port: UInt16) -> SyncAddress? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [(name: String, address: SyncAddress)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0, interface.ifa_flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0 else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue } // Wi-Fi and wired; pdp_ip is mobile data, utun is VPN.
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0,
                  let parsed = parse("\(String(cString: host)):\(port)") else { continue }
            found.append((name, parsed))
        }
        return found.sorted { $0.name < $1.name }.first?.address
    }
}

enum SyncHTTP {
    static let maxBody = 8 * 1024 * 1024
    static let maxHead = 8192
    static let maxHeaders = 32
    static let timeout: TimeInterval = 15
    static let begin = "/passby-sync/v1/begin"
    static let exchange = "/passby-sync/v1/exchange"
    static let origin = "https://passby.tenonai.cn"

    struct Message: Equatable {
        let start: String
        let headers: [String: String]
        let body: Data
    }

    enum Parsed: Equatable {
        case incomplete
        /// Malformed or too large: the connection is dropped without an answer.
        case bad
        case complete(Message)
    }

    /// Reads one message from the bytes received so far.
    static func parse(_ data: Data) -> Parsed {
        let bytes = Data(data)
        guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else { return bytes.count > maxHead ? .bad : .incomplete }
        guard end.upperBound <= maxHead, let head = String(data: bytes[..<end.lowerBound], encoding: .isoLatin1) else { return .bad }
        let lines = head.components(separatedBy: "\r\n")
        guard lines.count - 1 <= maxHeaders else { return .bad }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .bad }
            let name = line[..<colon].lowercased()
            if headers.updateValue(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces), forKey: name) != nil, name == "content-length" { return .bad }
        }
        if headers["transfer-encoding"] != nil || headers["expect"] != nil { return .bad }
        let text = headers["content-length"] ?? "0"
        guard (1...8).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }), let length = Int(text), length <= maxBody else { return .bad }
        let body = bytes[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .complete(Message(start: lines[0], headers: headers, body: Data(body.prefix(length))))
    }

    static func message(start: String, headers: [(String, String)], body: Data) -> Data {
        var head = start + "\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// What the listening side answers to each request (docs/sync.md 6.2). No networking here: the
/// listener feeds it parsed messages on one queue.
///
/// A pairing code is good for one session: once a guest's greeting has opened, no other device can
/// start one. `exchange` is given the guest's state once a frame has opened and been read; it
/// merges, saves the notebook and returns what to answer, or nil when the notebook could not be saved.
final class SyncHostCore {
    static let maxFailures = 5
    static let nonceLifetime: TimeInterval = 60
    static let maxPending = 4

    struct Reply: Equatable {
        let status: String
        let body: Data
    }

    private struct Session {
        let hostNonce: Data
        let guestNonce: Data
        let keys: SyncCrypto.Keys
        var counter: UInt64
    }

    private var code: String
    private let authority: String
    private let iterations: Int
    private let now: () -> Date
    private let exchange: (SyncState) -> (state: SyncState, summary: SyncSummary)?
    private var pending: [Data: Date] = [:]
    private var session: Session?
    private(set) var failures = 0
    private(set) var stopped = false

    init(code: String, authority: String, iterations: Int = SyncCrypto.iterations, now: @escaping () -> Date = Date.init,
         exchange: @escaping (SyncState) -> (state: SyncState, summary: SyncSummary)?) {
        self.code = code
        self.authority = authority
        self.iterations = iterations
        self.now = now
        self.exchange = exchange
    }

    /// Forgets the code and the keys; every later request is told the host has stopped.
    func stop() {
        stopped = true
        code = ""
        session = nil
        pending = [:]
    }

    /// The answer to a request, or nil to drop the connection without one.
    func respond(to request: SyncHTTP.Message) -> Reply? {
        let parts = request.start.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return nil }
        // A page that reached this iPhone under another name (DNS rebinding) is not answered at all.
        guard request.headers["host"] == authority else { return nil }
        let method = String(parts[0]), path = String(parts[1])
        if method == "POST", request.headers["content-length"] == nil { return nil }
        func reply(_ status: String, _ body: Data = Data()) -> Reply { Reply(status: status, body: body) }
        if stopped { return reply("410 Gone") }
        // Another website's page. Not counted against the code.
        if let origin = request.headers["origin"], origin != SyncHTTP.origin { return reply("403 Forbidden") }
        if method == "OPTIONS" { return reply("204 No Content") }
        if method == "POST", path == SyncHTTP.begin, request.body.isEmpty {
            guard let nonce = begin() else { return reply("403 Forbidden") }
            return reply("200 OK", nonce)
        }
        if method == "POST", path == SyncHTTP.exchange {
            do {
                guard let body = try answer(request.body) else { return reply("400 Bad Request") }
                return reply("200 OK", body)
            } catch SyncError.refused {
                failures += 1
                return reply("403 Forbidden")
            } catch {
                return reply("400 Bad Request")
            }
        }
        return reply("400 Bad Request")
    }

    /// A fresh host nonce, or nil: the code has been used by a session, or too many nonces are waiting.
    private func begin() -> Data? {
        guard session == nil else { return nil }
        let time = now()
        pending = pending.filter { time.timeIntervalSince($0.value) < Self.nonceLifetime }
        guard pending.count < Self.maxPending else { return nil }
        let nonce = ExportFormat.random(SyncCrypto.nonceLength)
        pending[nonce] = time
        return nonce
    }

    /// The sealed answer, or nil when the request opened but cannot be answered. Throws `.refused` when it does not open.
    private func answer(_ body: Data) throws -> Data? {
        let request = try SyncCrypto.readRequest(body)
        let keys: SyncCrypto.Keys
        let reply: Data
        if var current = session {
            guard current.hostNonce == request.hostNonce, current.guestNonce == request.guestNonce, request.counter > current.counter else { throw SyncError.refused }
            keys = current.keys
            let plain = try SyncCrypto.open(request.sealed, key: keys.guestToHost, hostNonce: request.hostNonce, guestNonce: request.guestNonce,
                direction: SyncCrypto.guestToHost, counter: request.counter)
            current.counter = request.counter
            session = current
            guard let state = try? SyncCodec.readRequest(plain), let merged = exchange(state) else { return nil }
            reply = SyncCodec.response(merged.state, merged.summary)
        } else {
            // A host nonce starts one session, within a minute of being handed out.
            guard let issued = pending.removeValue(forKey: request.hostNonce), now().timeIntervalSince(issued) < Self.nonceLifetime else { throw SyncError.refused }
            keys = try SyncCrypto.deriveKeys(code: code, hostNonce: request.hostNonce, guestNonce: request.guestNonce, iterations: iterations)
            let plain = try SyncCrypto.open(request.sealed, key: keys.guestToHost, hostNonce: request.hostNonce, guestNonce: request.guestNonce,
                direction: SyncCrypto.guestToHost, counter: request.counter)
            // The first frame is the greeting and carries nothing; the state comes after the guest
            // has seen this host answer it.
            guard request.counter == 0, SyncCodec.isHello(plain) else { return nil }
            // From here on the code belongs to this session: no more nonces are handed out.
            session = Session(hostNonce: request.hostNonce, guestNonce: request.guestNonce, keys: keys, counter: 0)
            pending = [:]
            reply = SyncCodec.hello
        }
        let sealed = try SyncCrypto.seal(reply, key: keys.hostToGuest, hostNonce: request.hostNonce, guestNonce: request.guestNonce,
            direction: SyncCrypto.hostToGuest, counter: request.counter)
        return SyncCrypto.responseBody(counter: request.counter, sealed: sealed)
    }
}

/// The listening side: an `NWListener` bound to this iPhone's own address on the local network. It
/// serves one request per connection and stops for good when `stop()` is called, after five frames
/// that did not open, or after ten minutes without a request.
final class SyncHost {
    enum Stop { case closed, idle, wrongCode, failed }
    static let idleLimit: TimeInterval = 10 * 60

    private let queue = DispatchQueue(label: "cn.tenonai.passby.sync-host")
    private let listener: NWListener
    private let core: SyncHostCore
    private let onStopped: (Stop) -> Void
    private var lastRequest = Date()
    private var idleTimer: DispatchSourceTimer?
    private var finished = false
    let address: SyncAddress

    /// Throws when the port cannot be opened on the address.
    init(code: String, address: SyncAddress, iterations: Int = SyncCrypto.iterations,
         exchange: @escaping (SyncState) -> (state: SyncState, summary: SyncSummary)?, onStopped: @escaping (Stop) -> Void) throws {
        let parameters = NWParameters.tcp
        // Only the address shown to the person: not every interface, and never mobile data.
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address.host), port: NWEndpoint.Port(rawValue: address.port)!)
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        self.address = address
        core = SyncHostCore(code: code, authority: address.description, iterations: iterations, exchange: exchange)
        self.onStopped = onStopped
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(.failed) }
        }
        listener.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, Date().timeIntervalSince(self.lastRequest) >= Self.idleLimit else { return }
            self.finish(.idle)
        }
        timer.resume()
        idleTimer = timer
    }

    /// Stops listening and forgets the code and the keys.
    func stop() {
        queue.async { self.finish(.closed) }
    }

    private func finish(_ reason: Stop) {
        guard !finished else { return }
        finished = true
        core.stop()
        idleTimer?.cancel()
        listener.cancel()
        onStopped(reason)
    }

    private func serve(_ connection: NWConnection) {
        var received = Data()
        let deadline = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + SyncHTTP.timeout, execute: deadline)
        func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
                guard let self, !self.finished else { return connection.cancel() }
                if let data { received.append(data) }
                switch SyncHTTP.parse(received) {
                case .bad:
                    connection.cancel()
                case .incomplete:
                    if complete || error != nil { connection.cancel() } else { read() }
                case .complete(let message):
                    guard let reply = self.core.respond(to: message) else { return connection.cancel() }
                    self.lastRequest = Date()
                    let headers = [("Access-Control-Allow-Origin", SyncHTTP.origin), ("Access-Control-Allow-Methods", "POST"),
                        ("Access-Control-Allow-Headers", "content-type"), ("Cache-Control", "no-store"), ("Content-Type", "application/octet-stream")]
                    connection.send(content: SyncHTTP.message(start: "HTTP/1.1 \(reply.status)", headers: headers, body: reply.body),
                        completion: .contentProcessed { _ in
                            deadline.cancel()
                            connection.cancel()
                        })
                    if self.core.failures >= SyncHostCore.maxFailures { self.finish(.wrongCode) }
                }
            }
        }
        connection.start(queue: queue)
        read()
    }
}

enum SyncGuestError: Error, Equatable {
    /// Nothing answered at the address.
    case unreachable
    /// The host refused the frame: the code is wrong or already used.
    case wrongCode
    /// The host has stopped listening.
    case stopped
    /// The answer did not come from a device holding the code, or is not a valid state.
    case untrusted
    /// The host could not take the request.
    case failed
}

/// The connecting side when it is an iPhone. One instance is one session; `exchange` may be called again.
final class SyncGuest {
    typealias Post = (_ path: String, _ body: Data) async throws -> (status: Int, body: Data)

    private let code: String
    private let iterations: Int
    private let post: Post
    private var hostNonce: Data?
    private let guestNonce = ExportFormat.random(SyncCrypto.nonceLength)
    private var keys: SyncCrypto.Keys?
    private var counter: UInt64 = 0
    private var greeted = false

    init(code: String, iterations: Int = SyncCrypto.iterations, post: @escaping Post) {
        self.code = code
        self.iterations = iterations
        self.post = post
    }

    convenience init(address: SyncAddress, code: String) {
        self.init(code: code) { path, body in try await SyncGuest.send(to: address, path: path, body: body) }
    }

    /// Sends this device's state and returns the merged state with what changed here. Nothing of the
    /// notebook is sent before the other side has shown, by answering the greeting, that it holds the code too.
    func exchange(_ state: SyncState) async throws -> (state: SyncState, summary: SyncSummary) {
        if hostNonce == nil {
            let nonce = try await request(SyncHTTP.begin, Data())
            guard nonce.count == SyncCrypto.nonceLength else { throw SyncGuestError.untrusted }
            hostNonce = nonce
        }
        if keys == nil {
            let (code, nonce, guest, rounds) = (code, hostNonce!, guestNonce, iterations)
            keys = try await Task.detached { try SyncCrypto.deriveKeys(code: code, hostNonce: nonce, guestNonce: guest, iterations: rounds) }.value
        }
        if !greeted {
            guard SyncCodec.isHello(try await frame(SyncCodec.hello)) else { throw SyncGuestError.untrusted }
            greeted = true
        }
        guard let answer = try? SyncCodec.readResponse(try await frame(SyncCodec.request(state))) else { throw SyncGuestError.untrusted }
        return answer
    }

    /// Seals and posts one frame, and opens the answer.
    private func frame(_ plain: Data) async throws -> Data {
        guard let nonce = hostNonce, let keys else { throw SyncGuestError.failed }
        let sent = counter
        counter += 1
        do {
            let sealed = try SyncCrypto.seal(plain, key: keys.guestToHost, hostNonce: nonce, guestNonce: guestNonce, direction: SyncCrypto.guestToHost, counter: sent)
            let answer = try SyncCrypto.readResponse(try await request(SyncHTTP.exchange, SyncCrypto.requestBody(hostNonce: nonce, guestNonce: guestNonce, counter: sent, sealed: sealed)))
            guard answer.counter == sent else { throw SyncGuestError.untrusted }
            return try SyncCrypto.open(answer.sealed, key: keys.hostToGuest, hostNonce: nonce, guestNonce: guestNonce, direction: SyncCrypto.hostToGuest, counter: sent)
        } catch is SyncError {
            throw SyncGuestError.untrusted
        }
    }

    private func request(_ path: String, _ body: Data) async throws -> Data {
        let response: (status: Int, body: Data)
        do {
            response = try await post(path, body)
        } catch {
            throw SyncGuestError.unreachable
        }
        switch response.status {
        case 200: return response.body
        case 403: throw SyncGuestError.wrongCode
        case 410: throw SyncGuestError.stopped
        default: throw SyncGuestError.failed
        }
    }

    /// One request over a plain socket to the address, never through the system's HTTP stack.
    static func send(to address: SyncAddress, path: String, body: Data) async throws -> (status: Int, body: Data) {
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: NWEndpoint.Host(address.host), port: NWEndpoint.Port(rawValue: address.port)!, using: parameters)
        let queue = DispatchQueue(label: "cn.tenonai.passby.sync-guest")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(status: Int, body: Data), Error>) in
            var done = false
            var received = Data()
            func finish(_ result: Result<(status: Int, body: Data), Error>) {
                guard !done else { return }
                done = true
                connection.cancel()
                continuation.resume(with: result)
            }
            queue.asyncAfter(deadline: .now() + SyncHTTP.timeout) { finish(.failure(SyncGuestError.unreachable)) }
            func read() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                    if let data { received.append(data) }
                    switch SyncHTTP.parse(received) {
                    case .bad: finish(.failure(SyncGuestError.unreachable))
                    case .incomplete: if complete || error != nil { finish(.failure(SyncGuestError.unreachable)) } else { read() }
                    case .complete(let message):
                        let parts = message.start.split(separator: " ")
                        guard parts.count >= 2, let status = Int(parts[1]) else { return finish(.failure(SyncGuestError.unreachable)) }
                        finish(.success((status, message.body)))
                    }
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let message = SyncHTTP.message(start: "POST \(path) HTTP/1.1",
                        headers: [("Host", address.description), ("Content-Type", "application/octet-stream")], body: body)
                    connection.send(content: message, completion: .contentProcessed { error in
                        if error != nil { finish(.failure(SyncGuestError.unreachable)) } else { read() }
                    })
                case .failed, .waiting: finish(.failure(SyncGuestError.unreachable))
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }
}
