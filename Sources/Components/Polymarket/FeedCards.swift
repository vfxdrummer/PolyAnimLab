import UIKit

enum Section {
    /// "Popular", "Live", "Today"… section titles.
    static func header(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.font(20, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }
}

/// Small white "● WATCH" tag used on live/promo content.
final class WatchTag: UIView {
    private lazy var icon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "video.fill"))
        imageView.tintColor = UIColor(hex: 0xE5303A)
        imageView.preferredSymbolConfiguration = .init(pointSize: 9, weight: .bold)
        return imageView
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        label.text = "WATCH"
        label.font = .systemFont(ofSize: 11, weight: .heavy)
        label.textColor = UIColor(hex: 0x0E1015)
        return label
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .white
        layer.cornerRadius = 4
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }
}

// MARK: - BTC Up or Down 15m

/// Live crypto card: ticking countdown, orange sparkline with pulsing dot, Up/Down pills.
final class UpDownCard: UIView {
    var onPick: ((Outcome) -> Void)?

    private lazy var icon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "bitcoinsign"))
        imageView.tintColor = .white
        imageView.preferredSymbolConfiguration = .init(pointSize: 22, weight: .bold)
        imageView.contentMode = .center
        imageView.backgroundColor = Theme.bitcoin
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "BTC Up or Down 15m"
        label.font = Theme.font(17, .medium)
        label.textColor = Theme.textPrimary
        return label
    }()

    /// Blinking "live" dot next to the countdown.
    private lazy var liveDot: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.no
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var countdown: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(15, .medium)
        view.textColor = Theme.no
        view.stagger = 0
        return view
    }()

    private lazy var metaLabel: UILabel = {
        let label = UILabel()
        label.text = "·  BTC  ·  Up/Down"
        label.font = Theme.font(15)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var metaRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [liveDot, countdown, metaLabel])
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }()

    private lazy var titleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, metaRow])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var chart: LiveChartView = {
        let chart = LiveChartView()
        chart.lineColor = Theme.bitcoin
        chart.showsFill = false
        chart.translatesAutoresizingMaskIntoConstraints = false
        return chart
    }()

    private lazy var upPill: PercentPill = {
        let pill = PercentPill(color: Theme.yes)
        pill.addAction(UIAction { [weak self] _ in self?.onPick?(.yes) }, for: .touchUpInside)
        return pill
    }()

    private lazy var downPill: PercentPill = {
        let pill = PercentPill(color: Theme.no)
        pill.addAction(UIAction { [weak self] _ in self?.onPick?(.no) }, for: .touchUpInside)
        return pill
    }()

    private lazy var pills: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [upPill, downPill])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        apply(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(marketDidUpdate), name: .upDownDidUpdate, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = Theme.card.withAlphaComponent(0.6)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Theme.border.cgColor
        [icon, titleStack, chart, pills].forEach(addSubview)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            liveDot.widthAnchor.constraint(equalToConstant: 6),
            liveDot.heightAnchor.constraint(equalToConstant: 6),
            titleStack.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            titleStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),

            chart.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chart.trailingAnchor.constraint(equalTo: pills.leadingAnchor, constant: -4),
            chart.heightAnchor.constraint(equalToConstant: 130),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            pills.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            pills.centerYAnchor.constraint(equalTo: chart.centerYAnchor),
        ])
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Blink the live dot. Re-added on window attach because layer animations are dropped when off-window.
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.2
        blink.duration = 0.8
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        liveDot.layer.add(blink, forKey: "blink")
    }

    private func apply(animated: Bool) {
        let market = SportsSimulator.shared.btc15m
        countdown.setText(String(format: "%02d:%02d", market.secondsLeft / 60, market.secondsLeft % 60), animated: animated)
        chart.setValues(market.history, animated: animated)
        upPill.setChance(market.upChance, animated: animated)
        downPill.setChance(1 - market.upChance, animated: animated)
    }

    @objc private func marketDidUpdate() { apply(animated: window != nil) }
}

// MARK: - Popular tile

/// Compact game tile in the horizontally scrolling "Popular" row.
final class PopularTile: UIView {
    private let game: Game

