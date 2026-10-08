import UIKit

/// What the slip is buying.
struct BetSlipContext {
    let matchup: String
    let outcome: String
    let chance: Double
    let color: UIColor
    let badge: String
    var badgeColor: UIColor = .white

    static func game(_ game: Game, team: Team) -> BetSlipContext {
        BetSlipContext(matchup: "\(game.home.name) vs \(game.away.name)", outcome: team.name, chance: game.chance(for: team),
                       color: team.color, badge: team.monogram,
                       badgeColor: team.color.isLight ? team.color : team.color.withLightness(min: 0.62))
    }

    static func upDown(_ market: UpDownMarket, outcome: Outcome) -> BetSlipContext {
        BetSlipContext(matchup: market.title, outcome: outcome == .yes ? "Up" : "Down",
                       chance: outcome == .yes ? market.upChance : 1 - market.upChance,
                       color: outcome == .yes ? Theme.yes : Theme.no, badge: "₿", badgeColor: Theme.bitcoin)
    }
}

/// Full-screen bet slip modeled on the real app: keypad entry, big rolling amount, team-colored
/// "Swipe to buy" footer. Pull the panel down to dismiss; swipe the footer up to buy.
final class BetSlipViewController: UIViewController, UIGestureRecognizerDelegate {
    private let context: BetSlipContext
    private let sheetTransition = FullSheetTransitioningDelegate()
    private var input = ""
    private var isArmed = false
    private let buyThreshold: CGFloat = 120
    private let balance: Double = 250

    private var amount: Double { Double(input) ?? 0 }
    private var footerColor: UIColor { context.color.isLight ? UIColor(hex: 0x3A4150) : context.color }

    // MARK: Panel

    private lazy var panel: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.background
        view.layer.cornerRadius = 38
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addGestureRecognizer(dismissPan)
        return view
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        button.tintColor = .white
        button.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var marketButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Market"
        config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.baseForegroundColor = Theme.textSecondary
        let button = UIButton(configuration: config)
        button.menu = UIMenu(children: [
            UIAction(title: "Market", state: .on) { _ in },
            UIAction(title: "Limit") { _ in },
        ])
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var badgeTile: UILabel = {
        let label = UILabel()
        label.text = context.badge
        label.font = .systemFont(ofSize: context.badge.count > 2 ? 13 : 20, weight: .heavy)
        label.textColor = context.badgeColor
        label.textAlignment = .center
        label.backgroundColor = Theme.card
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var matchupLabel: UILabel = {
        let label = UILabel()
        label.text = context.matchup
        label.font = Theme.font(15)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var outcomeLabel: UILabel = {
        let label = UILabel()
        label.text = context.outcome
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private lazy var headerText: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [matchupLabel, outcomeLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var amountLabel: RollingNumberView = {
        let view = RollingNumberView()
        view.font = .monospacedDigitSystemFont(ofSize: 68, weight: .bold)
        view.textColor = UIColor.white.withAlphaComponent(0.16)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var toWinPrefix: UILabel = {
        let label = UILabel()
        label.text = "to win"
        label.font = Theme.font(22)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var toWinValue: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(22, .regular)
        view.textColor = Theme.yes
        view.stagger = 0.015
        return view
    }()

    private lazy var toWinInfo: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "info.circle.fill"))
        imageView.tintColor = Theme.textSecondary
        imageView.preferredSymbolConfiguration = .init(pointSize: 13)
        return imageView
    }()

    private lazy var toWinRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [toWinPrefix, toWinValue, toWinInfo])
        stack.spacing = 6
        stack.alignment = .center
        stack.alpha = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var availableLabel: UILabel = {
        let label = UILabel()
        label.text = "\(Format.dollars(balance)) available   |   Odds \(Format.percent(context.chance))"
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var quickRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [5, 10, 25].map { value in
            let key = KeyButton(title: "+$\(value)")
            key.addAction(UIAction { [weak self] _ in self?.quickAdd(Double(value)) }, for: .touchUpInside)
            return key
        })
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var keypad: UIStackView = {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]].map { keys -> UIStackView in
            let row = UIStackView(arrangedSubviews: keys.map { key in
                let button = key == "⌫" ? KeyButton(symbol: "delete.left.fill") : KeyButton(title: key)
                button.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchUpInside)
                return button
            })
            row.distribution = .fillEqually
            return row
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: Footer

    private lazy var footer: UIView = {
        let view = UIView()
        view.backgroundColor = footerColor
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addGestureRecognizer(buyPan)
        return view
    }()

    /// The visible strip of footer below the panel; footer labels center in it.
    private lazy var footerArea: UILayoutGuide = UILayoutGuide()

