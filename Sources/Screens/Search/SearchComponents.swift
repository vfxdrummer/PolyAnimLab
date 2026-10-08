import UIKit

// MARK: - Data

/// One searchable market: a game or a multi-outcome future ("Sun Belt Football Championship Winner").
struct SearchMarket {
    struct Line {
        let name: String
        let chance: Double
        let color: UIColor
        var team: Team?
    }

    let title: String
    let subtitle: String
    let icon: String          // SF Symbol for futures; games use the home team's monogram
    let iconTint: UIColor
    let lines: [Line]
    let hiddenCount: Int      // "11 more"
    let keywords: String

    func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && (title + " " + subtitle + " " + keywords).lowercased().contains(q)
    }
}

enum SearchIndex {
    private static let blue = UIColor(hex: 0x3B82F6)
    private static let red = UIColor(hex: 0xE5303A)
    private static let gray = UIColor(hex: 0x6B7280)

    static var all: [SearchMarket] {
        let games = SportsSimulator.shared.games.map { game in
            SearchMarket(
                title: game.title, subtitle: "\(game.time) · \(game.league) · \(game.league == "MLB" ? "Baseball" : "Football")",
                icon: "", iconTint: game.home.color,
                lines: [
                    .init(name: game.home.name, chance: game.homeChance, color: game.home.color, team: game.home),
                    .init(name: game.away.name, chance: 1 - game.homeChance, color: game.away.color, team: game.away),
                ],
                hiddenCount: 0,
                keywords: "\(game.home.city) \(game.away.city) \(game.home.name) \(game.away.name) \(game.league == "NFL" ? "football" : "baseball")")
        }
        let futures: [SearchMarket] = [
            SearchMarket(title: "Sun Belt Football Championship Winner", subtitle: "Fri, Dec 4 · CFB", icon: "football.fill", iconTint: UIColor(hex: 0xC4552A),
                         lines: [.init(name: "Georgia State", chance: 0.03, color: blue), .init(name: "Troy", chance: 0.03, color: red),
                                 .init(name: "Appalachian State", chance: 0.06, color: gray)],
                         hiddenCount: 11, keywords: "college cfb ncaa"),
            SearchMarket(title: "Mountain West Football Championship Winner", subtitle: "Fri, Dec 4 · CFB", icon: "football.fill", iconTint: UIColor(hex: 0x8B5CF6),
                         lines: [.init(name: "Wyoming", chance: 0.02, color: gray), .init(name: "Northern Illinois", chance: 0.02, color: red),
                                 .init(name: "Boise State", chance: 0.41, color: blue)],
                         hiddenCount: 9, keywords: "college cfb ncaa"),
            SearchMarket(title: "2027 Pro Football Champion", subtitle: "Feb 14, 2027 · NFL", icon: "trophy.fill", iconTint: UIColor(hex: 0x3B82F6),
                         lines: [.init(name: "Buffalo", chance: 0.12, color: blue), .init(name: "Los Angeles R", chance: 0.12, color: blue),
                                 .init(name: "Philadelphia", chance: 0.10, color: UIColor(hex: 0x0B6E5F))],
                         hiddenCount: 29, keywords: "super bowl nfl football"),
            SearchMarket(title: "NLDS Winner: ATL Braves vs LA Dodgers", subtitle: "Fri, Oct 9 · MLB", icon: "baseball.fill", iconTint: UIColor(hex: 0x22B24C),
                         lines: [.init(name: "Dodgers", chance: 0.84, color: UIColor(hex: 0x1B81BE), team: SportsSimulator.shared.game(id: 0)?.home),
                                 .init(name: "Braves", chance: 0.16, color: UIColor(hex: 0xC41050), team: SportsSimulator.shared.game(id: 0)?.away)],
                         hiddenCount: 0, keywords: "dodgers braves baseball nlds playoffs"),
            SearchMarket(title: "World Series Champion 2026", subtitle: "Oct 30 · MLB", icon: "trophy.fill", iconTint: UIColor(hex: 0xC58E06),
                         lines: [.init(name: "Dodgers", chance: 0.31, color: UIColor(hex: 0x1B81BE)), .init(name: "Yankees", chance: 0.22, color: UIColor(hex: 0x225891)),
                                 .init(name: "Brewers", chance: 0.15, color: UIColor(hex: 0xC58E06))],
                         hiddenCount: 5, keywords: "mlb baseball dodgers yankees brewers"),
        ]
        return futures.filter { $0.subtitle.contains("CFB") } + games + futures.filter { !$0.subtitle.contains("CFB") }
    }

    static func search(_ query: String) -> [SearchMarket] { all.filter { $0.matches(query) } }

    static var futures: [SearchMarket] { all.filter { $0.icon == "trophy.fill" } }
}

// MARK: - Odds line

/// Compact outcome row used by futures cards and search results:
/// [badge] Name (odds bar underneath)              58%
final class OddsLine: UIView {
    private let line: SearchMarket.Line

    private var displayColor: UIColor { line.color.isLight ? .white : line.color.withLightness(min: 0.7) }

