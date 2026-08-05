import XCTest

final class SystemPermissionsRestartTests: XCTestCase {
    private let now: Double = 1_000_000

    func testRestartsAreAllowedWhileUnderBudget() throws {
        XCTAssertTrue(SystemPermissionsTestable.restartIsAllowed(attempts: [], now: now))
        XCTAssertTrue(SystemPermissionsTestable.restartIsAllowed(attempts: [now - 10], now: now))
        XCTAssertTrue(SystemPermissionsTestable.restartIsAllowed(attempts: [now - 10, now - 20], now: now))
    }

    /// the regression this guards: checkPermissionsPostStartup restarts the app whenever Accessibility
    /// reads notGranted, and every relaunch resets ScreenRecordingPermission.hasRequestedOnce, so an
    /// unbounded restart loop is also an unbounded system-prompt loop
    func testRestartIsRefusedOnceBudgetIsExhausted() throws {
        let attempts = [now - 10, now - 20, now - 30]
        XCTAssertFalse(SystemPermissionsTestable.restartIsAllowed(attempts: attempts, now: now))
    }

    func testBudgetRefillsAfterTheWindowPasses() throws {
        let window = SystemPermissionsTestable.restartWindowSeconds
        let stale = [now - window - 1, now - window - 2, now - window - 3]
        XCTAssertTrue(SystemPermissionsTestable.restartIsAllowed(attempts: stale, now: now))
    }

    func testOnlyAttemptsInsideTheWindowCount() throws {
        let window = SystemPermissionsTestable.restartWindowSeconds
        // two recent, two stale: still under budget
        let mixed = [now - 10, now - 20, now - window - 1, now - window - 2]
        XCTAssertTrue(SystemPermissionsTestable.restartIsAllowed(attempts: mixed, now: now))
        XCTAssertEqual(SystemPermissionsTestable.recentRestarts(mixed, now: now), [now - 10, now - 20])
    }

    /// a backwards clock jump must not hand out unlimited restarts
    func testFutureTimestampsAreNotDiscarded() throws {
        let attempts = [now + 10, now + 20, now + 30]
        XCTAssertFalse(SystemPermissionsTestable.restartIsAllowed(attempts: attempts, now: now))
    }

    func testRecordedAttemptsArePrunedAndAppended() throws {
        let window = SystemPermissionsTestable.restartWindowSeconds
        let recorded = SystemPermissionsTestable.recordingRestart([now - 10, now - window - 5], now: now)
        XCTAssertEqual(recorded, [now - 10, now])
    }
}
