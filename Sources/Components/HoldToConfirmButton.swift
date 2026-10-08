import UIKit

/// "Hold to buy" — the canonical UIViewPropertyAnimator demo.
/// Press: a linear fill runs over `holdDuration`. Release early: the SAME animator is reversed
/// from wherever it is (interruptible + reversible), with a faster spring timing.
/// Re-press mid-reverse: it flips direction again. No state is ever "jumped".
final class HoldToConfirmButton: UIControl {
    var holdDuration: TimeInterval = 0.9
    var title = "" { didSet { label.text = title } }
    var color: UIColor = Theme.yes { didSet { applyColor() } }
    private(set) var isCompleted = false

    private var animator: UIViewPropertyAnimator?
    private let emptyTransform = CGAffineTransform(scaleX: 0.001, y: 1) // 0 would be non-invertible

    private lazy var fill: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.anchorPoint = CGPoint(x: 0, y: 0.5) // grow from the leading edge
        view.transform = emptyTransform
        return view
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = Theme.font(17, .bold)
        label.textColor = .white
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var check: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        imageView.tintColor = .white
        imageView.preferredSymbolConfiguration = .init(pointSize: 26, weight: .bold)
        imageView.alpha = 0
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var impact: UIImpactFeedbackGenerator = {
        UIImpactFeedbackGenerator(style: .medium)
    }()

    private lazy var notify: UINotificationFeedbackGenerator = {
        UINotificationFeedbackGenerator()
    }()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true

        addSubview(fill)
        addSubview(label)
        addSubview(check)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.centerXAnchor.constraint(equalTo: centerXAnchor),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 58),
        ])
        applyColor()
    }

    private func applyColor() {
        backgroundColor = color.withAlphaComponent(0.35)
        fill.backgroundColor = color
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Never set `frame` on a view with a non-identity transform — set bounds + center instead.
        fill.bounds = bounds
        fill.center = CGPoint(x: 0, y: bounds.midY)
    }

    // MARK: Touch tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard !isCompleted, isEnabled else { return false }
        impact.impactOccurred(intensity: 0.6)
        notify.prepare()
        if let animator {
            // Caught mid-reverse: flip back to forward, linear again.
            animator.pauseAnimation()
            animator.isReversed = false
            animator.continueAnimation(withTimingParameters: UICubicTimingParameters(animationCurve: .linear), durationFactor: 1)
        } else {
            let a = UIViewPropertyAnimator(duration: holdDuration, curve: .linear) { self.fill.transform = .identity }
            a.addCompletion { [weak self] position in self?.animatorFinished(at: position) }
            a.startAnimation()
            animator = a
        }
        UIView.animate(springDuration: 0.25, bounce: 0) { self.label.transform = CGAffineTransform(scaleX: 0.95, y: 0.95) }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { release() }
    override func cancelTracking(with event: UIEvent?) { release() }

    private func release() {
        UIView.animate(springDuration: 0.4, bounce: 0.4) { self.label.transform = .identity }
        guard let animator, !isCompleted, animator.state == .active else { return }
        animator.pauseAnimation()
        animator.isReversed = true
        animator.continueAnimation(withTimingParameters: UISpringTimingParameters(dampingRatio: 1), durationFactor: 0.45)
    }

    private func animatorFinished(at position: UIViewAnimatingPosition) {
        animator = nil
        if position == .end { complete() }
    }

    private func complete() {
        isCompleted = true
        notify.notificationOccurred(.success)
        UIView.animate(springDuration: 0.3, bounce: 0) {
            self.label.alpha = 0
            self.label.transform = CGAffineTransform(translationX: 0, y: -14)
        }
        check.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(springDuration: 0.5, bounce: 0.5, initialSpringVelocity: 0, delay: 0.05, options: []) {
            self.check.alpha = 1
            self.check.transform = .identity
        }
        sendActions(for: .primaryActionTriggered)
    }

    func reset() {
        animator?.stopAnimation(true)
        animator = nil
        isCompleted = false
        fill.transform = emptyTransform
        label.alpha = 1
        label.transform = .identity
        check.alpha = 0
    }
}
