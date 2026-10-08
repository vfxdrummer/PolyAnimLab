import UIKit

/// Semicircle "62% chance" gauge from the market cards.
/// Uses a CAShapeLayer + strokeEnd, animated with an explicit CASpringAnimation that starts
/// from the *presentation* value so rapid updates don't jump.
final class ChanceGaugeView: UIView {
    private(set) var value: Double = 0

    private lazy var track: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 5
        layer.lineCap = .round
        layer.strokeColor = UIColor.white.withAlphaComponent(0.1).cgColor
        return layer
    }()

    private lazy var progress: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 5
        layer.lineCap = .round
        layer.strokeEnd = 0
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        layer.addSublayer(track)
        layer.addSublayer(progress)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no implicit animation for geometry
        let radius = min(bounds.width / 2, bounds.height) - track.lineWidth / 2
        let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.maxY - 1), radius: radius,
                                startAngle: .pi, endAngle: 2 * .pi, clockwise: true).cgPath
        for l in [track, progress] { l.frame = bounds; l.path = path }
        CATransaction.commit()
    }

    static func color(for value: Double) -> UIColor {
        UIColor(hue: 0.0 + 0.36 * value, saturation: 0.72, brightness: 0.88, alpha: 1)
    }

    func setValue(_ newValue: Double, animated: Bool) {
        value = newValue
        let from = progress.presentation()?.strokeEnd ?? progress.strokeEnd

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = CGFloat(newValue) // model value = final value
        if !animated { progress.strokeColor = Self.color(for: newValue).cgColor }
        CATransaction.commit()

        guard animated else { return }
        // Standalone (non view-backing) layers animate implicitly — this color change gets a free 0.25s fade.
        progress.strokeColor = Self.color(for: newValue).cgColor

        let spring = CASpringAnimation(perceptualDuration: 0.6, bounce: 0.15)
        spring.keyPath = "strokeEnd"
        spring.fromValue = from
        spring.toValue = CGFloat(newValue)
        spring.duration = spring.settlingDuration
        progress.add(spring, forKey: "strokeEnd")
    }
}