    /// Teams get their monogram; other outcomes get the real app's blank dark square.
    lazy var badge: UIView = {
        if let team = line.team { return TeamBadge(team: team, size: 26) }
        let view = UIView()
        view.backgroundColor = UIColor(hex: 0x1F232B)
        view.layer.cornerRadius = 6
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 26).isActive = true
        view.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.text = line.name
        label.font = Theme.font(16, .medium)
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bar: UIView = {
        let view = UIView()
        view.backgroundColor = displayColor
        view.layer.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var percentLabel: UILabel = {
        let label = UILabel()
        label.text = Format.percent(line.chance)
        label.font = Theme.mono(15, .medium)
        label.textColor = displayColor
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var track: UILayoutGuide = UILayoutGuide()

    init(line: SearchMarket.Line) {
        self.line = line
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        badge.translatesAutoresizingMaskIntoConstraints = false
        [badge, nameLabel, bar, percentLabel].forEach(addSubview)
        addLayoutGuide(track)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            track.trailingAnchor.constraint(equalTo: percentLabel.leadingAnchor, constant: -60),
            bar.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            bar.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bar.heightAnchor.constraint(equalToConstant: 2),
            bar.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.03, CGFloat(line.chance))),
        ])
    }
}

// MARK: - Result card

/// "Sun Belt Football Championship Winner" + up to three odds lines + "11 more".
final class SearchResultCard: UIView {
    private let market: SearchMarket

    /// Icon tile; fades in a beat after the text, like a remote image arriving.
    lazy var icon: UILabel = {
        let label = UILabel()
        if market.icon.isEmpty, let team = market.lines.first?.team {
            label.text = team.monogram
            label.font = .systemFont(ofSize: 15, weight: .heavy)
            label.textColor = team.color.isLight ? team.color : team.color.withLightness(min: 0.65)
        } else {
            let image = UIImage(systemName: market.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))!
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            label.attributedText = NSAttributedString(attachment: NSTextAttachment(image: image))
            label.backgroundColor = market.iconTint
        }
        label.textAlignment = .center
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = market.title
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.textPrimary
        label.numberOfLines = 2
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = market.subtitle
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var titleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    lazy var lines: [OddsLine] = market.lines.map { OddsLine(line: $0) }

    private lazy var moreLabel: UILabel = {
        let label = UILabel()
        label.text = "\(market.hiddenCount) more"
        label.font = Theme.font(15)
        label.textColor = Theme.textSecondary
        label.isHidden = market.hiddenCount == 0
        return label
    }()

    private lazy var linesStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: lines + [moreLabel])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(market: SearchMarket) {
        self.market = market
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        [icon, titleStack, linesStack, separator].forEach(addSubview)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            titleStack.topAnchor.constraint(equalTo: icon.topAnchor, constant: -2),
            titleStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            linesStack.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 8),
            linesStack.topAnchor.constraint(greaterThanOrEqualTo: icon.bottomAnchor, constant: 6),
            linesStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            linesStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            linesStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}

// MARK: - Browse pieces

/// Category chip: icon + label in a bordered capsule.
final class CategoryChip: PressableControl {
    private let title: String
    private let symbol: String
    private let tint: UIColor

    private lazy var label: UILabel = {
        let label = UILabel()
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))!
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        let text = NSMutableAttributedString(attachment: NSTextAttachment(image: image))
        text.append(NSAttributedString(string: "  \(title)"))
        label.attributedText = text
        label.font = Theme.font(16, .medium)
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String, symbol: String, tint: UIColor) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        pressedScale = 0.94
        backgroundColor = UIColor(hex: 0x14171D)
        layer.cornerRadius = 19
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }
}

/// Small live-match tile: "● 3rd Set   ATP" + two competitors with scores.
final class LiveTile: UIView {
    private let status: String
    private let league: String
    private let competitors: [(String, String, String)] // (flag/emoji, name, score)

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "● \(status)"
        label.font = Theme.font(13, .medium)
        label.textColor = Theme.no
        return label
    }()

    private lazy var leagueLabel: UILabel = {
        let label = UILabel()
        label.text = league
        label.font = Theme.font(13)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var stack: UIStackView = {
        let header = UIStackView(arrangedSubviews: [statusLabel, UIView(), leagueLabel])
        let rows = competitors.map { flag, name, score -> UIStackView in
            let flagLabel = UILabel()
            flagLabel.text = flag
            flagLabel.font = .systemFont(ofSize: 16)
            flagLabel.setContentHuggingPriority(.required, for: .horizontal)
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = Theme.font(15, .medium)
            nameLabel.textColor = Theme.textPrimary
            let scoreLabel = UILabel()
            scoreLabel.text = score
            scoreLabel.font = Theme.mono(15, .medium)
            scoreLabel.textColor = Theme.textPrimary
            scoreLabel.setContentHuggingPriority(.required, for: .horizontal)
            scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal) // truncate the name, never the score
            let row = UIStackView(arrangedSubviews: [flagLabel, nameLabel, scoreLabel])
            row.spacing = 8
            return row
        }
        let stack = UIStackView(arrangedSubviews: [header] + rows)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(status: String, league: String, competitors: [(String, String, String)]) {
        self.status = status
        self.league = league
        self.competitors = competitors
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = Theme.card
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 172),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
}

/// "2027 Pro Football Champion" card in the Futures carousel.
final class FuturesCard: UIView {
    private let market: SearchMarket

    private lazy var icon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: market.icon))
        imageView.tintColor = .white
        imageView.preferredSymbolConfiguration = .init(pointSize: 20, weight: .semibold)
        imageView.contentMode = .center
        imageView.backgroundColor = market.iconTint
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = market.title
        label.font = Theme.font(16, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = market.subtitle
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var stack: UIStackView = {
        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, titles])
        header.spacing = 12
        header.alignment = .center
        let stack = UIStackView(arrangedSubviews: [header] + market.lines.prefix(2).map { OddsLine(line: $0) })
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(market: SearchMarket) {
        self.market = market
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = Theme.card.withAlphaComponent(0.6)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Theme.border.cgColor
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 300),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }
}
