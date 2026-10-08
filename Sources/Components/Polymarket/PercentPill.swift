import UIKit

/// The chunky team-colored "57%" button from the real app: a face sitting on a darker base,
/// like a physical key. Pressing pushes the face down onto the base; releasing springs it back.
///
/// Only the face's `transform` animates — no layout, no shadow — so it's cheap even in long lists.
final class PercentPill: UIControl {
    var color: UIColor { didSet { applyColor() } }

    private let depth: CGFloat = 4

    private lazy var base: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 11
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var face: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 11
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var label: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(15, .medium)
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var haptic: UIImpactFeedbackGenerator = {
        UIImpactFeedbackGenerator(style: .rigid)
    }()

    init(color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(base)
        addSubview(face)
        face.addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 42),
            base.topAnchor.constraint(equalTo: topAnchor, constant: depth),
            base.leadingAnchor.constraint(equalTo: leadingAnchor),
            base.trailingAnchor.constraint(equalTo: trailingAnchor),
            base.bottomAnchor.constraint(equalTo: bottomAnchor),
            face.topAnchor.constraint(equalTo: topAnchor),
            face.leadingAnchor.constraint(equalTo: leadingAnchor),
            face.trailingAnchor.constraint(equalTo: trailingAnchor),
            face.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -depth),
            label.centerXAnchor.constraint(equalTo: face.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: face.centerYAnchor),
        ])
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyColor()
    }

    private func applyColor() {
        face.backgroundColor = color
        base.backgroundColor = color.isLight ? UIColor(white: 0.62, alpha: 1) : color.darker(0.62)
        label.textColor = color.isLight ? UIColor(hex: 0x0E1015) : .white
    }

    func setChance(_ chance: Double, animated: Bool) {
        label.setText(Format.percent(chance), animated: animated)
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            let down = isHighlighted
            UIView.animate(springDuration: down ? 0.12 : 0.4, bounce: down ? 0 : 0.5, initialSpringVelocity: 0, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.face.transform = down ? CGAffineTransform(translationX: 0, y: self.depth - 1) : .identity
            }
        }
    }

    @objc private func touchDown() { haptic.prepare() }
    @objc private func tapped() { haptic.impactOccurred(intensity: 0.8) }
}
