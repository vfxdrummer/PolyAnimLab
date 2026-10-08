import UIKit

final class MarketFeedViewController: UIViewController, UICollectionViewDelegate {
    private let sim = MarketSimulator.shared

    private lazy var layout: UICollectionViewCompositionalLayout = {
        UICollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(170))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 24, trailing: 0)
            return section
        }
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var cellRegistration: UICollectionView.CellRegistration<MarketCell, Int> = {
        UICollectionView.CellRegistration<MarketCell, Int> { [weak self] cell, _, id in
            guard let self, let market = self.sim.market(id: id) else { return }
            cell.apply(market, animated: false, previous: nil)
            cell.onBuy = { [weak self] outcome in
                guard let self else { return }
                BetSheetViewController.present(from: self, marketID: id, outcome: outcome)
            }
        }
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Int> = {
        let registration = cellRegistration
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        applySnapshot()
        NotificationCenter.default.addObserver(self, selector: #selector(marketDidUpdate(_:)), name: .marketDidUpdate, object: nil)
    }

    private func setupViews() {
        title = "Markets"
        view.backgroundColor = Theme.background
        collectionView.frame = view.bounds
        view.addSubview(collectionView)
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(sim.markets.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Live updates go straight to the visible cell. Reloading/re-applying a snapshot would
    /// re-run configuration and kill in-flight animations (and cost a full cell config).
    @objc private func marketDidUpdate(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? Int,
              let old = note.userInfo?["old"] as? Double,
              let indexPath = dataSource.indexPath(for: id),
              let cell = collectionView.cellForItem(at: indexPath) as? MarketCell,
              let market = sim.market(id: id) else { return }
        cell.apply(market, animated: true, previous: old)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        let detail = MarketDetailViewController(marketID: id)
        if #available(iOS 18.0, *) {
            // iOS 18 zoom transition: interactive, interruptible, and the source is re-resolved lazily.
            detail.preferredTransition = .zoom { [weak self] _ in
                guard let self, let ip = self.dataSource.indexPath(for: id) else { return nil }
                return (self.collectionView.cellForItem(at: ip) as? MarketCell)?.card
            }
        }
        navigationController?.pushViewController(detail, animated: true)
    }
}

final class MarketCell: UICollectionViewCell {
    var onBuy: ((Outcome) -> Void)?

    lazy var card: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.card
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = Theme.border.cgColor
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Green/red wash that fades out when the price moves.
    private lazy var flash: UIView = {
        let view = UIView()
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatar: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22)
        label.textAlignment = .center
        label.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(16, .semibold)
        label.textColor = Theme.textPrimary
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var gauge: ChanceGaugeView = {
        let view = ChanceGaugeView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var percent: RollingNumberView = {
        let view = RollingNumberView()
        view.font = Theme.mono(16, .bold)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var chanceLabel: UILabel = {
        let label = UILabel()
        label.text = "chance"
        label.font = Theme.font(11, .medium)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var yesButton: OutcomeButton = {
        let button = OutcomeButton(outcome: .yes, compact: true)
        button.addTarget(self, action: #selector(buyYes), for: .touchUpInside)
        return button
    }()

    private lazy var noButton: OutcomeButton = {
        let button = OutcomeButton(outcome: .no, compact: true)
        button.addTarget(self, action: #selector(buyNo), for: .touchUpInside)
        return button
    }()

    private lazy var buttons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [yesButton, noButton])
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var volumeLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(12, .medium)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.addSubview(card)
        [flash, avatar, titleLabel, gauge, percent, chanceLabel, buttons, volumeLabel].forEach(card.addSubview)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            flash.topAnchor.constraint(equalTo: card.topAnchor),
            flash.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            flash.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            flash.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            avatar.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: avatar.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: gauge.leadingAnchor, constant: -10),

            gauge.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            gauge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            gauge.widthAnchor.constraint(equalToConstant: 64),
            gauge.heightAnchor.constraint(equalToConstant: 34),
            percent.centerXAnchor.constraint(equalTo: gauge.centerXAnchor),
            percent.bottomAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 2),
            chanceLabel.centerXAnchor.constraint(equalTo: gauge.centerXAnchor),
            chanceLabel.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 1),

            buttons.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 14),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: chanceLabel.bottomAnchor, constant: 12),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: avatar.bottomAnchor, constant: 14),
            buttons.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            volumeLabel.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 10),
            volumeLabel.leadingAnchor.constraint(equalTo: buttons.leadingAnchor),
            volumeLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            UIView.animate(springDuration: isHighlighted ? 0.2 : 0.45, bounce: isHighlighted ? 0 : 0.35,
                           initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.card.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.975, y: 0.975) : .identity
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        flash.layer.removeAllAnimations()
        flash.alpha = 0
        card.transform = .identity
    }

    func apply(_ market: Market, animated: Bool, previous: Double?) {
        avatar.text = market.emoji
        titleLabel.text = market.title
        percent.setText(Format.percent(market.probability), animated: animated)
        gauge.setValue(market.probability, animated: animated)
        volumeLabel.text = "\(Format.volume(market.volume)) Vol."
        if animated, let previous, previous != market.probability {
            flashChange(up: market.probability > previous)
        }
    }

    private func flashChange(up: Bool) {
        flash.backgroundColor = up ? Theme.yes : Theme.no
        flash.alpha = 0.16
        UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.flash.alpha = 0
        }
    }

    @objc private func buyYes() { onBuy?(.yes) }
    @objc private func buyNo() { onBuy?(.no) }
}
