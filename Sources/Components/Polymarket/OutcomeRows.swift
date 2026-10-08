import UIKit

/// Team "logo": a monogram in the team color (stand-in for real team marks).
final class TeamBadge: UILabel {
    init(team: Team, size: CGFloat = 28) {
        super.init(frame: .zero)
        text = team.monogram
        font = .systemFont(ofSize: size * (team.monogram.count > 2 ? 0.36 : 0.5), weight: .heavy)
        textColor = team.color.isLight ? team.color : team.color.withLightness(min: 0.62)
        textAlignment = .center
        adjustsFontSizeToFitWidth = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

extension UIColor {
    /// Brightens dark team colors so they stay legible on the near-black background.
    func withLightness(min minimum: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(b, minimum), alpha: a)
    }
}

/// One outcome line: [badge] Name ───────── (underline sized to the odds)   1.7x  [57%]
/// The underline is the real app's subtle "odds bar"; it springs to its new length on every price tick.
final class OutcomeRow: UIView {
    var onPick: (() -> Void)?
    private let color: UIColor
    private var chance: Double = 0.5
    private let title: String
    private var underlineWidth: NSLayoutConstraint?

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.font = Theme.font(17, .medium)
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Spans from the name to the multiplier; the underline is a fraction of it.
    private lazy var track: UILayoutGuide = UILayoutGuide()

    private lazy var underline: UIView = {
        let view = UIView()
        view.backgroundColor = color.isLight ? UIColor(white: 0.8, alpha: 1) : color.withLightness(min: 0.6)
        view.layer.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var multiplierLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.mono(15, .regular)
        label.textColor = Theme.textSecondary
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var pill: PercentPill = {
        let pill = PercentPill(color: color)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
        return pill
    }()

    private let leading: UIView

    init(title: String, color: UIColor, leading: UIView) {
        self.title = title
        self.color = color
        self.leading = leading
        super.init(frame: .zero)
        setupViews()
    }

    convenience init(team: Team) {
        self.init(title: team.name, color: team.color, leading: TeamBadge(team: team))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        leading.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leading)
        addSubview(nameLabel)
        addSubview(underline)
        addSubview(multiplierLabel)
        addSubview(pill)
        addLayoutGuide(track)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leading.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),

            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            multiplierLabel.trailingAnchor.constraint(equalTo: pill.leadingAnchor, constant: -14),
            multiplierLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            multiplierLabel.widthAnchor.constraint(equalToConstant: 44),

            track.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            track.trailingAnchor.constraint(equalTo: multiplierLabel.leadingAnchor, constant: -12),

            underline.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            underline.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            underline.heightAnchor.constraint(equalToConstant: 2),
        ])
        setUnderline(chance)
    }

    func setChance(_ chance: Double, animated: Bool) {
        self.chance = chance
        pill.setChance(chance, animated: animated)
        multiplierLabel.text = String(format: "%.1fx", 1 / max(chance, 0.01))
        setUnderline(chance)
        guard animated, superview != nil else { return }
        UIView.animate(springDuration: 0.6, bounce: 0.15, initialSpringVelocity: 0, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) { self.layoutIfNeeded() }
    }

    /// Multipliers are immutable on constraints, so swap the width constraint and animate the layout pass.
    private func setUnderline(_ chance: Double) {
        underlineWidth?.isActive = false
        underlineWidth = underline.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.02, CGFloat(chance)))
        underlineWidth?.isActive = true
    }

    @objc private func pillTapped() { onPick?() }
}

/// "Game 4: LA Dodgers vs. ATL Braves" card with two live outcome rows and a "347 markets" footer.
final class GameCardView: UIView {
    let gameID: Int
    var onPick: ((Game, Team) -> Void)?

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.textPrimary
        label.numberOfLines = 2
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var homeRow: OutcomeRow = {
        let row = OutcomeRow(team: game.home)
        row.onPick = { [weak self] in self?.pick(home: true) }
        return row
    }()

    private lazy var awayRow: OutcomeRow = {
        let row = OutcomeRow(team: game.away)
        row.onPick = { [weak self] in self?.pick(home: false) }
        return row
    }()

    private lazy var marketsRow: UIStackView = {
        let icon = UIImageView(image: UIImage(systemName: "square.stack.3d.up.fill"))
        icon.tintColor = UIColor(hex: 0x8B7CF6)
        icon.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
        let label = UILabel()
        label.text = "\(game.marketCount) markets"
        label.font = Theme.font(15)
        label.textColor = Theme.textSecondary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [icon, label, UIView()])
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, homeRow, awayRow, marketsRow])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(10, after: subtitleLabel)
        stack.setCustomSpacing(12, after: awayRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var game: Game

    init(game: Game) {
        self.game = game
        self.gameID = game.id
        super.init(frame: .zero)
        setupViews()
        apply(game, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(gameDidUpdate(_:)), name: .gameDidUpdate, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(stack)
        addSubview(separator)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    func apply(_ game: Game, animated: Bool) {
        self.game = game
        titleLabel.text = game.title
        subtitleLabel.text = game.subtitle
        homeRow.setChance(game.homeChance, animated: animated)
        awayRow.setChance(1 - game.homeChance, animated: animated)
    }

    @objc private func gameDidUpdate(_ note: Notification) {
        guard note.userInfo?["id"] as? Int == gameID, let game = SportsSimulator.shared.game(id: gameID) else { return }
        apply(game, animated: window != nil) // don't animate off-screen pages
    }

    private func pick(home: Bool) { onPick?(game, home ? game.home : game.away) }
}
