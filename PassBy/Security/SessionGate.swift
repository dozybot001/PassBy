import Foundation

/// The one door in front of the notebook. A cold start asks once; coming back
/// asks again only after five minutes away. The times are seconds on a clock
/// that keeps running while the phone sleeps and ignores changes to the date.
struct SessionGate {
    enum Phase { case locked, authenticating, unlocked }
    static let grace: TimeInterval = 5 * 60

    private(set) var phase: Phase = .locked
    private(set) var generation: UInt64 = 0
    private var leftAt: TimeInterval?

    mutating func beginAuthentication() -> UInt64? {
        guard phase == .locked else { return nil }
        generation &+= 1
        phase = .authenticating
        return generation
    }

    /// A late answer from an earlier prompt must never open the notebook.
    func accepts(_ token: UInt64) -> Bool {
        token == generation && phase == .authenticating
    }

    @discardableResult
    mutating func authenticationSucceeded(_ token: UInt64) -> Bool {
        guard accepts(token) else { return false }
        phase = .unlocked
        leftAt = nil
        return true
    }

    mutating func authenticationFailed(_ token: UInt64) {
        guard accepts(token) else { return }
        lock()
    }

    /// The door is switched off, or the phone has no screen lock.
    mutating func open() {
        guard phase == .locked else { return }
        generation &+= 1
        phase = .unlocked
        leftAt = nil
    }

    mutating func didEnterBackground(at uptime: TimeInterval) {
        if phase == .authenticating { lock() }
        if leftAt == nil { leftAt = uptime }
    }

    /// Locks when the app was away for five minutes or more.
    mutating func didBecomeActive(at uptime: TimeInterval) {
        defer { leftAt = nil }
        guard phase == .unlocked, let leftAt, uptime - leftAt >= Self.grace else { return }
        lock()
    }

    mutating func lock() {
        generation &+= 1
        phase = .locked
        leftAt = nil
    }
}

enum Uptime {
    static var now: TimeInterval { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
}
