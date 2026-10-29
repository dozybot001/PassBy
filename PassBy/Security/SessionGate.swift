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
        biometricPromptActive = false
        if isActive { phase = .unlocked }
        return true
    }

    mutating func authenticationFailed(_ token: UInt64) {
        guard accepts(token) else { return }
        lock()
    }

    /// A second check while unlocked, before showing the recovery key. Its
    /// prompt may make the scene inactive; leaving the app still locks.
    mutating func beginReauthentication() -> UInt64? {
        guard isActive, phase == .unlocked, !biometricPromptActive else { return nil }
        biometricPromptActive = true
        return generation
    }

    @discardableResult
    mutating func reauthenticationFinished(_ token: UInt64) -> Bool {
        guard token == generation, phase == .unlocked else { return false }
        biometricPromptActive = false
        return true
    }

    mutating func willResignActive() {
        isActive = false
        if !biometricPromptActive { lock() }
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
