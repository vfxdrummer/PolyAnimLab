import UIKit

final class MarketDetailViewController: UIViewController {
    private let marketID: Int
    private let sim = MarketSimulator.shared
    private let ranges = ["1H", "6H", "1D", "1W", "ALL"]
    private let windowSizes = [30, 60, 120, 240, 400]
    private var isScrubbing = false
    private var didAnimateIn = false

    // MARK: Header

    private lazy var avatar: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .center
        label.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        return label
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(20, .bold)
        label.textColor = Theme.textPrimary
        label.numberOfLines = 0
        return label
    }()

    private lazy var header: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatar, titleLabel])
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }()

    // MARK: Price

    private lazy var bigNumber: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(40, .bold)
        view.textColor = Theme.accent
        return view
    }()

    private lazy var chanceLabel: UILabel = {
        let label = UILabel()
        label.text = "chance"
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.accent
        return label
    }()

    private lazy var numberRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [bigNumber, chanceLabel, UIView()])
        stack.spacing = 6
        stack.alignment = .lastBaseline
        return stack
    }()

    private lazy var changeLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(14, .semibold)
        return label
    }()

    // MARK: Chart

    private lazy var chart: LiveChartView = {
        let chart = LiveChartView()
        chart.onScrub = { [weak self] value in self?.scrubbed(to: value) }
        return chart
    }()

    private lazy var rangeControl: PillSegmentedControl = {
        let control = PillSegmentedControl(items: ranges)
        control.selectedTextColor = .white
        control.select(2, animated: false)
        control.addTarget(self, action: #selector(rangeChanged), for: .valueChanged)
        return control
    }()

    private lazy var volumeLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(14, .medium)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.text = "Long-press and drag on the chart to scrub. Prices tick live; tap Buy to open the bet slip."
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        label.numberOfLines = 0
        return label
    }()

    // MARK: Containers

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [header, numberRow, changeLabel, chart, rangeControl, volumeLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(2, after: numberRow)
        stack.setCustomSpacing(20, after: rangeControl)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    // MARK: Bottom bar

    private lazy var yesButton: OutcomeButton = {
        let button = OutcomeButton(outcome: .yes, compact: false)
        button.addTarget(self, action: #selector(buyYes), for: .touchUpInside)
        return button
    }()

    private lazy var noButton: OutcomeButton = {
        let button = OutcomeButton(outcome: .no, compact: false)
        button.addTarget(self, action: #selector(buyNo), for: .touchUpInside)
        return button
    }()

    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [yesButton, noButton])
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var hairline: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.border
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bottomBar: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: Lifecycle

    init(marketID: Int) {
        self.marketID = marketID
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        update(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(marketDidUpdate(_:)), name: .marketDidUpdate, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        chart.animateDrawIn()
    }

    private func setupViews() {
        view.backgroundColor = Theme.background
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(bottomBar)
        bottomBar.addSubview(hairline)
        bottomBar.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 52),
            avatar.heightAnchor.constraint(equalToConstant: 52),
            chart.heightAnchor.constraint(equalToConstant: 240),
            rangeControl.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hairline.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            buttonStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    // MARK: State

    private var market: Market? { sim.market(id: marketID) }
    private var window: Int { windowSizes[rangeControl.selectedIndex] }

    private func series(_ m: Market) -> [Double] { Array(m.history.suffix(window)) }

    private func update(animated: Bool) {
        guard let m = market else { return }
        avatar.text = m.emoji
        titleLabel.text = m.title
        let s = series(m)
        chart.setValues(s, animated: animated)
        if !isScrubbing {
            bigNumber.setText(Format.percent(m.probability), animated: animated)
            setChange(from: s.first ?? m.probability, to: m.probability, animated: animated)
        }
        yesButton.setPrice(m.probability, animated: animated)
        noButton.setPrice(1 - m.probability, animated: animated)
        volumeLabel.text = "\(Format.volume(m.volume)) Vol."
    }

    private func setChange(from: Double, to: Double, animated: Bool) {
        let delta = Int(((to - from) * 100).rounded())
        let up = delta >= 0
        let text = "\(up ? "▲" : "▼") \(abs(delta))%  \(ranges[rangeControl.selectedIndex])"
        let color = up ? Theme.yes : Theme.no
        guard changeLabel.text != text else { return }
        if animated {
            UIView.transition(with: changeLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.changeLabel.text = text
                self.changeLabel.textColor = color
            }
        } else {
            changeLabel.text = text
            changeLabel.textColor = color
        }
    }

    private func scrubbed(to value: Double?) {
        isScrubbing = value != nil
        scrollView.isScrollEnabled = !isScrubbing
        guard let m = market else { return }
        if let value {
            bigNumber.setText(Format.percent(value), animated: true)
            setChange(from: series(m).first ?? value, to: value, animated: true)
        } else {
            update(animated: true)
        }
    }

    @objc private func marketDidUpdate(_ note: Notification) {
        guard note.userInfo?["id"] as? Int == marketID else { return }
        update(animated: true)
    }

    @objc private func rangeChanged() { update(animated: true) }
    @objc private func buyYes() { BetSheetViewController.present(from: self, marketID: marketID, outcome: .yes) }
    @objc private func buyNo() { BetSheetViewController.present(from: self, marketID: marketID, outcome: .no) }
}
