import XCTest
@testable import PassBy

final class SessionGateTests: XCTestCase {
    func testEveryDepartureLocksAnUnlockedSession() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertTrue(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .unlocked)
        gate.willResignActive()
        XCTAssertEqual(gate.phase, .locked)
        gate.didBecomeActive()
        XCTAssertEqual(gate.phase, .locked)
    }

    func testPromptMayMakeSceneInactiveButNeverDisplaysSecretsThere() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.willResignActive()
        XCTAssertTrue(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .authenticating)
        gate.didBecomeActive()
        XCTAssertEqual(gate.phase, .unlocked)
    }

    func testBackgroundInvalidatesPendingBiometricSuccess() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.willResignActive()
        gate.didEnterBackground()
        XCTAssertFalse(gate.authenticationSucceeded(token))
        gate.didBecomeActive()
        XCTAssertEqual(gate.phase, .locked)
        let next = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertNotEqual(next, token)
        XCTAssertFalse(gate.authenticationSucceeded(token))
        XCTAssertTrue(gate.authenticationSucceeded(next))
    }

    func testCancelledAuthenticationCannotBeReused() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.authenticationFailed(token)
        XCTAssertFalse(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .locked)
    }

    func testLeavingDuringCloudRecoveryInvalidatesAuthentication() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.biometricPromptFinished(token)
        gate.willResignActive()
        gate.didBecomeActive()
        XCTAssertFalse(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .locked)
    }

    func testClipboardOnlyLocalAndExpiresInSixtySeconds() {
        let now = Date(timeIntervalSince1970: 100)
        let options = SecureClipboard.options(now: now)
        XCTAssertEqual(options[.localOnly] as? Bool, true)
        XCTAssertEqual(options[.expirationDate] as? Date, now.addingTimeInterval(60))
    }
    @MainActor
    private func savedTenonSession(store: TenonSessionStore, time: Date, expires: Double? = nil) throws {
        let identity = TenonAccount.Identity(issuer: "https://account.tenon.asia/api/auth", sub: "fixture-user",
            name: "Example", role: "user", expires: expires ?? (time.timeIntervalSince1970 * 1000 + 900000))
        try store.write(JSONEncoder().encode(TenonAccount.Grant(token: String(repeating: "t", count: 43), identity: identity)))
    }
    @MainActor
    func testTenonSignInSurvivesAColdRestartWithoutUnlockingNotebook() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        try savedTenonSession(store: store, time: now)
        let first = TenonAccount(store: store, now: { now })
        let reopened = TenonAccount(store: store, now: { now.addingTimeInterval(30) })
        XCTAssertEqual(first.identity?.sub, "fixture-user")
        XCTAssertEqual(reopened.identity?.sub, first.identity?.sub)
        XCTAssertEqual(reopened.identity?.expires, first.identity?.expires)
        XCTAssertNotEqual(VaultSession.shared.phase, .unlocked)
    }
    @MainActor
    func testExpiredOrInvalidStoredTenonSessionCannotBeRestored() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        for expiry in [now.timeIntervalSince1970 * 1000, now.timeIntervalSince1970 * 1000 + 900001] {
            try savedTenonSession(store: store, time: now, expires: expiry)
            XCTAssertNil(TenonAccount(store: store, now: { now }).identity)
            XCTAssertNil(try store.read())
        }
        try store.write(Data("invalid-session".utf8))
        XCTAssertNil(TenonAccount(store: store, now: { now }).identity)
        XCTAssertNil(try store.read())
    }
    @MainActor
    func testSigningOutClearsTheSavedTenonSession() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        try savedTenonSession(store: store, time: now)
        let account = TenonAccount(store: store, now: { now }, transport: { _ in throw URLError(.notConnectedToInternet) })
        account.signOut()
        XCTAssertNil(account.identity)
        XCTAssertNil(try store.read())
        XCTAssertNil(TenonAccount(store: store, now: { now }).identity)
    }
    @MainActor
    func testRevokedServerSessionClearsColdStartCredentials() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        try savedTenonSession(store: store, time: now)
        let account = TenonAccount(store: store, now: { now }, transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        })
        await account.validateRestoredSession()
        XCTAssertNil(account.identity)
        XCTAssertNil(try store.read())
    }

}
