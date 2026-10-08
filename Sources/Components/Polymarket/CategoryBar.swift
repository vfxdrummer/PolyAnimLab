import UIKit

/// Home / MLB / NFL / Crypto… icon row with a rounded highlight behind the selected icon.
///
/// The highlight has no animation of its own: it's a pure function of the pager's scroll position
/// (`setPagePosition`). Swiping, decelerating and tap-to-jump all move it through the same code path,
/// so it can never drift out of sync with the content, and it's interruptible for free.
final class CategoryBar: UIView {
    struct Item {
        let title: String
        let symbol: String
        let colors: [UIColor]
    }

    var onSelect: ((Int) -> Void)?
    private let items: [Item]
    private var lastIndex = 0

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 56)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var highlight: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: 0x1C2029)
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var itemViews: [ItemView] = items.enumerated().map { index, item in
        let view = ItemView(item: item)
        view.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
        return view
    }

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: itemViews)
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Filter button pinned on the right with a fade so items slide "under" it.
    private lazy var filterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = Theme.textPrimary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var fade: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [Theme.background.withAlphaComponent(0).cgColor, Theme.background.cgColor, Theme.background.cgColor]
        layer.locations = [0, 0.35, 1]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()

    private lazy var fadeView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(fade)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var haptics: UISelectionFeedbackGenerator = {
        UISelectionFeedbackGenerator()
    }()

    init(items: [Item]) {
        self.items = items
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(scrollView)
        scrollView.addSubview(highlight)
        scrollView.addSubview(stack)
        addSubview(fadeView)
        addSubview(filterButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 66),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: 76),
            filterButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            filterButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            filterButton.widthAnchor.constraint(equalToConstant: 40),
            filterButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = fadeView.bounds
        CATransaction.commit()
        stack.layoutIfNeeded()
        setPagePosition(CGFloat(lastIndex))
    }

    private func highlightFrame(_ index: Int) -> CGRect {
        let item = itemViews[index].frame
        return CGRect(x: item.midX - 23, y: 2, width: 46, height: 42)
    }

    /// `position` is the pager's fractional page (e.g. 1.4 = 40% of the way from MLB to NFL).
    func setPagePosition(_ position: CGFloat) {
        guard !itemViews.isEmpty, itemViews[0].frame.width > 0 else { return }
        let clamped = max(0, min(CGFloat(items.count - 1), position))
        let lower = Int(clamped.rounded(.down)), upper = min(lower + 1, items.count - 1)
        let t = clamped - CGFloat(lower)
        let a = highlightFrame(lower), b = highlightFrame(upper)
        highlight.frame = CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY, width: a.width, height: a.height)
        for (i, view) in itemViews.enumerated() {
            let distance = abs(CGFloat(i) - clamped)
            view.setSelectedAmount(max(0, 1 - distance))
        }

        let nearest = Int(clamped.rounded())
        if nearest != lastIndex {
            lastIndex = nearest
            haptics.selectionChanged()
            scrollView.scrollRectToVisible(itemViews[nearest].frame.insetBy(dx: -40, dy: 0), animated: true)
        }
    }

    /// Icon over a label; label color blends from gray to white with the selection amount.
    private final class ItemView: UIControl {
        private let item: Item

        private lazy var icon: UIImageView = {
            let imageView = UIImageView(image: UIImage(systemName: item.symbol))
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
                .applying(UIImage.SymbolConfiguration(paletteColors: item.colors))
            imageView.contentMode = .center
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        private lazy var label: UILabel = {
            let label = UILabel()
            label.text = item.title
            label.font = Theme.font(12, .medium)
            label.textColor = Theme.textSecondary
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        init(item: Item) {
            self.item = item
            super.init(frame: .zero)
            setupViews()
        }

        required init?(coder: NSCoder) { fatalError() }

        private func setupViews() {
            addSubview(icon)
            addSubview(label)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 58),
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                icon.heightAnchor.constraint(equalToConstant: 34),
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 6),
            ])
        }

        func setSelectedAmount(_ amount: CGFloat) {
            label.textColor = Theme.textSecondary.blended(with: .white, amount: amount)
        }

        override var isHighlighted: Bool {
            didSet {
                UIView.animate(springDuration: isHighlighted ? 0.15 : 0.4, bounce: isHighlighted ? 0 : 0.5,
                               initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.icon.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
                }
            }
        }
    }
}

extension UIColor {
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
