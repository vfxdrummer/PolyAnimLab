import UIKit

/// Segmented control with a sliding, springy pill. Used for chart ranges and the Yes/No toggle.
final class PillSegmentedControl: UIControl {
    private(set) var selectedIndex = 0
    /// Optional per-segment indicator colors (backgroundColor is animatable, so it cross-fades for free).
    var indicatorColors: [UIColor]? { didSet { indicator.backgroundColor = indicatorColor(selectedIndex) } }
    var selectedTextColor: UIColor = .white
    var normalTextColor: UIColor = Theme.textSecondary

    private let items: [String]
    private let font: UIFont

    private lazy var indicator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var labels: [UILabel] = items.enumerated().map { i, item in
        let label = UILabel()
        label.text = item
        label.font = font
        label.textAlignment = .center
        label.textColor = i == selectedIndex ? selectedTextColor : normalTextColor
        return label
    }

    private lazy var haptics: UISelectionFeedbackGenerator = {
        UISelectionFeedbackGenerator()
    }()

    private lazy var tap: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    }()

    init(items: [String], font: UIFont = Theme.font(14, .semibold)) {
        self.items = items
        self.font = font
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        addSubview(indicator)
        labels.forEach(addSubview)
        addGestureRecognizer(tap)
    }

    func setTitle(_ title: String, at index: Int) { labels[index].text = title }

    private func indicatorColor(_ i: Int) -> UIColor {
        indicatorColors?[i] ?? UIColor.white.withAlphaComponent(0.12)
    }

    private func segmentFrame(_ i: Int) -> CGRect {
        let w = bounds.width / CGFloat(labels.count)
        return CGRect(x: w * CGFloat(i), y: 0, width: w, height: bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, l) in labels.enumerated() { l.frame = segmentFrame(i) }
        indicator.frame = segmentFrame(selectedIndex).insetBy(dx: 2, dy: 2)
        indicator.layer.cornerRadius = indicator.bounds.height / 2
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let i = Int(g.location(in: self).x / (bounds.width / CGFloat(labels.count)))
        select(max(0, min(labels.count - 1, i)), animated: true)
    }

    func select(_ index: Int, animated: Bool) {
        guard index != selectedIndex else { return }
        let old = selectedIndex
        selectedIndex = index
        haptics.selectionChanged()

        let changes = {
            self.indicator.frame = self.segmentFrame(index).insetBy(dx: 2, dy: 2)
            self.indicator.backgroundColor = self.indicatorColor(index)
        }
        if animated {
            UIView.animate(springDuration: 0.45, bounce: 0.22, initialSpringVelocity: 0, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: changes)
            // textColor isn't animatable — cross-dissolve the label's rendered content instead.
            for (i, color) in [(old, normalTextColor), (index, selectedTextColor)] {
                UIView.transition(with: labels[i], duration: 0.2, options: .transitionCrossDissolve) {
                    self.labels[i].textColor = color
                }
            }
        } else {
            changes()
            labels[old].textColor = normalTextColor
            labels[index].textColor = selectedTextColor
        }
        sendActions(for: .valueChanged)
    }
}
