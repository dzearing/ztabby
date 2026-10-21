import Cocoa
import ShortcutRecorder

/// Focus-on-release depends on learning that the shortcut's modifiers came up, and macOS does not tell us
/// reliably: the keyboard event tap is starved while Input Monitoring is denied, and events can be dropped
/// or arrive out of order even when it is granted. A release we never hear about leaves the switcher open
/// over the user's screen, so while it is open we confirm the modifier state ourselves instead of trusting
/// delivery. The timer lives only as long as the open UI, it arms only for a summon that actually held the
/// modifiers, and it wants two agreeing reads so that one racy read cannot focus while the key is still down
class HoldKeyWatcher {
    private static let interval = 0.05
    private static let agreeingReadsBeforeFiring = 2
    private static var timer: DispatchSourceTimer?
    private static var sawModifiersHeld = false
    private static var releasedReads = 0

    static func start() {
        guard timer == nil else { return }
        releasedReads = 0
        sawModifiersHeld = activeHoldShortcut().map(isHeld) ?? false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(10))
        timer.setEventHandler(handler: focusIfModifiersWereReleased)
        timer.resume()
        self.timer = timer
    }

    static func stop() {
        timer?.cancel()
        timer = nil
        sawModifiersHeld = false
        releasedReads = 0
    }

    private static func focusIfModifiersWereReleased() {
        guard let holdShortcut = activeHoldShortcut() else { stop(); return }
        if isHeld(holdShortcut) {
            sawModifiersHeld = true
            releasedReads = 0
            return
        }
        guard sawModifiersHeld else { return } // summoned without holding them (gesture, menubar, cli)
        releasedReads += 1
        guard releasedReads >= agreeingReadsBeforeFiring else { return }
        Logger.info { "\(holdShortcut.id) was released without an event reaching us; focusing the selection" }
        holdShortcut.state = .up
        ControlsTab.executeAction(holdShortcut.id)
    }

    private static func activeHoldShortcut() -> ATShortcut? {
        guard App.appIsBeingUsed, !App.forceDoNothingOnRelease, Preferences.shortcutStyle == .focusOnRelease else { return nil }
        return ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.shortcutIndex)]
    }

    private static func isHeld(_ holdShortcut: ATShortcut) -> Bool {
        let modifiers = cocoaToCarbonFlags(ModifierFlags.current).cleaned()
        let holdModifiers = holdShortcut.shortcut.carbonModifierFlags.cleaned()
        guard holdModifiers != 0 else { return true } // nothing to release; never fire on its behalf
        return modifiers == (modifiers | holdModifiers)
    }
}
