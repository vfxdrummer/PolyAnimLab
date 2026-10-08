import UIKit

/// Live probability chart: line + gradient fill + pulsing "live" dot + scrubbing.
///
/// Techniques on display:
/// - Path morphing: CABasicAnimation on `path`. Paths must have the SAME number of points to
///   interpolate nicely, so data is resampled to a fixed `sampleCount`.
/// - Draw-in via `strokeEnd`, staggered fade of the fill via `beginTime` + `fillMode = .backwards`.
/// - Infinite pulse via CAAnimationGroup, re-added in didMoveToWindow (layer animations are
///   removed when a layer leaves the window / app is backgrounded).
/// - Scrubbing moves layers inside CATransaction.setDisableActions(true) so they track the
///   finger 1:1 instead of lagging behind an implicit 0.25s animation.
final class LiveChartView: UIView {
    var onScrub: ((Double?) -> Void)?
    var lineColor: UIColor = Theme.accent { didSet { applyColors() } }
    /// The real app's sparklines are line-only; the v1 detail chart keeps its gradient fill.
    var showsFill = true { didSet { fillLayer.isHidden = !showsFill } }

    private(set) var values: [Double] = []
    private var points: [CGPoint] = []
    private let sampleCount = 120
    private let insets = UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 16)
    private let morphDuration: CFTimeInterval = 0.5
    private let morphTiming = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)

    private var scrubIndex: Int?
    private var lastLayoutSize: CGSize = .zero

    private lazy var lineLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 2.5
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }()

    private lazy var fillMask: CAShapeLayer = {
        CAShapeLayer()
    }()

    private lazy var fillLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.mask = fillMask // note: masks cost an offscreen pass — fine for one chart
        return layer
    }()

    private lazy var dot: CALayer = {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        layer.cornerRadius = 4.5
        return layer
    }()

    private lazy var pulse: CALayer = {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        layer.cornerRadius = 4.5
        return layer
    }()

    /// Holds the dot + its pulse ring so both move together.
    private lazy var dotContainer: CALayer = {
        let layer = CALayer()
        layer.addSublayer(pulse)
        layer.addSublayer(dot)
        return layer
    }()

    private lazy var scrubLine: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.opacity = 0
        return layer
    }()

    private lazy var scrubDot: CALayer = {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        layer.cornerRadius = 7
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
        layer.opacity = 0
        return layer
    }()

    private lazy var haptics: UISelectionFeedbackGenerator = {
        UISelectionFeedbackGenerator()
    }()

    private lazy var press: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        gesture.minimumPressDuration = 0.12
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        [fillLayer, lineLayer, scrubLine, dotContainer, scrubDot].forEach(layer.addSublayer)
        addGestureRecognizer(press)
        applyColors()

        NotificationCenter.default.addObserver(self, selector: #selector(startPulse),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    private func applyColors() {
        lineLayer.strokeColor = lineColor.cgColor
        fillLayer.colors = [lineColor.withAlphaComponent(0.28).cgColor, lineColor.withAlphaComponent(0).cgColor]
        dot.backgroundColor = lineColor.cgColor
        pulse.backgroundColor = lineColor.cgColor
        scrubDot.backgroundColor = lineColor.cgColor
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [fillLayer, fillMask, lineLayer] as [CALayer] { l.frame = bounds }
        scrubLine.frame = CGRect(x: scrubLine.frame.minX, y: insets.top - 10, width: 1,
                                 height: bounds.height - insets.top - insets.bottom + 20)
        redraw(animated: false)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startPulse() }
    }

    // MARK: Data

    func setValues(_ raw: [Double], animated: Bool) {
        values = Self.resample(raw, to: sampleCount)
        redraw(animated: animated)
    }

    static func resample(_ v: [Double], to n: Int) -> [Double] {
        guard v.count > 1 else { return Array(repeating: v.first ?? 0.5, count: n) }
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1) * Double(v.count - 1)
            let lo = Int(t.rounded(.down)), hi = min(lo + 1, v.count - 1)
            let f = t - Double(lo)
            return v[lo] * (1 - f) + v[hi] * f
        }
    }

    private func makePoints(_ v: [Double]) -> [CGPoint] {
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return [] }
        let pad = max((hi - lo) * 0.15, 0.02)
        let minV = lo - pad, maxV = hi + pad
        let plot = bounds.inset(by: insets)
        return v.enumerated().map { i, val in
            CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: plot.minY + plot.height * CGFloat(1 - (val - minV) / (maxV - minV)))
        }
    }

    private func redraw(animated: Bool) {
        guard bounds.width > 0 else { return }
        points = makePoints(values)
        guard let first = points.first, let last = points.last else { return }

        let line = UIBezierPath()
        line.move(to: first)
        points.dropFirst().forEach(line.addLine(to:))
        let fill = line.copy() as! UIBezierPath
        fill.addLine(to: CGPoint(x: last.x, y: bounds.maxY))
        fill.addLine(to: CGPoint(x: first.x, y: bounds.maxY))
        fill.close()

        morph(lineLayer, to: line.cgPath, animated: animated)
        morph(fillMask, to: fill.cgPath, animated: animated)

        let fromPosition = dotContainer.presentation()?.position ?? dotContainer.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotContainer.position = last
        if let i = scrubIndex, points.indices.contains(i) { scrubDot.position = points[i] }
        CATransaction.commit()
        if animated {
            let a = CABasicAnimation(keyPath: "position")
            a.fromValue = NSValue(cgPoint: fromPosition)
            a.toValue = NSValue(cgPoint: last)
            a.duration = morphDuration
            a.timingFunction = morphTiming
            dotContainer.add(a, forKey: "position")
        }
    }

    /// The core pattern for explicit CA animations:
    /// 1) read `from` off the presentation layer (handles interruption),
    /// 2) set the model value with actions disabled,
    /// 3) add an explicit animation from → to.
    private func morph(_ shape: CAShapeLayer, to path: CGPath, animated: Bool) {
        let from = shape.presentation()?.path ?? shape.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
        guard animated, let from else { return }
        let a = CABasicAnimation(keyPath: "path")
        a.fromValue = from
        a.toValue = path
        a.duration = morphDuration
        a.timingFunction = morphTiming
        shape.add(a, forKey: "path")
    }

    // MARK: Entrance + pulse

    func animateDrawIn() {
        let now = CACurrentMediaTime()
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.9
        draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        lineLayer.add(draw, forKey: "drawIn")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.6
        fade.beginTime = now + 0.35
        fade.fillMode = .backwards // hold fromValue during the delay
        fillLayer.add(fade, forKey: "fadeIn")

        let pop = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.45)
        pop.keyPath = "transform.scale"
        pop.fromValue = 0
        pop.toValue = 1
        pop.duration = pop.settlingDuration
        pop.beginTime = now + 0.75
        pop.fillMode = .backwards
        dotContainer.add(pop, forKey: "pop")
    }

    @objc private func startPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 3.2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.6
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.opacity = 0
        pulse.add(group, forKey: "pulse")
    }

    // MARK: Scrubbing

    @objc private func handlePress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            haptics.prepare()
            setScrubVisible(true)
            updateScrub(at: g.location(in: self).x)
        case .changed:
            updateScrub(at: g.location(in: self).x)
        default:
            scrubIndex = nil
            setScrubVisible(false)
            onScrub?(nil)
        }
    }

    private func updateScrub(at x: CGFloat) {
        guard points.count > 1 else { return }
        let plot = bounds.inset(by: insets)
        let t = (x - plot.minX) / plot.width
        let i = max(0, min(points.count - 1, Int((t * CGFloat(points.count - 1)).rounded())))
        guard i != scrubIndex else { return }
        scrubIndex = i
        if i % 3 == 0 { haptics.selectionChanged() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrubLine.position.x = points[i].x
        scrubDot.position = points[i]
        CATransaction.commit()
        onScrub?(values[i])
    }

    private func setScrubVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15) // implicit animation, but quicker than the 0.25 default
        scrubLine.opacity = visible ? 1 : 0
        scrubDot.opacity = visible ? 1 : 0
        dotContainer.opacity = visible ? 0.25 : 1
        CATransaction.commit()
    }
}
