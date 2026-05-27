import Cocoa
import SwiftUI

@available(macOS 26.0, *)
class LauncherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private var onDismissCallback: (() -> Void)?
    private let cornerRadius: CGFloat = 20
    private var showTime: Date = .distantPast
    private var hasBeenDragged = false

    convenience init(viewModel: LauncherViewModel, onDismiss: @escaping () -> Void, onLaunch: @escaping () -> Void) {
        self.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        onDismissCallback = onDismiss
        delegate = self
        isFloatingPanel = true
        level = .floating
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        let launcherView = LauncherView(viewModel: viewModel, onDismiss: onDismiss, onLaunch: onLaunch)
        let hostingView = NSHostingView(rootView: launcherView)
        contentView = hostingView
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = cornerRadius
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.backgroundColor = .clear
        setFrameAutosaveName("LauncherWindow")
        setAccessibilityLabel("App Launcher")
        setAccessibilitySubrole(.unknown)
    }

    func showCentered() {
        let width: CGFloat = 680
        hasBeenDragged = setFrameUsingName(frameAutosaveName)
        if !hasBeenDragged {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let visible = screen.visibleFrame
            let x = visible.midX - width / 2
            let y = visible.midY + visible.height * 0.12
            setFrame(NSRect(x: x, y: y, width: width, height: 80), display: false)
        }
        showTime = Date()
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.updateSize() }
    }

    func updateSize() {
        guard let hostingView = contentView, isVisible else { return }
        let size = hostingView.fittingSize
        guard size.height > 0 else { return }
        let topY = frame.maxY
        let centerX = frame.midX
        let x = centerX - size.width / 2
        setFrame(NSRect(x: x, y: topY - size.height, width: size.width, height: size.height), display: true)
    }
}

@available(macOS 26.0, *)
extension LauncherWindow: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard Date().timeIntervalSince(showTime) > 0.5 else { return }
        onDismissCallback?()
    }

    func windowDidMove(_ notification: Notification) {
        hasBeenDragged = true
        saveFrame(usingName: frameAutosaveName)
    }
}
