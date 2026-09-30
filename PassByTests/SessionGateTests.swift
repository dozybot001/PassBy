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
}
