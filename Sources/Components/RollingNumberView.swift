import UIKit

/// Odometer-style number ("62%", "$1,240.50"). Each digit is a vertical strip of 0–9
/// inside a clipping column; changing a digit springs the strip's transform.
///
/// Why it performs well:
/// - Only `transform` animates → no layout work per frame, Core Animation interpolates on the render server.
/// - `.beginFromCurrentState` + UIKit's additive springs means rapid updates retarget smoothly.
/// - Digits stagger right-to-left, like a real odometer.
final class RollingNumberView: UIView {
    var font: UIFont = Theme.mono(28, .bold) { didSet { rebuild(Array(text), previous: Array(text)) } }
    var textColor: UIColor = Theme.textPrimary { didSet { columns.forEach { ($0 as? Colorable)?.setColor(textColor) } } }
    var stagger: TimeInterval = 0.025

    private(set) var text = ""
    private var columns: [UIView] = []

    private lazy var stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
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
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isAccessibilityElement = true
    }

    func setText(_ newText: String, animated: Bool) {
        guard newText != text else { return }
        let old = Array(text), new = Array(newText)
        text = newText
        accessibilityLabel = newText

        // Same "shape" (digits in the same slots) → reuse columns and just roll. Otherwise rebuild,
        // seeding each new digit column with the old digit at the same right-aligned position.
        let sameShape = old.count == new.count && zip(old, new).allSatisfy { a, b in
            a.isWholeNumber == b.isWholeNumber && (a.isWholeNumber || a == b)
        }
        if !sameShape { rebuild(new, previous: old) }

        for (i, ch) in new.enumerated() {
            guard let digit = ch.wholeNumberValue, let column = columns[i] as? DigitColumn else { continue }
            let fromRight = new.count - 1 - i
            column.setDigit(digit, animated: animated, delay: Double(fromRight) * stagger)
        }
    }

    private func rebuild(_ chars: [Character], previous: [Character]) {
        columns.forEach { $0.removeFromSuperview() }
        columns = chars.enumerated().map { i, ch -> UIView in
            if let digit = ch.wholeNumberValue {
                let column = DigitColumn(font: font, color: textColor)
                let oldIndex = previous.count - (chars.count - i)
                let start = previous.indices.contains(oldIndex) ? (previous[oldIndex].wholeNumberValue ?? digit) : digit
                column.setDigit(start, animated: false, delay: 0)
                return column
            }
            let label = StaticColumn()
            label.text = String(ch)
            label.font = font
            label.textColor = textColor
            return label
        }
        columns.forEach(stack.addArrangedSubview)
    }
}

private protocol Colorable { func setColor(_ color: UIColor) }

private final class StaticColumn: UILabel, Colorable {
    func setColor(_ color: UIColor) { textColor = color }
}

private final class DigitColumn: UIView, Colorable {
    private let font: UIFont
    private let initialColor: UIColor
    private let digitSize: CGSize

    /// Digits 0–9 stacked vertically, one digit-height apart.
    private lazy var labels: [UILabel] = (0..<10).map { i in
        let label = UILabel(frame: CGRect(x: 0, y: CGFloat(i) * digitSize.height, width: digitSize.width, height: digitSize.height))
        label.text = "\(i)"
        label.font = font
        label.textColor = initialColor
        label.textAlignment = .center
        return label
    }

    private lazy var strip: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: digitSize.width, height: digitSize.height * 10))
        labels.forEach(view.addSubview)
        return view
    }()

    init(font: UIFont, color: UIColor) {
        self.font = font
        self.initialColor = color
        // With monospaced digits every glyph shares this width.
        let width = ceil(("0" as NSString).size(withAttributes: [.font: font]).width)
        digitSize = CGSize(width: width, height: ceil(font.lineHeight))
        super.init(frame: CGRect(origin: .zero, size: digitSize))
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        clipsToBounds = true
        addSubview(strip)
    }

    override var intrinsicContentSize: CGSize { digitSize }

    func setColor(_ color: UIColor) { labels.forEach { $0.textColor = color } }

    func setDigit(_ digit: Int, animated: Bool, delay: TimeInterval) {
        let target = CGAffineTransform(translationX: 0, y: -CGFloat(digit) * digitSize.height)
        guard animated else { strip.transform = target; return }
        UIView.animate(springDuration: 0.55, bounce: 0.2, initialSpringVelocity: 0, delay: delay,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.strip.transform = target
        }
    }
}
