import Cocoa
import SwiftUI

@available(macOS 26.0, *)
class LauncherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(viewModel: LauncherViewModel, onDismiss: @escaping () -> Void, onLaunch: @escaping () -> Void) {
        self.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        let launcherView = LauncherView(viewModel: viewModel, onDismiss: onDismiss, onLaunch: onLaunch)
        let hostingView = NSHostingView(rootView: launcherView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostingView
        setAccessibilityLabel("App Launcher")
        setAccessibilitySubrole(.unknown)
    }

    func showCentered() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let contentSize = contentView?.fittingSize ?? NSSize(width: 680, height: 80)
        let x = screen.frame.midX - contentSize.width / 2
        let y = screen.frame.midY + screen.frame.height * 0.1
        setFrame(NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height), display: true)
        makeKeyAndOrderFront(nil)
    }

    func updateSize() {
        guard let hostingView = contentView, isVisible else { return }
        let size = hostingView.fittingSize
        guard let screen = screen ?? NSScreen.main else { return }
        let x = screen.frame.midX - size.width / 2
        let currentTop = frame.maxY
        setFrame(NSRect(x: x, y: currentTop - size.height, width: size.width, height: size.height), display: true)
    }
}
