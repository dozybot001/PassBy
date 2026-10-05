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
            name: "Example", role: "user", expires: expires ?? (time.timeIntervalSince1970 * 1000 + TenonAccount.sessionLifetime))
        try store.write(JSONEncoder().encode(TenonAccount.Grant(token: String(repeating: "t", count: 43), identity: identity)))
    }
    @MainActor
    func testTenonSignInSurvivesAColdRestartWithoutUnlockingNotebook() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        try savedTenonSession(store: store, time: now)
        let first = TenonAccount(store: store, now: { now })
        let reopened = TenonAccount(store: store, now: { now.addingTimeInterval(29 * 86400) })
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
        for expiry in [now.timeIntervalSince1970 * 1000, now.timeIntervalSince1970 * 1000 + TenonAccount.sessionLifetime + 1] {
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

    @MainActor
    private func rememberedGrant(time: Date, refresh: String = String(repeating: "r", count: 32), sub: String = "fixture-user", accessLifetime: Double = TenonAccount.sessionLifetime, version: Int = 3) -> TenonAccount.Grant {
        TenonAccount.Grant(token: String(repeating: "t", count: 43),
            identity: TenonAccount.Identity(issuer: "https://account.tenon.asia/api/auth", sub: sub, name: "Example", role: "user",
                expires: time.timeIntervalSince1970 * 1000 + accessLifetime),
            version: version, refreshToken: refresh, refreshExpires: time.timeIntervalSince1970 * 1000 + 2592000000)
    }
    @MainActor
    func testRememberedAccountSurvivesExpiredAccessOfflineWithoutExtendingAuthority() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let created = Date(timeIntervalSince1970: 1000), reopened = created.addingTimeInterval(86400)
        let original = rememberedGrant(time: created, accessLifetime: 900000, version: 2)
        try store.write(JSONEncoder().encode(original))
        let account = TenonAccount(store: store, now: { reopened }, transport: { _ in throw URLError(.notConnectedToInternet) })
        await account.validateRestoredSession()
        XCTAssertEqual(account.identity?.sub, original.identity.sub)
        XCTAssertEqual(account.identity?.expires, original.identity.expires)
        XCTAssertFalse(account.hasCurrentAuthorization)
        XCTAssertNotNil(try store.read())
        XCTAssertNotEqual(VaultSession.shared.phase, .unlocked)
    }
    @MainActor
    func testRememberedSessionRejectsAnExpiryBeyondThirtyDays() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        let invalid = rememberedGrant(time: now, accessLifetime: TenonAccount.sessionLifetime + 1)
        try store.write(JSONEncoder().encode(invalid))
        XCTAssertNil(TenonAccount(store: store, now: { now }).identity)
        XCTAssertNil(try store.read())
    }
    @MainActor
    func testColdStartRenewsAndPersistsRotatedCredentialWithTheSameIdentity() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let created = Date(timeIntervalSince1970: 1000), reopened = created.addingTimeInterval(86400)
        let original = rememberedGrant(time: created, accessLifetime: 900000, version: 2), next = rememberedGrant(time: reopened, refresh: String(repeating: "n", count: 32))
        try store.write(JSONEncoder().encode(original))
        var requests = 0
        let account = TenonAccount(store: store, now: { reopened }, transport: { request in
            requests += 1
            XCTAssertEqual(request.url?.lastPathComponent, "refresh")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["refreshToken"] as? String, original.refreshToken)
            XCTAssertEqual(body["sub"] as? String, original.identity.sub)
            XCTAssertEqual(body["session_version"] as? Int, 3)
            return (try JSONEncoder().encode(next), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await account.validateRestoredSession()
        XCTAssertTrue(account.hasCurrentAuthorization)
        XCTAssertEqual(requests, 1)
        let saved = try JSONDecoder().decode(TenonAccount.Grant.self, from: XCTUnwrap(store.read()))
        XCTAssertEqual(saved.refreshToken, next.refreshToken)
        XCTAssertEqual(saved.version, 3)
        XCTAssertEqual(saved.identity.sub, original.identity.sub)
        XCTAssertEqual(saved.identity.expires, reopened.timeIntervalSince1970 * 1000 + TenonAccount.sessionLifetime)
        XCTAssertNotEqual(VaultSession.shared.phase, .unlocked)
    }
    @MainActor
    func testNewClientAlsoAcceptsLegacyV2RenewalResponses() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let created = Date(timeIntervalSince1970: 1000), reopened = created.addingTimeInterval(86400)
        let original = rememberedGrant(time: created, accessLifetime: 900000, version: 2)
        let next = rememberedGrant(time: reopened, refresh: String(repeating: "n", count: 32), accessLifetime: 900000, version: 2)
        try store.write(JSONEncoder().encode(original))
        let account = TenonAccount(store: store, now: { reopened }, transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["session_version"] as? Int, 3)
            return (try JSONEncoder().encode(next), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await account.validateRestoredSession()
        XCTAssertTrue(account.hasCurrentAuthorization)
        let saved = try JSONDecoder().decode(TenonAccount.Grant.self, from: XCTUnwrap(store.read()))
        XCTAssertEqual(saved.version, 2)
        XCTAssertEqual(saved.refreshToken, next.refreshToken)
        XCTAssertEqual(saved.identity.expires, next.identity.expires)
    }
    @MainActor
    func testRememberedRevokedOrMismatchedIdentityIsRemoved() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let now = Date(timeIntervalSince1970: 1000)
        for status in [401, 403, 200] {
            try store.write(JSONEncoder().encode(rememberedGrant(time: now)))
            let wrong = rememberedGrant(time: now, refresh: String(repeating: "n", count: 32), sub: "another-user")
            let account = TenonAccount(store: store, now: { now }, transport: { request in
                (try JSONEncoder().encode(wrong), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            await account.validateRestoredSession()
            XCTAssertNil(account.identity); XCTAssertNil(try store.read())
        }
    }
    @MainActor
    func testRefreshExpiryRequiresLoginWhileTemporaryServerFailureKeepsRememberedProfile() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let created = Date(timeIntervalSince1970: 1000)
        try store.write(JSONEncoder().encode(rememberedGrant(time: created)))
        let beforeExpiry = TenonAccount(store: store, now: { created.addingTimeInterval(30 * 86400 - 0.001) })
        XCTAssertTrue(beforeExpiry.hasCurrentAuthorization)
        XCTAssertEqual(beforeExpiry.identity?.expires, created.timeIntervalSince1970 * 1000 + TenonAccount.sessionLifetime)
        XCTAssertNil(TenonAccount(store: store, now: { created.addingTimeInterval(30 * 86400) }).identity)
        XCTAssertNil(try store.read())
        try store.write(JSONEncoder().encode(rememberedGrant(time: created)))
        let account = TenonAccount(store: store, now: { created.addingTimeInterval(86400) }, transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        })
        await account.validateRestoredSession()
        XCTAssertNotNil(account.identity); XCTAssertNotNil(try store.read())
        XCTAssertTrue(account.hasCurrentAuthorization)
    }
    @MainActor
    func testConcurrentRenewalIsSingleFlightAndLogoutCannotBeUndoneByALateResponse() async throws {
        let store = TenonSessionStore(service: "passby-test-" + UUID().uuidString)
        defer { try? store.clear() }
        let created = Date(timeIntervalSince1970: 1000), reopened = created.addingTimeInterval(86400)
        try store.write(JSONEncoder().encode(rememberedGrant(time: created)))
        let next = rememberedGrant(time: reopened, refresh: String(repeating: "n", count: 32))
        var requests = 0
        var finish: CheckedContinuation<Void, Never>?
        let started = expectation(description: "Refresh started")
        let account = TenonAccount(store: store, now: { reopened }, transport: { request in
            if request.url?.lastPathComponent == "logout" {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            requests += 1
            await withCheckedContinuation { continuation in finish = continuation; started.fulfill() }
            return (try JSONEncoder().encode(next), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = Task { await account.validateRestoredSession() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await account.ensureCurrentSession() }
        await Task.yield()
        XCTAssertEqual(requests, 1)
        account.signOut()
        finish?.resume()
        await first.value; _ = await second.value
        XCTAssertNil(account.identity); XCTAssertNil(try store.read())
    }

}