    private lazy var timeLabel: UILabel = makeMeta(game.time.components(separatedBy: " @ ").last ?? game.time)
    private lazy var leagueLabel: UILabel = makeMeta(game.league)

    private lazy var homePercent: RollingNumberView = makePercent(game.home)
    private lazy var awayPercent: RollingNumberView = makePercent(game.away)

    private lazy var rows: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            UIStackView(arrangedSubviews: [timeLabel, UIView(), leagueLabel]),
            makeTeamRow(game.home, percent: homePercent),
            makeTeamRow(game.away, percent: awayPercent),
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(game: Game) {
        self.game = game
        super.init(frame: .zero)
        setupViews()
        apply(game, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(gameDidUpdate(_:)), name: .gameDidUpdate, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = Theme.card
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        addSubview(rows)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 176),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    private func makeMeta(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.font(13)
        label.textColor = Theme.textSecondary
        return label
    }

    private func makePercent(_ team: Team) -> RollingNumberView {
        let view = RollingNumberView()
        view.font = Theme.mono(15, .medium)
        view.textColor = team.color.isLight ? .white : team.color.withLightness(min: 0.75)
        return view
    }

    private func makeTeamRow(_ team: Team, percent: RollingNumberView) -> UIStackView {
        let name = UILabel()
        name.text = team.name
        name.font = Theme.font(15, .medium)
        name.textColor = Theme.textPrimary
        let stack = UIStackView(arrangedSubviews: [TeamBadge(team: team, size: 20), name, UIView(), percent])
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func apply(_ game: Game, animated: Bool) {
        homePercent.setText(Format.percent(game.homeChance), animated: animated)
        awayPercent.setText(Format.percent(1 - game.homeChance), animated: animated)
    }

    @objc private func gameDidUpdate(_ note: Notification) {
        guard note.userInfo?["id"] as? Int == game.id, let game = SportsSimulator.shared.game(id: game.id) else { return }
        apply(game, animated: window != nil)
    }
}

// MARK: - Promo banner

/// "New on Polymarket" banner: deep purple gradient, condensed italic title, glowing ball.
final class PromoBanner: PressableControl {
    private lazy var gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(hex: 0x1A123C).cgColor, UIColor(hex: 0x33237A).cgColor, UIColor(hex: 0x24185A).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        return layer
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "SHANGHAI MASTERS"
        label.font = .systemFont(ofSize: 25, weight: .heavy, width: .condensed)
        label.textColor = .white
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "ATP Masters 1000"
        label.font = Theme.font(15)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        return label
    }()

    private lazy var tagRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [WatchTag(), subtitleLabel])
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, tagRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var ball: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "tennisball.fill"))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 58, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [UIColor(hex: 0xD9F25A)]))
        imageView.layer.shadowColor = UIColor(hex: 0xD9F25A).cgColor
        imageView.layer.shadowOpacity = 0.55
        imageView.layer.shadowRadius = 14
        imageView.layer.shadowOffset = .zero
        // A shadow without shadowPath on non-rectangular content needs an offscreen pass every frame.
        // This content never changes, so rasterizing (at the screen scale!) is the legitimate fix.
        imageView.layer.shouldRasterize = true
        imageView.layer.rasterizationScale = UIScreen.main.scale
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        pressedScale = 0.97
        layer.insertSublayer(gradient, at: 0)
        addSubview(textStack)
        addSubview(ball)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 98),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ball.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            ball.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Live match

