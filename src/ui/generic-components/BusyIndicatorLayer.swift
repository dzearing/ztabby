import Cocoa

class BusyIndicatorLayer: CALayer {
    private static let sweepKey = "busySweep"
    private static let pulseKey = "busyPulse"
    private let overlayLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

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
        overlayLayer.fillColor = NSColor.systemGreen.cgColor
        overlayLayer.opacity = 0.1
        overlayLayer.strokeColor = nil
        addSublayer(overlayLayer)
    }

    private func setupBorder() {
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.systemGreen.cgColor
        borderLayer.lineWidth = 1.0
        borderLayer.lineCap = .round
        borderLayer.lineJoin = .round
        borderLayer.shadowColor = NSColor.systemGreen.cgColor
        borderLayer.shadowRadius = 2
        borderLayer.shadowOpacity = 0.3
        borderLayer.shadowOffset = .zero
        addSublayer(borderLayer)
    }

    func update(busy: Bool, size: CGFloat) {
        guard busy != !isHidden else { return }
        isHidden = !busy
        guard busy else {
            overlayLayer.removeAllAnimations()
            borderLayer.removeAllAnimations()
            return
        }
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layoutOverlay(size: size)
        let perimeter = layoutBorder(size: size)
        addOverlayPulse()
        addSweepAnimation(perimeter: perimeter)
    }

    private func layoutOverlay(size: CGFloat) {
        let gap: CGFloat = 2
        let iconRect = CGRect(x: gap, y: gap, width: size - gap * 2, height: size - gap * 2)
        let cornerRadius = iconRect.width * 0.2
        overlayLayer.path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        overlayLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
    }

    private func layoutBorder(size: CGFloat) -> CGFloat {
        let inset = borderLayer.lineWidth / 2
        let cornerRadius = size * 0.2
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
        borderLayer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        borderLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let perimeter = 2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
        borderLayer.lineDashPattern = [NSNumber(value: Double(perimeter * 0.35)), NSNumber(value: Double(perimeter * 0.65))]
        return perimeter
    }

    private func addOverlayPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.1
        pulse.toValue = 0.5
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        pulse.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: 2.0)
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