    private lazy var chooseLabel: UILabel = {
        let label = UILabel()
        label.text = "Choose an amount"
        label.font = Theme.font(16, .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var chevron: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.up"))
        imageView.tintColor = .white
        imageView.preferredSymbolConfiguration = .init(pointSize: 13, weight: .bold)
        return imageView
    }()

    private lazy var swipeLabel: UILabel = {
        let label = UILabel()
        let text = NSMutableAttributedString(string: "Swipe", attributes: [.font: Theme.font(17, .bold)])
        text.append(NSAttributedString(string: " to buy \(context.outcome)", attributes: [.font: Theme.font(17, .semibold)]))
        label.attributedText = text
        label.textColor = .white
        return label
    }()

    private lazy var finePrint: UILabel = {
        let label = UILabel()
        label.text = "Final cost may vary"
        label.font = Theme.font(12)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        return label
    }()

    private lazy var swipeStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [chevron, swipeLabel, finePrint])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.alpha = 0
        stack.isUserInteractionEnabled = false // sits above the footer; let the footer's pan get the touch
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var successStack: UIStackView = {
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = .white
        check.preferredSymbolConfiguration = .init(pointSize: 64, weight: .bold)
        let title = UILabel()
        title.text = "Bought \(context.outcome)"
        title.font = Theme.font(26, .bold)
        title.textColor = .white
        let detail = UILabel()
        detail.tag = 1
        detail.font = Theme.font(16, .medium)
        detail.textColor = UIColor.white.withAlphaComponent(0.85)
        let stack = UIStackView(arrangedSubviews: [check, title, detail])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.alpha = 0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: Gestures & feedback

    private lazy var buyPan: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handleBuyPan(_:)))
    }()

    private lazy var dismissPan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        gesture.delegate = self
        return gesture
    }()

    private lazy var armHaptic: UIImpactFeedbackGenerator = {
        UIImpactFeedbackGenerator(style: .medium)
    }()

    private var sheetPC: FullSheetPresentationController? { presentationController as? FullSheetPresentationController }

    // MARK: Lifecycle

    init(context: BetSlipContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = sheetTransition
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        render(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // In the recording the team color only appears once the slip has landed.
        swipeStack.transform = CGAffineTransform(translationX: 0, y: 10)
        chooseLabel.transform = CGAffineTransform(translationX: 0, y: 10)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.footer.alpha = 1
            self.chooseLabel.transform = .identity
            self.swipeStack.transform = .identity
        }
    }

    private func setupViews() {
        view.backgroundColor = Theme.background
        view.layer.cornerRadius = 38
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true

        view.addSubview(footer)
        view.addLayoutGuide(footerArea)
        [chooseLabel, swipeStack, successStack].forEach(view.addSubview)
        view.addSubview(panel)
        [closeButton, marketButton, badgeTile, headerText, amountLabel, toWinRow, availableLabel, quickRow, keypad].forEach(panel.addSubview)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: view.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -66),

            footerArea.topAnchor.constraint(equalTo: panel.bottomAnchor),
            footerArea.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            chooseLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chooseLabel.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor),
            swipeStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            swipeStack.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor),
            successStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            successStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            marketButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            marketButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),

            badgeTile.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 10),
            badgeTile.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            badgeTile.widthAnchor.constraint(equalToConstant: 44),
            badgeTile.heightAnchor.constraint(equalToConstant: 44),
            headerText.centerYAnchor.constraint(equalTo: badgeTile.centerYAnchor),
            headerText.leadingAnchor.constraint(equalTo: badgeTile.trailingAnchor, constant: 12),

            amountLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            amountLabel.topAnchor.constraint(equalTo: badgeTile.bottomAnchor, constant: 76),
            toWinRow.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            toWinRow.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 2),

            keypad.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            keypad.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            keypad.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20),
            keypad.heightAnchor.constraint(equalToConstant: 240),
            quickRow.leadingAnchor.constraint(equalTo: keypad.leadingAnchor),
            quickRow.trailingAnchor.constraint(equalTo: keypad.trailingAnchor),
            quickRow.bottomAnchor.constraint(equalTo: keypad.topAnchor, constant: -4),
            quickRow.heightAnchor.constraint(equalToConstant: 56),
            availableLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            availableLabel.bottomAnchor.constraint(equalTo: quickRow.topAnchor, constant: -24),
        ])
    }

    // MARK: Input

    private func press(_ key: String) {
        var next = input
        switch key {
        case "⌫":
            guard !next.isEmpty else { return reject() }
            next.removeLast()
        case ".":
            guard !next.contains(".") else { return reject() }
            next += next.isEmpty ? "0." : "."
        default:
            next = next == "0" ? key : next + key
        }
        let parts = next.split(separator: ".", omittingEmptySubsequences: false)
        guard parts[0].count <= 5, parts.count < 2 || parts[1].count <= 2 else { return reject() }
        guard (Double(next) ?? 0) <= balance else { return reject() } // can't spend more than you have
        input = next
        render(animated: true)
    }

    private func quickAdd(_ value: Double) {
        let total = amount + value
        guard total <= balance else { return reject() }
        input = total.rounded() == total ? String(Int(total)) : String(format: "%.2f", total)
        render(animated: true)
    }

    private func reject() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -14, 11, -8, 5, -2, 0]
        shake.duration = 0.4
        shake.isAdditive = true
        amountLabel.layer.add(shake, forKey: "shake")
    }

    private var displayAmount: String {
        guard !input.isEmpty else { return "$0" }
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts[0]) ?? 0
        let grouped = NumberFormatter.localizedString(from: NSNumber(value: whole), number: .decimal)
        return "$" + grouped + (parts.count > 1 ? "." + parts[1] : "")
    }

    private func render(animated: Bool) {
        let hasAmount = amount > 0
        amountLabel.setText(displayAmount, animated: animated)
        amountLabel.textColor = hasAmount ? .white : UIColor.white.withAlphaComponent(0.16)
        toWinValue.setText(Format.dollars(amount / max(context.chance, 0.01), cents: true), animated: animated && hasAmount)

        guard animated else { return }
        // Pop: jump the scale up instantly, spring back to identity.
        amountLabel.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        UIView.animate(springDuration: 0.45, bounce: 0.45) { self.amountLabel.transform = .identity }

        let showSwipe = hasAmount
        guard (swipeStack.alpha > 0.5) != showSwipe else { return }
        UIView.animate(springDuration: 0.4, bounce: 0.1) {
            self.toWinRow.alpha = showSwipe ? 1 : 0
            self.toWinRow.transform = showSwipe ? .identity : CGAffineTransform(translationX: 0, y: -6)
            self.swipeStack.alpha = showSwipe ? 1 : 0
            self.swipeStack.transform = showSwipe ? .identity : CGAffineTransform(translationX: 0, y: 12)
            self.chooseLabel.alpha = showSwipe ? 0 : 1
            self.chooseLabel.transform = showSwipe ? CGAffineTransform(translationX: 0, y: -12) : .identity
        }
    }

    // MARK: Swipe to buy

    @objc private func handleBuyPan(_ g: UIPanGestureRecognizer) {
        guard amount > 0 else { return }
        let travel = max(0, -g.translation(in: view).y)
        let offset = travel < buyThreshold ? travel : buyThreshold + Gesture.rubberBand(travel - buyThreshold, limit: 60)
        switch g.state {
        case .began:
            armHaptic.prepare()
        case .changed:
            panel.transform = CGAffineTransform(translationX: 0, y: -offset)
            swipeStack.transform = CGAffineTransform(translationX: 0, y: -offset * 0.45)
            // Tactile "detent" when crossing the commit point (and when backing off it).
            let armed = travel >= buyThreshold
            if armed != isArmed {
                isArmed = armed
                armHaptic.impactOccurred(intensity: armed ? 1 : 0.5)
            }
        case .ended, .cancelled:
            let velocity = g.velocity(in: view).y
            if travel + Gesture.project(-velocity) > buyThreshold, g.state == .ended {
                commitPurchase(velocity: velocity)
            } else {
                isArmed = false
                let relative = offset > 1 ? max(-30, min(30, -velocity / offset)) : 0
                UIView.animate(springDuration: 0.5, bounce: 0.3, initialSpringVelocity: relative, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.panel.transform = .identity
                    self.swipeStack.transform = .identity
                }
            }
        default: break
        }
    }

    private func commitPurchase(velocity: CGFloat) {
        buyPan.isEnabled = false
        dismissPan.isEnabled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        (successStack.arrangedSubviews.last as? UILabel)?.text =
            "\(Format.dollars(amount, cents: true))  ·  to win \(Format.dollars(amount / max(context.chance, 0.01), cents: true))"

        // Carry the finger's speed into the fly-away (relative velocity = pt/s ÷ distance).
        let current = -panel.transform.ty
        let distance = view.bounds.height - current
        let relative = distance > 1 ? min(40, max(0, -velocity / distance)) : 0
        let fly = UIViewPropertyAnimator(duration: 0.5, timingParameters: UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: 0, dy: relative)))
        fly.addAnimations {
            self.panel.transform = CGAffineTransform(translationX: 0, y: -self.view.bounds.height)
            self.swipeStack.alpha = 0
        }
        fly.startAnimation()

        successStack.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(springDuration: 0.55, bounce: 0.45, initialSpringVelocity: 0, delay: 0.15, options: []) {
            self.successStack.alpha = 1
            self.successStack.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Confetti.burst(in: self.view, at: CGPoint(x: self.view.bounds.midX, y: self.view.bounds.maxY - 40))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.dismiss(animated: true) }
    }

    // MARK: Pull to dismiss

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        let v = dismissPan.velocity(in: view)
        return v.y > abs(v.x) // only clearly-downward drags
    }

    @objc private func handleDismissPan(_ g: UIPanGestureRecognizer) {
        let ty = max(0, g.translation(in: view).y)
        switch g.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: ty)
            sheetPC?.setPresentedFraction(1 - ty / view.bounds.height)
        case .ended, .cancelled:
            let velocity = g.velocity(in: view).y
            if ty + Gesture.project(velocity) > view.bounds.height * 0.3 {
                sheetTransition.dismissVelocity = velocity
                dismiss(animated: true)
            } else {
                let relative = ty > 1 ? max(-30, min(30, velocity / -ty)) : 0
                UIView.animate(springDuration: 0.5, bounce: 0.15, initialSpringVelocity: relative, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.view.transform = .identity
                    self.sheetPC?.setPresentedFraction(1)
                }
            }
        default: break
        }
    }
}

