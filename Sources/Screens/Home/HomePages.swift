import UIKit

/// Shared shell for every pager page: a vertical scroll view with a content stack and
/// bottom padding so the floating "Build a Combo" pill never covers the last row.
class HomePage: UIView {
    var onBet: ((BetSlipContext) -> Void)?

    lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInset.bottom = 96
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }

    /// Called when the page settles on screen (e.g. to kick off entrance animations).
    func pageDidAppear() {}

    /// Wraps a view with the standard 20pt side inset.
    func inset(_ view: UIView, top: CGFloat = 0, bottom: CGFloat = 0, sides: CGFloat = 20) -> UIView {
        let container = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sides),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -sides),
        ])
        return container
    }

    /// Horizontally scrolling row of fixed-width views (Popular tiles, Combo cards…).
    func carousel(_ views: [UIView], spacing: CGFloat = 10) -> UIView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        let stack = UIStackView(arrangedSubviews: views)
        stack.spacing = spacing
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        return scrollView
    }

    func gameCard(_ game: Game) -> GameCardView {
        let card = GameCardView(game: game)
        card.onPick = { [weak self] game, team in self?.onBet?(.game(game, team: team)) }
        return card
    }
}

// MARK: - Home

final class HomeFeedPage: HomePage {
    private lazy var upDownCard: UpDownCard = {
        let card = UpDownCard()
        card.onPick = { [weak self] outcome in self?.onBet?(.upDown(SportsSimulator.shared.btc15m, outcome: outcome)) }
        return card
    }()

    private lazy var popularRow: UIView = {
        let tiles = SportsSimulator.shared.games(league: "MLB").map { PopularTile(game: $0) }
        let row = carousel(tiles)
        row.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return row
    }()

    private lazy var promo: PromoBanner = {
        PromoBanner()
    }()

    private lazy var liveMatch: LiveMatchCard = {
        let card = LiveMatchCard()
        card.onPick = { [weak self] player in
            self?.onBet?(BetSlipContext(matchup: "McDonald vs Nijboer", outcome: player, chance: 0.38,
                                        color: UIColor(hex: 0xC41050), badge: "🎾"))
        }
        return card
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let games = SportsSimulator.shared.games(league: "MLB")
        [
            inset(upDownCard, top: 4, bottom: 28),
            inset(Section.header("Popular"), bottom: 12),
            popularRow,
            inset(Section.header("New on Polymarket"), top: 28, bottom: 12),
            inset(promo),
            inset(Section.header("Live"), top: 28, bottom: 8),
            liveMatch,
            separator,
            gameCard(games[0]),
            gameCard(games[1]),
        ].forEach(contentStack.addArrangedSubview)
    }
}

// MARK: - League (MLB / NFL)

final class LeaguePage: HomePage {
    private let league: String
    private let hero: HeroBanner
    private let chips: [String]
    private let combos: [ComboCard]

    private lazy var chipRow: UIView = {
        let row = carousel(chips.enumerated().map { index, title in FilterChip(title: title, selected: index == 0) }, spacing: 8)
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }()

    private lazy var comboRow: UIView = {
        carousel(combos, spacing: 12)
    }()

    init(league: String, hero: HeroBanner, chips: [String], combos: [ComboCard] = []) {
        self.league = league
        self.hero = hero
        self.chips = chips
        self.combos = combos
        super.init(frame: .zero)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        contentStack.addArrangedSubview(chipRow)
        contentStack.addArrangedSubview(inset(hero, top: 16, bottom: 8))
        if !combos.isEmpty {
            contentStack.addArrangedSubview(inset(Section.header("Combos"), top: 20, bottom: 12))
            contentStack.addArrangedSubview(comboRow)
        }
        var lastSection = ""
        for game in SportsSimulator.shared.games(league: league) {
            if game.section != lastSection {
                lastSection = game.section
                contentStack.addArrangedSubview(inset(Section.header(game.section), top: 24, bottom: 4))
            }
            contentStack.addArrangedSubview(gameCard(game))
        }
    }

    override func pageDidAppear() { hero.animateProgressIn() }
}

/// "Games 4" / "Futures 28" filter chip.
final class FilterChip: PressableControl {
    private let title: String
    private let isChosen: Bool

    private lazy var label: UILabel = {
        let label = UILabel()
        label.text = title
        label.font = Theme.font(15, .medium)
        label.textColor = isChosen ? Theme.textPrimary : UIColor.white.withAlphaComponent(0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String, selected: Bool) {
        self.title = title
        self.isChosen = selected
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        pressedScale = 0.94
        backgroundColor = isChosen ? UIColor(hex: 0x1D1F24) : UIColor(hex: 0x15181E)
        layer.cornerRadius = 19
        layer.cornerCurve = .continuous
        layer.borderWidth = isChosen ? 1 : 0
        layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }
}

// MARK: - Crypto & placeholders

final class CryptoPage: HomePage {
    private lazy var card: UpDownCard = {
        let card = UpDownCard()
        card.onPick = { [weak self] outcome in self?.onBet?(.upDown(SportsSimulator.shared.btc15m, outcome: outcome)) }
        return card
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentStack.addArrangedSubview(inset(card, top: 4))
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class PlaceholderPage: HomePage {
    private let title: String
    private let symbol: String

    private lazy var label: UILabel = {
        let label = UILabel()
        let attachment = NSTextAttachment(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40))!
            .withTintColor(Theme.textSecondary))
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "\n\n\(title) markets\ncoming soon"))
        label.attributedText = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = Theme.font(17, .medium)
        label.textColor = Theme.textSecondary
        return label
    }()

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
        super.init(frame: .zero)
        contentStack.addArrangedSubview(inset(label, top: 120))
    }

    required init?(coder: NSCoder) { fatalError() }
}
