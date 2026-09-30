import Foundation

/// The biometric prompt itself can make the scene inactive. Backgrounding must
/// invalidate it; a late success must never reopen a notebook in another session.
struct SessionGate {
    enum Phase { case locked, authenticating, unlocked }
    private(set) var phase: Phase = .locked
    private(set) var isActive = true
    private(set) var generation: UInt64 = 0
    private var pendingSuccess = false
    private var biometricPromptActive = false

    mutating func beginAuthentication() -> UInt64? {
        guard isActive, phase == .locked else { return nil }
        generation &+= 1
        phase = .authenticating
        pendingSuccess = false
        biometricPromptActive = true
        return generation
    }

    func accepts(_ token: UInt64) -> Bool {
        token == generation && phase == .authenticating
    }

    mutating func biometricPromptFinished(_ token: UInt64) {
        if accepts(token) { biometricPromptActive = false }
    }

    @discardableResult
    mutating func authenticationSucceeded(_ token: UInt64) -> Bool {
        guard accepts(token) else { return false }
        pendingSuccess = true
        if isActive { phase = .unlocked }
        return true
    }

    mutating func authenticationFailed(_ token: UInt64) {
        guard accepts(token) else { return }
        lock()
    }

    mutating func willResignActive() {
        isActive = false
        if phase != .authenticating || !biometricPromptActive { lock() }
    }

    mutating func didEnterBackground() {
        isActive = false
        lock()
    }

    mutating func didBecomeActive() {
        isActive = true
        if phase == .authenticating && pendingSuccess { phase = .unlocked }
    }

    mutating func lock() {
        generation &+= 1
        pendingSuccess = false
        biometricPromptActive = false
        phase = .locked
    }
}
