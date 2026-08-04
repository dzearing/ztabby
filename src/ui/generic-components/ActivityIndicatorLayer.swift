import Cocoa

/// A window's activity state, as published by the app in `kAXWindowActivityStateAttribute`.
/// nil for idle, and for apps that publish nothing.
enum ActivityIndicator: String {
    case busy
    case needsInput = "needs_input"

    static func make(_ activityState: String?) -> ActivityIndicator? {
        guard let activityState else { return nil }
        return ActivityIndicator(rawValue: activityState)
    }

    var color: NSColor { self == .busy ? .systemGreen : .systemYellow }

    /// Busy sweeps a dashed border to read as "in progress"; needing input holds a solid one.
    var sweepsBorder: Bool { self == .busy }

    /// Needing input pulses faster, so the two states stay tellable apart at a glance.
    var pulseDuration: CFTimeInterval { self == .busy ? 1.0 : 0.4 }
}

/// Pulsing tint and sweeping border drawn over a window's app icon while that window reports
/// activity: green while busy, orange while it waits on the user. Animations are wall-clock-synced
/// so they don't restart when the switcher rebuilds its rows.
class ActivityIndicatorLayer: CALayer {
    private static let sweepKey = "activitySweep"
    private static let pulseKey = "activityPulse"
    private let overlayLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var indicator: ActivityIndicator?

    override init() {
        super.init()
        setupOverlay()
        setupBorder()
        isHidden = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupOverlay() {
        overlayLayer.opacity = 0.1
        overlayLayer.strokeColor = nil
        addSublayer(overlayLayer)
    }

    private func setupBorder() {
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.0
        borderLayer.lineCap = .round
        borderLayer.lineJoin = .round
        borderLayer.shadowRadius = 2
        borderLayer.shadowOpacity = 0.3
        borderLayer.shadowOffset = .zero
        addSublayer(borderLayer)
    }

    func update(_ newIndicator: ActivityIndicator?, size: CGFloat) {
        guard newIndicator != indicator || bounds.width != size else { return }
        indicator = newIndicator
        isHidden = newIndicator == nil
        overlayLayer.removeAllAnimations()
        borderLayer.removeAllAnimations()
        guard let newIndicator else { return }
        applyColor(newIndicator.color)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layoutOverlay(size: size)
        let perimeter = layoutBorder(size: size, sweeping: newIndicator.sweepsBorder)
        addOverlayPulse(newIndicator.pulseDuration)
        guard newIndicator.sweepsBorder else { return }
        addSweepAnimation(perimeter: perimeter)
    }

    private func applyColor(_ color: NSColor) {
        overlayLayer.fillColor = color.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.shadowColor = color.cgColor
    }

    private func layoutOverlay(size: CGFloat) {
        let gap: CGFloat = 2
        let iconRect = CGRect(x: gap, y: gap, width: size - gap * 2, height: size - gap * 2)
        let cornerRadius = iconRect.width * 0.2
        overlayLayer.path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        overlayLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
    }

    private func layoutBorder(size: CGFloat, sweeping: Bool) -> CGFloat {
        let inset = borderLayer.lineWidth / 2
        let cornerRadius = size * 0.2
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
        borderLayer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        borderLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let perimeter = 2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
        borderLayer.lineDashPhase = 0
        borderLayer.lineDashPattern = sweeping ? [NSNumber(value: Double(perimeter * 0.35)), NSNumber(value: Double(perimeter * 0.65))] : nil
        return perimeter
    }

    private func addOverlayPulse(_ duration: CFTimeInterval) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.1
        pulse.toValue = 0.5
        pulse.duration = duration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        pulse.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: duration * 2)
        overlayLayer.add(pulse, forKey: Self.pulseKey)
    }

    private func addSweepAnimation(perimeter: CGFloat) {
        let sweep = CABasicAnimation(keyPath: "lineDashPhase")
        sweep.fromValue = 0
        sweep.toValue = Double(perimeter)
        sweep.duration = 2.0
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        sweep.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: 2.0)
        borderLayer.add(sweep, forKey: Self.sweepKey)
    }
}
