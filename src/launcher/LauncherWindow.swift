import Cocoa
import SwiftUI

@available(macOS 26.0, *)
class LauncherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private var onDismissCallback: (() -> Void)?
    private let cornerRadius: CGFloat = 20
    private let width: CGFloat = 680
    private var showTime: Date = .distantPast
    private var isAdjustingFrame = false
    private var userCenterOffset: CGSize?
    // Pinned top edge: the field stays put here while results grow/shrink downward.
    private var contentTopY: CGFloat?
    private static let offsetXKey = "LauncherWindow.centerOffsetX"
    private static let offsetYKey = "LauncherWindow.centerOffsetY"

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
        setAccessibilityLabel("App Launcher")
        setAccessibilitySubrole(.unknown)
        loadUserOffset()
    }

    func showCentered() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let center = targetCenter(on: screen)
        let height: CGFloat = 80
        contentTopY = nil
        setFrameInternally(NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), display: false)
        showTime = Date()
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.updateSize() }
    }

    func updateSize() {
        guard let hostingView = contentView, isVisible else { return }
        let size = hostingView.fittingSize
        guard size.height > 0 else { return }
        // First layout centers this height around the open center, then pins the top so
        // the field stays put and later result changes only grow/shrink the bottom.
        let top = contentTopY ?? (frame.midY + size.height / 2)
        contentTopY = top
        let rect = NSRect(x: frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        guard rect != frame else { return }
        setFrameInternally(rect, display: true)
    }

    // Center point the window opens at: screen center, plus any persisted user drag offset.
    private func targetCenter(on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let offset = userCenterOffset ?? .zero
        return CGPoint(x: visible.midX + offset.width, y: visible.midY + offset.height)
    }

    // Frame changes we make ourselves must not be mistaken for user drags.
    private func setFrameInternally(_ rect: NSRect, display: Bool) {
        isAdjustingFrame = true
        setFrame(rect, display: display)
        isAdjustingFrame = false
    }

    private func loadUserOffset() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.offsetXKey) != nil else { return }
        userCenterOffset = CGSize(width: defaults.double(forKey: Self.offsetXKey), height: defaults.double(forKey: Self.offsetYKey))
    }

    private func persistUserOffset(_ offset: CGSize) {
        userCenterOffset = offset
        UserDefaults.standard.set(offset.width, forKey: Self.offsetXKey)
        UserDefaults.standard.set(offset.height, forKey: Self.offsetYKey)
    }
}

@available(macOS 26.0, *)
extension LauncherWindow: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard Date().timeIntervalSince(showTime) > 0.5 else { return }
        onDismissCallback?()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        contentTopY = frame.maxY
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        persistUserOffset(CGSize(width: frame.midX - visible.midX, height: frame.midY - visible.midY))
    }
}
