import UIKit

/// Polymarket-style home: header, category icon row, horizontally paged categories,
/// floating "Build a Combo" pill. The bell holds the lab menu (Playground, Perf Lab, v1 demo, HUD).
final class HomeViewController: UIViewController, UIScrollViewDelegate {
    private let categories: [CategoryBar.Item] = [
        .init(title: "Home", symbol: "safari.fill", colors: [.white, Theme.accent]),
        .init(title: "MLB", symbol: "baseball.fill", colors: [UIColor(hex: 0xE8E8E8)]),
        .init(title: "NFL", symbol: "football.fill", colors: [UIColor(hex: 0xC4552A)]),
        .init(title: "Crypto", symbol: "bitcoinsign.circle.fill", colors: [.white, Theme.bitcoin]),
        .init(title: "Hockey", symbol: "hockey.puck.fill", colors: [UIColor(hex: 0xD0D4DA)]),
        .init(title: "Tennis", symbol: "tennisball.fill", colors: [UIColor(hex: 0xA6D23A)]),
        .init(title: "Politics", symbol: "building.columns.fill", colors: [UIColor(hex: 0xB0B6C0)]),
    ]

    private var currentPage = 0

    private var logoAspect: CGFloat {
        guard let size = logo.image?.size, size.height > 0 else { return 5.8 }
        return size.width / size.height
    }

    // MARK: Header

    private lazy var logo: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "LaunchLogo"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var depositButton: PressableControl = {
        let button = PressableControl()
        button.backgroundColor = Theme.accent
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = "Deposit"
        label.font = Theme.font(15, .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Bell doubles as the lab menu so the Playground / Perf Lab stay one tap away.
    private lazy var bellButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "bell", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        config.baseBackgroundColor = Theme.raised
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.menu = labMenu
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var labMenu: UIMenu = {
        UIMenu(title: "PolyAnim Lab", children: [
            UIAction(title: "Animation Playground", image: UIImage(systemName: "wand.and.stars")) { [weak self] _ in
                self?.navigationController?.pushViewController(PlaygroundViewController(), animated: true)
            },
            UIAction(title: "Perf Lab", image: UIImage(systemName: "speedometer")) { [weak self] _ in
                self?.navigationController?.pushViewController(PerformanceLabViewController(), animated: true)
            },
            UIAction(title: "v1 Market Demo", image: UIImage(systemName: "chart.line.uptrend.xyaxis")) { [weak self] _ in
                self?.navigationController?.pushViewController(MarketFeedViewController(), animated: true)
            },
            UIAction(title: "Toggle Hitch HUD", image: UIImage(systemName: "gauge.with.dots.needle.67percent")) { [weak self] _ in
                guard let scene = self?.view.window?.windowScene else { return }
                HitchHUD.shared.toggle(in: scene)
            },
        ])
    }()

    private lazy var categoryBar: CategoryBar = {
        let bar = CategoryBar(items: categories)
        bar.onSelect = { [weak self] index in self?.scrollToPage(index) }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    // MARK: Pages

    private lazy var pages: [HomePage] = {
        let pages: [HomePage] = [
            HomeFeedPage(),
            LeaguePage(league: "MLB",
                       hero: HeroBanner(league: "MLB", phase: "Postseason", progressText: "Division Series", progress: 0.3,
                                        art: UIImage(systemName: "baseball.fill")?.withTintColor(UIColor(hex: 0xC9CED6), renderingMode: .alwaysOriginal)),
                       chips: ["Games 4", "Futures 28", "World Series 4", "Postseason 12"],
                       combos: [
                           ComboCard(title: "Clinching Quartet", legs: [("White Sox To win", "54%"), ("Dodgers To win", "57%"), ("Rays To win", "40%"), ("Brewers To win", "50%")], payout: "$146.20"),
                           ComboCard(title: "Home Sweet Home", legs: [("White Sox To win", "54%"), ("Braves To win", "43%"), ("Yankees To win", "60%"), ("Padres To win", "51%")], payout: "$139.75"),
                       ]),
            LeaguePage(league: "NFL",
                       hero: HeroBanner(league: "NFL", phase: "Regular season", progressText: "Week 5 of 18", progress: 5.0 / 18,
                                        art: HelmetSprites.leftProfile),
                       chips: ["Games 29", "Week 5 15", "Week 6 14", "Weekly Leaders 8"]),
            CryptoPage(),
            PlaceholderPage(title: "Hockey", symbol: "hockey.puck.fill"),
            PlaceholderPage(title: "Tennis", symbol: "tennisball.fill"),
            PlaceholderPage(title: "Politics", symbol: "building.columns.fill"),
        ]
        pages.forEach { page in page.onBet = { [weak self] context in self?.presentBetSlip(context) } }
        return pages
    }()

    private lazy var pager: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        // Nested scroll views that BOTH delay content touches swallow quick taps (e.g. a mouse click
        // in the Simulator) on controls inside the inner one. Let only the inner page scroll view delay;
        // the pager can still cancel a control's tracking once a horizontal swipe begins.
        scrollView.delaysContentTouches = false
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var pagesStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: pages)
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var comboButton: BuildComboButton = {
        let button = BuildComboButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func setupViews() {
        view.backgroundColor = Theme.background
        [pager, logo, depositButton, bellButton, categoryBar, comboButton].forEach(view.addSubview)
        pager.addSubview(pagesStack)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            logo.centerYAnchor.constraint(equalTo: bellButton.centerYAnchor),
            logo.heightAnchor.constraint(equalToConstant: 22),
            logo.widthAnchor.constraint(equalTo: logo.heightAnchor, multiplier: logoAspect),

            bellButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            bellButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bellButton.widthAnchor.constraint(equalToConstant: 40),
            bellButton.heightAnchor.constraint(equalToConstant: 40),
            depositButton.trailingAnchor.constraint(equalTo: bellButton.leadingAnchor, constant: -10),
            depositButton.centerYAnchor.constraint(equalTo: bellButton.centerYAnchor),

            categoryBar.topAnchor.constraint(equalTo: bellButton.bottomAnchor, constant: 8),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            pager.topAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: 6),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pagesStack.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: pager.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor),
            pagesStack.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor),
            pagesStack.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor, multiplier: CGFloat(pages.count)),

            comboButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            comboButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14),
        ])
        pages.forEach { $0.scrollView.contentInset.bottom = 96 }
    }

    // MARK: Paging

    private func scrollToPage(_ index: Int) {
        // Adjacent pages: animate the pager (the category highlight follows the scroll).
        // Far jumps: cross-fade instead of flinging past five pages.
        let target = CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0)
        if abs(index - currentPage) <= 1 {
            pager.setContentOffset(target, animated: true)
        } else {
            UIView.transition(with: pager, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.pager.contentOffset = target
            }
            pageSettled()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pager, pager.bounds.width > 0 else { return }
        categoryBar.setPagePosition(pager.contentOffset.x / pager.bounds.width)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { pageSettled() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { pageSettled() }

    private func pageSettled() {
        let index = Int((pager.contentOffset.x / max(1, pager.bounds.width)).rounded())
        guard index != currentPage else { return }
        currentPage = index
        pages[index].pageDidAppear()
    }

    // MARK: Betting

    private func presentBetSlip(_ context: BetSlipContext) {
        present(BetSlipViewController(context: context), animated: true)
    }
}

/// Simple stand-in for the Squads / Live / Portfolio / Search tabs.
final class TabPlaceholderViewController: UIViewController {
    private let symbol: String

    private lazy var label: UILabel = {
        let label = UILabel()
        let attachment = NSTextAttachment(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 44))!
            .withTintColor(Theme.textSecondary))
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "\n\n\(title ?? "")"))
        label.attributedText = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = Theme.font(17, .medium)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String, symbol: String) {
        self.symbol = symbol
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        view.backgroundColor = Theme.background
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
