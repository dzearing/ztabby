import Cocoa
import Carbon.HIToolbox

@available(macOS 26.0, *)
class Launcher {
    static var shared: Launcher?

    private let discovery = LauncherAppDiscovery()
    private let frecency = LauncherFrecency()
    private var viewModel: LauncherViewModel!
    private var window: LauncherWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var pressedHandler: EventHandlerRef?
    private var sizeObservation: Any?

    func start() {
        viewModel = LauncherViewModel(discovery: discovery, frecency: frecency)
        discovery.scan { [weak self] in self?.viewModel.updateResults() }
        BackgroundWork.screenshotsQueue.addOperation { [weak self] in
            self?.discovery.loadAllIcons()
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.updateResults()
            }
        }
        registerHotKey()
        frecency.prune()
        let registered = hotKeyRef != nil
        Logger.info { "Launcher started; ⌥Space hotkey registered:\(registered)" }
    }

    func toggle() {
        guard let window, window.isVisible else {
            show()
            return
        }
        hide()
    }

    func show() {
        guard !App.appIsBeingUsed else { return }
        if window == nil {
            window = LauncherWindow(
                viewModel: viewModel,
                onDismiss: { [weak self] in self?.hide() },
                onLaunch: { [weak self] in self?.launchAndHide() }
            )
            observeSize()
        }
        viewModel.reset()
        window?.showCentered()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func launchAndHide() {
        viewModel.launchSelected()
        hide()
    }

    private func observeSize() {
        sizeObservation = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.window?.updateSize()
        }
    }

    private static let hotkeySignature: UInt32 = "zlch".utf16.reduce(0) { ($0 << 8) + UInt32($1) }
    private static let hotkeyId: UInt32 = 1

    private func registerHotKey() {
        let id = EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyId)
        let target = GetEventDispatcherTarget()
        var eventTypes = [EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        InstallEventHandler(target, { (_, event, userData) -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var eventId = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &eventId)
            guard status == noErr, eventId.signature == Launcher.hotkeySignature, eventId.id == Launcher.hotkeyId else {
                return OSStatus(eventNotHandledErr)
            }
            let launcher = Unmanaged<Launcher>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { launcher.toggle() }
            return noErr
        }, eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &pressedHandler)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            id,
            target,
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = pressedHandler { RemoveEventHandler(handler) }
        if let timer = sizeObservation as? Timer { timer.invalidate() }
    }
}
