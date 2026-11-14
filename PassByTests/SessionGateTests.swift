import XCTest
@testable import PassBy

final class SessionGateTests: XCTestCase {
    private func unlocked() throws -> SessionGate {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertTrue(gate.authenticationSucceeded(token))
        return gate
    }

    func testColdStartIsLockedAndOpensAfterOneCheck() throws {
        var gate = SessionGate()
        XCTAssertEqual(gate.phase, .locked)
        let token = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertEqual(gate.phase, .authenticating)
        XCTAssertNil(gate.beginAuthentication())
        XCTAssertTrue(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .unlocked)
    }

    func testComingBackWithinFiveMinutesStaysOpen() throws {
        var gate = try unlocked()
        gate.didEnterBackground(at: 1000)
        gate.didBecomeActive(at: 1000 + SessionGate.grace - 1)
        XCTAssertEqual(gate.phase, .unlocked)
    }

    func testComingBackAfterFiveMinutesLocks() throws {
        var gate = try unlocked()
        gate.didEnterBackground(at: 1000)
        gate.didBecomeActive(at: 1000 + SessionGate.grace)
        XCTAssertEqual(gate.phase, .locked)
    }

    func testTimeAwayCountsFromTheFirstDeparture() throws {
        var gate = try unlocked()
        gate.didEnterBackground(at: 1000)
        gate.didEnterBackground(at: 1200)
        gate.didBecomeActive(at: 1000 + SessionGate.grace)
        XCTAssertEqual(gate.phase, .locked)
    }

    func testEachReturnStartsANewCount() throws {
        var gate = try unlocked()
        gate.didEnterBackground(at: 1000)
        gate.didBecomeActive(at: 1200)
        gate.didEnterBackground(at: 1250)
        gate.didBecomeActive(at: 1250 + SessionGate.grace - 1)
        XCTAssertEqual(gate.phase, .unlocked)
    }

    func testLeavingDuringTheCheckCancelsItAndALateAnswerIsRejected() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.didEnterBackground(at: 10)
        XCTAssertEqual(gate.phase, .locked)
        XCTAssertFalse(gate.authenticationSucceeded(token))
        XCTAssertEqual(gate.phase, .locked)
    }

    func testCancelledCheckCannotBeReused() throws {
        var gate = SessionGate()
        let token = try XCTUnwrap(gate.beginAuthentication())
        gate.authenticationFailed(token)
        XCTAssertEqual(gate.phase, .locked)
        XCTAssertFalse(gate.authenticationSucceeded(token))
        let next = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertNotEqual(next, token)
    }

    func testAnswerFromAnEarlierCheckDoesNotOpenALaterOne() throws {
        var gate = SessionGate()
        let first = try XCTUnwrap(gate.beginAuthentication())
        gate.lock()
        _ = try XCTUnwrap(gate.beginAuthentication())
        XCTAssertFalse(gate.authenticationSucceeded(first))
        XCTAssertEqual(gate.phase, .authenticating)
    }

    func testOpeningWithoutACheckOnlyWorksFromLocked() throws {
        var gate = SessionGate()
        gate.open()
        XCTAssertEqual(gate.phase, .unlocked)
        gate.lock()
        _ = try XCTUnwrap(gate.beginAuthentication())
        gate.open()
        XCTAssertEqual(gate.phase, .authenticating)
    }

    func testUptimeClockMovesForward() {
        let first = Uptime.now
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThanOrEqual(Uptime.now, first)
    }

    func testClipboardOnlyLocalAndExpiresInSixtySeconds() {
        let now = Date(timeIntervalSince1970: 1000)
        let options = SecureClipboard.options(now: now)
        XCTAssertEqual(options[.localOnly] as? Bool, true)
        XCTAssertEqual(options[.expirationDate] as? Date, now.addingTimeInterval(60))
    }
}
