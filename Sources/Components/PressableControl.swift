import UIKit

/// Base class for anything that should "squish" on touch-down and spring back on release.
/// Down: fast, no bounce (feels immediate). Up: slower with bounce (feels alive).
class PressableControl: UIControl {
    var pressedScale: CGFloat = 0.96
    var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle? = .light
    private lazy var impact = UIImpactFeedbackGenerator(style: hapticStyle ?? .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    override var isHighlighted: Bool {
        didSet { if oldValue != isHighlighted { animatePress(isHighlighted) } }
    }

    private func animatePress(_ down: Bool) {
        UIView.animate(springDuration: down ? 0.18 : 0.5, bounce: down ? 0 : 0.45, initialSpringVelocity: 0, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = down ? CGAffineTransform(scaleX: self.pressedScale, y: self.pressedScale) : .identity
        }
    }

    @objc private func touchDown() { if hapticStyle != nil { impact.prepare() } }
    @objc private func tapped() { if hapticStyle != nil { impact.impactOccurred() } }
}

/// The green "Yes" / red "No" buttons, with a rolling price.
final class OutcomeButton: PressableControl {
    let outcome: Outcome
    private let compact: Bool

    private var outcomeColor: UIColor { outcome == .yes ? Theme.yes : Theme.no }
    private var contentColor: UIColor { compact ? outcomeColor : .white }

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = compact ? outcome.title : "Buy \(outcome.title)"
        label.font = Theme.font(compact ? 15 : 17, .semibold)
        label.textColor = contentColor
        return label
    }()

    private lazy var price: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(compact ? 15 : 17, .semibold)
        view.textColor = contentColor.withAlphaComponent(compact ? 1 : 0.85)
        view.isHidden = compact
        return view
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, price])
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(outcome: Outcome, compact: Bool) {
        self.outcome = outcome
        self.compact = compact
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = compact ? outcomeColor.withAlphaComponent(0.16) : outcomeColor
        layer.cornerRadius = compact ? 10 : 14
        layer.cornerCurve = .continuous
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: compact ? 40 : 54),
        ])
    }

    func setPrice(_ p: Double, animated: Bool) {
        price.setText(Format.cents(p), animated: animated)
    }
}

/// Small pill used for "+$10" quick-add chips.
final class ChipButton: PressableControl {
    private let title: String

    lazy var label: UILabel = {
        let label = UILabel()
        label.text = title
        label.font = Theme.font(15, .semibold)
        label.textColor = Theme.textPrimary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        pressedScale = 0.92
        backgroundColor = UIColor.white.withAlphaComponent(0.08)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 40),
        ])
    }
}