/// Live tennis match: scores per set, current game in a raised box, pills.
final class LiveMatchCard: UIView {
    var onPick: ((String) -> Void)?

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Mackenzie McDonald vs. Ryan Nijboer"
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        let text = NSMutableAttributedString(string: "●  2nd Set", attributes: [.foregroundColor: Theme.no])
        text.append(NSAttributedString(string: "  ·  ATP Challenger Braga  ·  Tennis", attributes: [.foregroundColor: Theme.textSecondary]))
        label.attributedText = text
        label.font = Theme.font(14)
        return label
    }()

    private lazy var playerOne: OutcomeRow = makePlayerRow("M. McDonald", flag: "🇺🇸", scores: ["1", "5", "30"], chance: 0.38)
    private lazy var playerTwo: OutcomeRow = makePlayerRow("R. Nijboer", flag: "🇳🇱", scores: ["6", "3", "30"], chance: 0.64)

    private lazy var footer: UIStackView = {
        let icon = UIImageView(image: UIImage(systemName: "square.stack.3d.up.fill"))
        icon.tintColor = UIColor(hex: 0x8B7CF6)
        icon.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
        let label = UILabel()
        label.text = "19 markets"
        label.font = Theme.font(15)
        label.textColor = Theme.textSecondary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [icon, label, UIView(), WatchTag()])
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, playerOne, playerTwo, footer])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(10, after: subtitleLabel)
        stack.setCustomSpacing(12, after: playerTwo)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    private func makePlayerRow(_ name: String, flag: String, scores: [String], chance: Double) -> OutcomeRow {
        let flagLabel = UILabel()
        flagLabel.text = flag
        flagLabel.font = .systemFont(ofSize: 22)
        let row = OutcomeRow(title: name, color: UIColor(hex: 0xC41050), leading: flagLabel)
        row.setChance(chance, animated: false)
        row.onPick = { [weak self] in self?.onPick?(name) }
        return row
    }
}

// MARK: - League hero banner

/// "MLB 2026 · Postseason" banner with a season-progress slider that springs into place on appear.
final class HeroBanner: UIView {
    private let league: String
    private let phase: String
    private let progressText: String
    private let progress: CGFloat
    private let art: UIImage?

    private lazy var gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(hex: 0x16203A).cgColor, UIColor(hex: 0x27304A).cgColor, UIColor(hex: 0x3A3D48).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "\(league)  2026"
        label.font = .systemFont(ofSize: 30, weight: .heavy, width: .condensed)
        label.textColor = .white
        return label
    }()

    private lazy var phaseLabel: UILabel = {
        let label = UILabel()
        label.text = phase
        label.font = Theme.font(17)
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        return label
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.text = progressText
        label.font = Theme.font(15)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        return label
    }()

    private lazy var track: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        view.layer.cornerRadius = 1.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fill: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 1.5
        return view
    }()

    private lazy var knob: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        view.backgroundColor = .white
        view.layer.cornerRadius = 7
        return view
    }()

    private lazy var artView: UIImageView = {
        let imageView = UIImageView(image: art)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, phaseLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var currentProgress: CGFloat = 0

    init(league: String, phase: String, progressText: String, progress: CGFloat, art: UIImage?) {
        self.league = league
        self.phase = phase
        self.progressText = progressText
        self.progress = progress
        self.art = art
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.insertSublayer(gradient, at: 0)
        [artView, textStack, progressLabel, track].forEach(addSubview)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        track.addSubview(knob)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 180),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            progressLabel.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -12),
            track.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            track.widthAnchor.constraint(equalToConstant: 140),
            track.heightAnchor.constraint(equalToConstant: 3),
            artView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            artView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            artView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.72),
            artView.widthAnchor.constraint(equalTo: artView.heightAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        layoutProgress(currentProgress)
    }

    private func layoutProgress(_ p: CGFloat) {
        let x = track.bounds.width * p
        fill.frame = CGRect(x: 0, y: 0, width: x, height: track.bounds.height)
        knob.center = CGPoint(x: x, y: track.bounds.midY)
    }

    /// Slides the knob from 0 to the season's progress — called when the page becomes visible.
    func animateProgressIn() {
        currentProgress = 0
        layoutProgress(0)
        currentProgress = progress
        UIView.animate(springDuration: 0.9, bounce: 0.2, initialSpringVelocity: 0, delay: 0.15, options: []) {
            self.layoutProgress(self.progress)
        }
    }
}

// MARK: - Combo card

