import Cocoa
import IOKit.hid

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    private static var timer: DispatchSourceTimer!
    private static var timerIsFrequent = false

    static func ensurePermissionsAreGranted() {
        timer = DispatchSource.makeTimerSource(queue: BackgroundWork.permissionsCheckOnTimerQueue.strongUnderlyingQueue)
        timer.setEventHandler(handler: checkPermissionsOnTimer)
        setImmediateTimer()
        timer.resume()
    }

    private static func checkPermissionsOnTimer() {
        AccessibilityPermission.update()
        let isPermissionsWindowVisible = PermissionsWindow.shared?.isVisible ?? false
        // always safe to poll: update() only uses silent check APIs; they never trigger a system prompt
        ScreenRecordingPermission.update()
        InputMonitoringPermission.update()
        Logger.debug { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status) inputMonitoring:\(InputMonitoringPermission.status)" }
        if !preStartupPermissionsPassed {
            checkPermissionsPreStartup()
        } else {
            checkPermissionsPostStartup()
            if isPermissionsWindowVisible && !timerIsFrequent {
                setFrequentTimer()
            } else if !isPermissionsWindowVisible && timerIsFrequent {
                setInfrequentTimer()
            }
        }
        DispatchQueue.main.async {
            Menubar.togglePermissionCallout(permissionCalloutMessage())
            if PermissionsWindow.shared != nil {
                PermissionsWindow.updatePermissionViews()
            }
        }
    }

    /// only Accessibility is required: without it we cannot list or focus windows at all. Screen Recording
    /// (thumbnails) and Input Monitoring (focus on shortcut release) each degrade one feature, so they are
    /// opt-in and never block the app from starting
    /// neither optional permission blocks the app, but a missing one has to be visible rather than silent:
    /// Input Monitoring first, as without it the switcher never focuses on release. Thumbnails are only
    /// worth mentioning to someone whose switcher draws them - the grouped view is icons and titles
    private static func permissionCalloutMessage() -> String? {
        if InputMonitoringPermission.status != .granted {
            return NSLocalizedString("Ztabby is running without Input Monitoring permission. It can’t see when you release the shortcut, so the switcher stays open.", comment: "Menubar callout")
        }
        if ScreenRecordingPermission.status != .granted && !Appearance.hideThumbnails && !Preferences.windowGroupingEnabled {
            return NSLocalizedString("Ztabby is running without Screen Recording permission. Thumbnails won’t show.", comment: "Menubar callout")
        }
        return nil
    }

    private static func checkPermissionsPreStartup() {
        if AccessibilityPermission.status != .notGranted {
            DispatchQueue.main.async {
                preStartupPermissionsPassed = true
                PermissionsWindow.shared?.close()
                setInfrequentTimer()
                App.continueAppLaunchAfterPermissionsAreGranted()
            }
        } else {
            DispatchQueue.main.async {
                App.showPermissionsWindow()
            }
        }
    }

    private static func checkPermissionsPostStartup() {
        guard AccessibilityPermission.status == .notGranted else { return }
        guard consumeRestartBudget() else {
            // give up on restarting rather than loop: see SystemPermissionsTestable
            Logger.error { "Accessibility permission lost, but the restart budget is spent; showing the permissions window instead" }
            DispatchQueue.main.async { App.showPermissionsWindow() }
            return
        }
        Logger.error { "Accessibility permission revoked while Ztabby was running; restarting" }
        DispatchQueue.main.async { App.restart() }
    }

    /// Restart attempts are tracked in UserDefaults because each restart is a new process; an in-memory
    /// counter would reset every time and never trip. The sliding window refills the budget on its own,
    /// so nothing needs to clear this once permissions are healthy again — and deliberately so: clearing
    /// it on a successful launch would reset the count on every loop iteration and defeat the limit.
    private static func consumeRestartBudget(now: Double = Date().timeIntervalSince1970) -> Bool {
        let key = "permissionRestartAttempts"
        let stored = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        guard SystemPermissionsTestable.restartIsAllowed(attempts: stored, now: now) else {
            UserDefaults.standard.set(SystemPermissionsTestable.recentRestarts(stored, now: now), forKey: key)
            return false
        }
        UserDefaults.standard.set(SystemPermissionsTestable.recordingRestart(stored, now: now), forKey: key)
        return true
    }

    static func setInfrequentTimer() {
        timerIsFrequent = false
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
    }

    static func setFrequentTimer() {
        timerIsFrequent = true
        timer.schedule(deadline: .now(), repeating: 0.5, leeway: .milliseconds(500))
    }

    private static func setImmediateTimer() {
        timerIsFrequent = false
        timer.schedule(deadline: .now(), repeating: .never, leeway: .never)
    }
}

class AccessibilityPermission {
    static var status = PermissionStatus.notGranted

    @discardableResult
    static func update() -> PermissionStatus {
        status = detect()
        return status
    }

    private static func detect() -> PermissionStatus {
        // no DEBUG bypass: the debug build has its own bundle id and must check its own TCC grants,
        // otherwise it acts on permissions it doesn't have (e.g. spamming Screen Recording prompts)
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
    }
}

class ScreenRecordingPermission {
    static var status = PermissionStatus.notGranted
    private static var hasRequestedOnce = false

    @discardableResult
    static func update() -> PermissionStatus {
        status = detect()
        return status
    }

    /// status check only: CGPreflightScreenCaptureAccess is silent and never queues a system prompt.
    /// no DEBUG bypass: the debug build has its own bundle id and must check its own TCC grants
    private static func detect() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        }
        return .granted
    }

    /// the only place allowed to queue a system Screen Recording prompt.
    /// fires at most once per launch, and only while the permissions window is frontmost.
    /// if the user denies, we never re-request; the permissions window and menubar callout are the hint
    static func requestOnce() {
        if #available(macOS 10.15, *) {
            guard !hasRequestedOnce, update() == .notGranted else { return }
            hasRequestedOnce = true
            Logger.info { "requesting Screen Recording permission (once per launch)" }
            CGRequestScreenCaptureAccess()
        }
    }
}

/// Keyboard event taps are how we learn that the shortcut's modifier was released. macOS starves the tap
/// when this permission is missing - it is created, reports itself disabled, and delivers almost nothing -
/// so the switcher opens but never focuses on release, with no error anywhere. Hence we check it and say so
class InputMonitoringPermission {
    static var status = PermissionStatus.notGranted
    private static var hasRequestedOnce = false

    @discardableResult
    static func update() -> PermissionStatus {
        status = detect()
        return status
    }

    private static func detect() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ? .granted : .notGranted
        }
        return .granted
    }

    /// the only place allowed to queue a system Input Monitoring prompt; at most once per launch, like
    /// Screen Recording, and only while the permissions window is frontmost
    static func requestOnce() {
        if #available(macOS 10.15, *) {
            guard !hasRequestedOnce, update() == .notGranted else { return }
            hasRequestedOnce = true
            Logger.info { "requesting Input Monitoring permission (once per launch)" }
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }
}
