import UIKit

final class BetSheetViewController: UIViewController {
    private let marketID: Int
    private var outcome: Outcome
    private let sheetTransition = SheetTransitioningDelegate()
    private let balance = 250
    private var amount = 0

    // MARK: Views

    /// A "skirt" below the sheet so the spring overshoot / rubber band never reveals a gap.
    private lazy var skirt: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.sheet
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var grabber: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        view.layer.cornerRadius = 2.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(15, .semibold)
        label.textColor = Theme.textSecondary
        label.numberOfLines = 2
        label.textAlignment = .center
        return label
    }()

    private lazy var outcomeToggle: PillSegmentedControl = {
        let control = PillSegmentedControl(items: ["Yes", "No"], font: Theme.font(16, .bold))
        control.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        control.layer.cornerRadius = 24
        control.layer.cornerCurve = .continuous
        control.indicatorColors = [Theme.yes, Theme.no]
        control.select(outcome == .yes ? 0 : 1, animated: false)
        control.addTarget(self, action: #selector(outcomeChanged), for: .valueChanged)
        return control
    }()

    private lazy var amountLabel: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(56, .heavy)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Centers the amount inside the full-width stack.
    private lazy var amountContainer: UIView = {
        let view = UIView()
        view.addSubview(amountLabel)
        return view
    }()

    private lazy var balanceLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(14, .medium)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        return label
    }()

    private lazy var chips: UIStackView = {
        let buttons = [("+$1", 1), ("+$5", 5), ("+$20", 20), ("+$100", 100), ("Max", -1)].map { title, value in
            let chip = ChipButton(title: title)
            chip.tag = value
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            return chip
        }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }()

    private lazy var toWinTitle: UILabel = {
        let label = UILabel()
        label.text = "To win 💸"
        label.font = Theme.font(16, .semibold)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var toWinLabel: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(22, .bold)
        view.textColor = Theme.yes
        return view
    }()

    private lazy var toWinRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [toWinTitle, UIView(), toWinLabel])
        stack.alignment = .center
        return stack
    }()

    private lazy var confirmButton: HoldToConfirmButton = {
        let button = HoldToConfirmButton()
        button.addTarget(self, action: #selector(confirmed), for: .primaryActionTriggered)
        return button
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, outcomeToggle, amountContainer, balanceLabel, chips, toWinRow, confirmButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(4, after: amountContainer)
        stack.setCustomSpacing(24, after: toWinRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    }()

    // MARK: Lifecycle

    static func present(from presenter: UIViewController, marketID: Int, outcome: Outcome) {
        presenter.present(BetSheetViewController(marketID: marketID, outcome: outcome), animated: true)
    }

    init(marketID: Int, outcome: Outcome) {
        self.marketID = marketID
        self.outcome = outcome
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = sheetTransition // transitioningDelegate is weak; we own it
    }

    required init?(coder: NSCoder) { fatalError() }

    private var market: Market? { MarketSimulator.shared.market(id: marketID) }
    private var sheetPC: SheetPresentationController? { presentationController as? SheetPresentationController }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        refresh(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(marketDidUpdate(_:)), name: .marketDidUpdate, object: nil)
    }

    private func setupViews() {
        view.backgroundColor = Theme.sheet
        view.layer.cornerRadius = 28
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.addGestureRecognizer(panGesture)

        view.addSubview(skirt)
        view.addSubview(grabber)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            skirt.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -1),
            skirt.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skirt.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skirt.heightAnchor.constraint(equalToConstant: 400),

            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            amountLabel.centerXAnchor.constraint(equalTo: amountContainer.centerXAnchor),
            amountLabel.topAnchor.constraint(equalTo: amountContainer.topAnchor),
            amountLabel.bottomAnchor.constraint(equalTo: amountContainer.bottomAnchor),

            outcomeToggle.heightAnchor.constraint(equalToConstant: 48),

            contentStack.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: State

    private func refresh(animated: Bool) {
        guard let m = market else { return }
        titleLabel.text = "\(m.emoji)  \(m.title)"
        outcomeToggle.setTitle("Yes \(Format.cents(m.probability))", at: 0)
        outcomeToggle.setTitle("No \(Format.cents(1 - m.probability))", at: 1)
        amountLabel.setText(Format.dollars(Double(amount)), animated: animated)
        let price = max(m.price(for: outcome), 0.01)
        toWinLabel.setText(Format.dollars(Double(amount) / price, cents: true), animated: animated)
        balanceLabel.text = "Balance \(Format.dollars(Double(balance - amount)))"
        confirmButton.color = outcome == .yes ? Theme.yes : Theme.no
        confirmButton.title = amount == 0 ? "Add an amount" : "Hold to buy \(outcome.title)"
        confirmButton.isEnabled = amount > 0
        confirmButton.alpha = amount > 0 ? 1 : 0.5
    }

    @objc private func marketDidUpdate(_ note: Notification) {
        guard note.userInfo?["id"] as? Int == marketID, !confirmButton.isCompleted else { return }
        refresh(animated: true)
    }

    @objc private func outcomeChanged() {
        outcome = outcomeToggle.selectedIndex == 0 ? .yes : .no
        UIView.animate(withDuration: 0.25) { self.refresh(animated: true) }
    }

    @objc private func chipTapped(_ chip: ChipButton) {
        let add = chip.tag == -1 ? balance - amount : chip.tag
        guard add > 0, amount + add <= balance else { return rejectAmount() }
        amount += add
        refresh(animated: true)
        // "Pop": jump the model to a bigger scale instantly, then spring back to identity.
        amountLabel.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(springDuration: 0.4, bounce: 0.5) { self.amountLabel.transform = .identity }
    }

    private func rejectAmount() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -12, 10, -8, 6, -3, 0]
        shake.duration = 0.4
        shake.isAdditive = true // composes with any transform already applied
        amountLabel.layer.add(shake, forKey: "shake")
        UIView.transition(with: balanceLabel, duration: 0.15, options: .transitionCrossDissolve) {
            self.balanceLabel.textColor = Theme.no
        } completion: { _ in
            UIView.transition(with: self.balanceLabel, duration: 0.6, options: .transitionCrossDissolve) {
                self.balanceLabel.textColor = Theme.textSecondary
            }
        }
    }

    @objc private func confirmed() {
        if let window = view.window {
            Confetti.burst(in: window, at: confirmButton.convert(CGPoint(x: confirmButton.bounds.midX, y: 0), to: window))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.dismiss(animated: true) }
    }

    // MARK: Interactive dismissal

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let container = view.superview else { return }
        let ty = g.translation(in: container).y
        let offset = ty >= 0 ? ty : -Gesture.rubberBand(-ty, limit: 50)
        switch g.state {
        case .began, .changed:
            view.transform = CGAffineTransform(translationX: 0, y: offset)
            sheetPC?.setDimming(1 - max(0, offset) / view.bounds.height)
        case .ended, .cancelled:
            let velocity = g.velocity(in: container).y
            if offset + Gesture.project(velocity) > view.bounds.height * 0.4 {
                sheetTransition.dismissVelocity = velocity
                dismiss(animated: true)
            } else {
                // Spring back, carrying the finger's velocity (relative to remaining distance).
                let relative = abs(offset) > 1 ? max(-30, min(30, velocity / -offset)) : 0
                UIView.animate(springDuration: 0.5, bounce: 0.2, initialSpringVelocity: relative, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.view.transform = .identity
                    self.sheetPC?.setDimming(1)
                }
            }
        default: break
        }
    }
}