/// Parlay card: four legs, a gradient-bordered "$10 pays $146.20" CTA, social proof footer.
final class ComboCard: PressableControl {
    private let title: String
    private let legs: [(String, String)]
    private let payout: String

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.font = Theme.font(16, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private lazy var countLabel: UILabel = {
        let label = UILabel()
        let attachment = NSTextAttachment(image: UIImage(systemName: "square.stack.3d.up.fill")!.withTintColor(Theme.textSecondary))
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: " \(legs.count)"))
        label.attributedText = text
        label.font = Theme.font(14)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var legsStack: UIStackView = {
        let rows = legs.map { name, chance -> UIStackView in
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.25)
            dot.layer.cornerRadius = 2.5
            dot.widthAnchor.constraint(equalToConstant: 5).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 5).isActive = true
            let label = UILabel()
            label.text = name
            label.font = Theme.font(14)
            label.textColor = UIColor.white.withAlphaComponent(0.85)
            let value = UILabel()
            value.text = chance
            value.font = Theme.mono(14, .regular)
            value.textColor = Theme.textSecondary
            let row = UIStackView(arrangedSubviews: [dot, label, UIView(), value])
            row.spacing = 10
            row.alignment = .center
            return row
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }()

    private lazy var ctaLabel: UILabel = {
        let label = UILabel()
        let text = NSMutableAttributedString(string: "$10 pays ", attributes: [.foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: payout, attributes: [.foregroundColor: UIColor(hex: 0xA78BFA)]))
        label.attributedText = text
        label.font = Theme.font(16, .semibold)
        label.textAlignment = .center
        return label
    }()

    private lazy var cta: GradientBorderView = {
        let view = GradientBorderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var footerLabel: UILabel = {
        let label = UILabel()
        label.text = "👤 1,083                    📊 $16K Vol."
        label.font = Theme.font(12)
        label.textColor = Theme.textSecondary
        return label
    }()

    private lazy var stack: UIStackView = {
        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), countLabel])
        let stack = UIStackView(arrangedSubviews: [header, legsStack, cta, footerLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init(title: String, legs: [(String, String)], payout: String) {
        self.title = title
        self.legs = legs
        self.payout = payout
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        pressedScale = 0.97
        backgroundColor = Theme.card.withAlphaComponent(0.5)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Theme.border.cgColor
        addSubview(stack)
        cta.addSubview(ctaLabel)
        ctaLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 256),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            cta.heightAnchor.constraint(equalToConstant: 46),
            ctaLabel.centerXAnchor.constraint(equalTo: cta.centerXAnchor),
            ctaLabel.centerYAnchor.constraint(equalTo: cta.centerYAnchor),
        ])
    }

}

/// Rounded rect with a purple → teal gradient stroke: a gradient layer masked by a stroked shape layer.
/// Lays out its own layers so the path always matches its final size (a parent's layoutSubviews runs
/// before a stack view has sized its arranged subviews).
final class GradientBorderView: UIView {
    private lazy var gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(hex: 0x8B5CF6).cgColor, UIColor(hex: 0x2DD4BF).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.mask = strokeMask
        return layer
    }()

    private lazy var strokeMask: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = UIColor.black.cgColor
        layer.lineWidth = 1.5
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        layer.addSublayer(gradient)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        strokeMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 12).cgPath
        CATransaction.commit()
    }
}

// MARK: - Build a Combo

/// Floating gradient capsule with a soft colored glow.
final class BuildComboButton: PressableControl {
    private lazy var gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(hex: 0x3BA99C).cgColor, UIColor(hex: 0x5B7BD5).cgColor, UIColor(hex: 0x8B5CF6).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.masksToBounds = true // on the gradient layer only, so the control's glow isn't clipped
        return layer
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        let attachment = NSTextAttachment(image: UIImage(systemName: "square.stack.3d.up.fill")!.withTintColor(.white))
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "  Build a Combo"))
        label.attributedText = text
        label.font = Theme.font(16, .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        hapticStyle = .medium
        layer.insertSublayer(gradient, at: 0)
        layer.shadowColor = UIColor(hex: 0x8B5CF6).cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.cornerRadius = bounds.height / 2
        // Explicit shadowPath: the glow is computed from a known shape instead of an offscreen pass.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        CATransaction.commit()
    }
}
