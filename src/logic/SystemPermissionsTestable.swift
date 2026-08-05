import Foundation

/// Rate-limiting for the permission-loss restart path, extracted so it can be unit-tested without
/// touching UserDefaults or actually relaunching the app.
///
/// `SystemPermissions.checkPermissionsPostStartup` relaunches Ztabby whenever Accessibility reads
/// `.notGranted`, and every relaunch resets `ScreenRecordingPermission.hasRequestedOnce`, so an
/// unbounded restart loop is also an unbounded system-prompt loop — the failure mode that can bury a
/// machine in dialogs faster than they can be dismissed. A degraded app showing the permissions window
/// is strictly better than that, so restarts get a budget.
class SystemPermissionsTestable {
    static let restartWindowSeconds: Double = 300
    static let maxRestartsPerWindow = 3

    /// attempts still inside the sliding window ending at `now`, in their original order.
    /// Timestamps in the future are deliberately kept: a backwards clock jump must spend budget rather
    /// than hand out unlimited restarts.
    static func recentRestarts(_ attempts: [Double], now: Double, windowSeconds: Double = restartWindowSeconds) -> [Double] {
        attempts.filter { now - $0 < windowSeconds }
    }

    static func restartIsAllowed(attempts: [Double], now: Double, windowSeconds: Double = restartWindowSeconds) -> Bool {
        recentRestarts(attempts, now: now, windowSeconds: windowSeconds).count < maxRestartsPerWindow
    }

    /// the attempt list to persist after taking a restart: pruned of anything stale, plus this attempt
    static func recordingRestart(_ attempts: [Double], now: Double, windowSeconds: Double = restartWindowSeconds) -> [Double] {
        recentRestarts(attempts, now: now, windowSeconds: windowSeconds) + [now]
    }
}
