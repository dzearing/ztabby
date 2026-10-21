import Cocoa

class PermissionsWindow: NSWindow {
    static var accessibilityView: PermissionView!
    static var screenRecordingView: PermissionView!
    static var inputMonitoringView: PermissionView!
    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }
    static var shared: PermissionsWindow!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
        setFrameAutosaveName("PermissionsWindow")
        Self.shared = self
    }

    static func updatePermissionViews() {
        accessibilityView.updatePermissionStatus(AccessibilityPermission.status)
        if #available(macOS 10.15, *) {
            screenRecordingView.updatePermissionStatus(ScreenRecordingPermission.status)
            inputMonitoringView.updatePermissionStatus(InputMonitoringPermission.status)
        }
    }

    static func show() {
        guard !Self.shared.isVisible else { return }
        Logger.debug { "" }
        Self.shared.center()
        App.shared.activate(ignoringOtherApps: true)
        Self.shared.makeKeyAndOrderFront(nil)
        SystemPermissions.setFrequentTimer()
        // the permission UI is frontmost: the one moment we may queue real system prompts
        ScreenRecordingPermission.requestOnce()
        InputMonitoringPermission.requestOnce()
    }

    private func setupWindow() {
        title = NSLocalizedString("Ztabby needs some permissions", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.closable])
    }

    private func setupView() {
        let appIcon = LightImageView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.updateContents(.cgImage(App.appIcon), NSSize(width: 80, height: 80))
        appIcon.fit(80, 80)
        let appText = TitleLabel(NSLocalizedString("Ztabby needs some permissions", comment: ""))
        appText.preferredMaxLayoutWidth = 380
        appText.font = .systemFont(ofSize: 25, weight: .regular)
        let header = NSStackView(views: [appIcon, appText])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.spacing = GridView.interPadding
        Self.accessibilityView = PermissionView(
            "accessibility",
            NSLocalizedString("Accessibility", comment: ""),
            NSLocalizedString("Required. Without it, windows can't be listed or focused", comment: ""),
            NSLocalizedString("Open Accessibility Settings…", comment: ""),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        )
        var rows = [
            [header],
            [Self.accessibilityView],
        ]
        if #available(macOS 10.15, *) {
            Self.screenRecordingView = PermissionView(
                "screen-recording",
                NSLocalizedString("Screen Recording", comment: ""),
                NSLocalizedString("Optional. Grant it to show thumbnails and a preview of open windows", comment: ""),
                NSLocalizedString("Open Screen Recording Settings…", comment: ""),
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
            Self.inputMonitoringView = PermissionView(
                "accessibility",
                NSLocalizedString("Input Monitoring", comment: ""),
                NSLocalizedString("Optional. Without it, macOS hides modifier keys from us, so the switcher stays open instead of focusing when you release the shortcut", comment: ""),
                NSLocalizedString("Open Input Monitoring Settings…", comment: ""),
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
            rows.append([Self.screenRecordingView])
            rows.append([Self.inputMonitoringView])
        }
        let widestRowWidth = rows.reduce(0) { max($0, $1[0]!.fittingSize.width) }
        rows.forEach { $0[0]!.fit(widestRowWidth, $0[0]!.fittingSize.height) }
        let view = GridView(rows as! [[NSView]])
        view.fit()
        setContentSize(view.fittingSize)
        contentView = view
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension PermissionsWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Logger.debug { "preStartupPermissionsPassed:\(SystemPermissions.preStartupPermissionsPassed), accessibility:\(AccessibilityPermission.status), screenRecording:\(ScreenRecordingPermission.status), inputMonitoring:\(InputMonitoringPermission.status)" }
        if !SystemPermissions.preStartupPermissionsPassed {
            if AccessibilityPermission.status == .notGranted {
                Logger.error {
                    """
                    Before using this app, you need to give permission in System Settings > Privacy & Security > Accessibility.
                    Please authorize and re-launch.
                    See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx
                    """
                }
                App.shared.terminate(self)
                return false // prevent the close; termination will close everything once
            }
        }
        return true
    }
}