/// Keypad / quick-add key: a soft circular highlight blooms behind the glyph on touch.
final class KeyButton: UIControl {
    private let title: String?
    private let symbol: String?

    private lazy var bloom: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var glyph: UIView = {
        if let symbol {
            let imageView = UIImageView(image: UIImage(systemName: symbol))
            imageView.tintColor = Theme.textSecondary
            imageView.preferredSymbolConfiguration = .init(pointSize: 20, weight: .medium)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }
        let label = UILabel()
        label.text = title
        label.font = Theme.font(title?.hasPrefix("+") == true ? 20 : 26, .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var haptic: UIImpactFeedbackGenerator = {
        UIImpactFeedbackGenerator(style: .soft)
    }()

    init(title: String) {
        self.title = title
        self.symbol = nil
        super.init(frame: .zero)
        setupViews()
    }

    init(symbol: String) {
        self.title = nil
        self.symbol = symbol
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(bloom)
        addSubview(glyph)
        NSLayoutConstraint.activate([
            bloom.centerXAnchor.constraint(equalTo: centerXAnchor),
            bloom.centerYAnchor.constraint(equalTo: centerYAnchor),
            bloom.widthAnchor.constraint(equalToConstant: 64),
            bloom.heightAnchor.constraint(equalToConstant: 52),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        bloom.layer.cornerRadius = 16
        bloom.layer.cornerCurve = .continuous
        addTarget(self, action: #selector(touchDown), for: .touchDown)
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            let down = isHighlighted
            // Instant in, gentle out — the key should feel like it responded before your finger lifted.
            UIView.animate(withDuration: down ? 0.06 : 0.35, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.bloom.alpha = down ? 1 : 0
                self.bloom.transform = down ? CGAffineTransform(scaleX: 1.05, y: 1.05) : CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.glyph.transform = down ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    @objc private func touchDown() { haptic.impactOccurred(intensity: 0.6) }
}

// MARK: - Full-screen sheet transition

/// Like the bottom sheet, but full height, and the presenter recedes (scales + rounds) behind it.
final class FullSheetTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    var dismissVelocity: CGFloat = 0

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        FullSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SheetAnimator(presenting: true, velocity: 0)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        defer { dismissVelocity = 0 }
        return SheetAnimator(presenting: false, velocity: dismissVelocity)
    }
}

final class FullSheetPresentationController: UIPresentationController {
    private let recededScale: CGFloat = 0.92

    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.alpha = 0
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    private var presenterView: UIView { presentingViewController.view }

    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimmingView.frame = container.bounds
        container.insertSubview(dimmingView, at: 0)
        presenterView.layer.cornerCurve = .continuous
        presenterView.clipsToBounds = true
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.setPresentedFraction(1)
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.setPresentedFraction(0)
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        guard completed else { return }
        presenterView.transform = .identity
        presenterView.layer.cornerRadius = 0
        presenterView.clipsToBounds = false
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let v = presentedView else { return }
        let f = frameOfPresentedViewInContainerView
        v.bounds = CGRect(origin: .zero, size: f.size)
        v.center = CGPoint(x: f.midX, y: f.midY)
    }

    /// 1 = slip fully up (presenter receded), 0 = slip gone (presenter restored). Drives the interactive pull.
    func setPresentedFraction(_ fraction: CGFloat) {
        let f = max(0, min(1, fraction))
        let scale = 1 - (1 - recededScale) * f
        presenterView.transform = CGAffineTransform(scaleX: scale, y: scale)
        presenterView.layer.cornerRadius = 38 * f
        dimmingView.alpha = f
    }
}
