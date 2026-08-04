import Cocoa

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
        // always safe to poll: update() only uses the silent preflight API; it never triggers a system prompt
        ScreenRecordingPermission.update()
        Logger.debug { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status)" }
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
            Menubar.togglePermissionCallout(ScreenRecordingPermission.status != .granted)
            if PermissionsWindow.shared != nil {
                PermissionsWindow.updatePermissionViews()
            }
        }
    }

    private static func checkPermissionsPreStartup() {
        if AccessibilityPermission.status != .notGranted && ScreenRecordingPermission.status != .notGranted {
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
        if AccessibilityPermission.status == .notGranted {
            Logger.error { "Accessibility permission revoked while Ztabby was running; restarting" }
            DispatchQueue.main.async { App.restart() }
        }
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
            return CGPreflightScreenCaptureAccess() ? .granted :
                (Preferences.screenRecordingPermissionSkipped ? .skipped : .notGranted)
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
