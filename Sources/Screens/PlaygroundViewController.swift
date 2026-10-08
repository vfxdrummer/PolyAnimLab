import UIKit

/// Side-by-side timing curves, an interruptible fling-to-corner, and keyframe/symbol effects.
final class PlaygroundViewController: UIViewController {
    private var curveDots: [(UIView, (UIView, CGAffineTransform) -> Void)] = []
    private var curvesAtEnd = false
    private var flingAnimator: UIViewPropertyAnimator?
    private var panStart: CGPoint = .zero

    private lazy var scroll: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var slowMoItem: UIBarButtonItem = {
        UIBarButtonItem(title: "Slow-mo", style: .plain, target: self, action: #selector(toggleSlowMo))
    }()

    private lazy var pip: UIView = {
        let view = UIView(frame: CGRect(x: 12, y: 12, width: 110, height: 72))
        view.backgroundColor = Theme.accent
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        return view
    }()

    private lazy var flingArea: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.addSubview(pip)
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        title = "Playground"
        view.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = slowMoItem
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        buildCurves()
        buildFling()
        buildEffects()
    }

    // MARK: Slow-mo — CALayer.speed on the window slows EVERY animation (UIKit, CA, property animators).

    @objc private func toggleSlowMo() {
        guard let layer = view.window?.layer else { return }
        layer.speed = layer.speed == 1 ? 0.2 : 1
        slowMoItem.title = layer.speed == 1 ? "Slow-mo" : "Slow-mo ✓"
    }

    // MARK: Curves

    private func header(_ title: String, _ subtitle: String) {
        let t = UILabel()
        t.text = title
        t.font = Theme.font(20, .bold)
        t.textColor = Theme.textPrimary
        let s = UILabel()
        s.text = subtitle
        s.font = Theme.font(13)
        s.textColor = Theme.textSecondary
        s.numberOfLines = 0
        stack.addArrangedSubview(t)
        stack.addArrangedSubview(s)
        stack.setCustomSpacing(4, after: t)
    }

    private func buildCurves() {
        header("Timing curves", "Same distance, different feel. Springs with bounce 0 are the modern default for UI motion; a curve has a fixed duration and can't carry velocity.")
        let demos: [(String, UIColor, (UIView, CGAffineTransform) -> Void)] = [
            ("easeInOut 0.5s", .systemGray, { v, t in
                UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) { v.transform = t }
            }),
            ("spring bounce 0", Theme.accent, { v, t in
                UIView.animate(springDuration: 0.5, bounce: 0, initialSpringVelocity: 0, delay: 0, options: .beginFromCurrentState) { v.transform = t }
            }),
            ("spring bounce 0.3", Theme.yes, { v, t in
                UIView.animate(springDuration: 0.5, bounce: 0.3, initialSpringVelocity: 0, delay: 0, options: .beginFromCurrentState) { v.transform = t }
            }),
            ("spring bounce 0.6", .systemPink, { v, t in
                UIView.animate(springDuration: 0.5, bounce: 0.6, initialSpringVelocity: 0, delay: 0, options: .beginFromCurrentState) { v.transform = t }
            }),
            ("CASpringAnimation (layer)", .systemYellow, { v, t in
                let from = v.layer.presentation()?.affineTransform() ?? v.transform
                v.transform = t // model first…
                let spring = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.3)
                spring.keyPath = "transform.translation.x"
                spring.fromValue = from.tx
                spring.toValue = t.tx
                spring.duration = spring.settlingDuration
                v.layer.add(spring, forKey: "spring") // …then animate presentation from→to
            }),
        ]
        for (name, color, run) in demos {
            let label = UILabel()
            label.text = name
            label.font = Theme.mono(12, .medium)
            label.textColor = Theme.textSecondary
            let track = UIView()
            track.backgroundColor = UIColor.white.withAlphaComponent(0.05)
            track.layer.cornerRadius = 14
            track.heightAnchor.constraint(equalToConstant: 28).isActive = true
            let dot = UIView(frame: CGRect(x: 2, y: 2, width: 24, height: 24))
            dot.backgroundColor = color
            dot.layer.cornerRadius = 12
            track.addSubview(dot)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(track)
            stack.setCustomSpacing(4, after: label)
            curveDots.append((dot, run))
        }
        let button = ChipButton(title: "Run ▶︎ (tap again mid-flight to retarget)")
        button.addTarget(self, action: #selector(runCurves), for: .touchUpInside)
        stack.addArrangedSubview(button)
        stack.setCustomSpacing(36, after: button)
    }

    @objc private func runCurves() {
        curvesAtEnd.toggle()
        for (dot, run) in curveDots {
            let distance = (dot.superview?.bounds.width ?? 0) - dot.bounds.width - 4
            run(dot, curvesAtEnd ? CGAffineTransform(translationX: distance, y: 0) : .identity)
        }
    }

    // MARK: Interruptible fling

    private func buildFling() {
        header("Interruptible fling", "Throw the card — it projects your velocity to the nearest corner and springs there with that velocity. Grab it mid-flight: stopAnimation(true) leaves it exactly where it is.")
        flingArea.heightAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(flingArea)
        stack.setCustomSpacing(36, after: flingArea)
    }

    private var corners: [CGPoint] {
        let b = flingArea.bounds.insetBy(dx: 12 + pip.bounds.width / 2, dy: 12 + pip.bounds.height / 2)
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            flingAnimator?.stopAnimation(true) // catch it: model values snap to the current presentation values
            panStart = pip.center
            UIView.animate(springDuration: 0.25, bounce: 0) { self.pip.transform = CGAffineTransform(scaleX: 1.06, y: 1.06) }
        case .changed:
            let t = g.translation(in: flingArea)
            pip.center = CGPoint(x: panStart.x + t.x, y: panStart.y + t.y)
        case .ended, .cancelled:
            let v = g.velocity(in: flingArea)
            let projected = CGPoint(x: pip.center.x + Gesture.project(v.x), y: pip.center.y + Gesture.project(v.y))
            let target = corners.min { hypot($0.x - projected.x, $0.y - projected.y) < hypot($1.x - projected.x, $1.y - projected.y) }!
            let dx = target.x - pip.center.x, dy = target.y - pip.center.y
            let relative = CGVector(dx: abs(dx) > 1 ? v.x / dx : 0, dy: abs(dy) > 1 ? v.y / dy : 0)
            let animator = UIViewPropertyAnimator(duration: 0.6, timingParameters: UISpringTimingParameters(dampingRatio: 0.78, initialVelocity: relative))
            animator.addAnimations {
                self.pip.center = target
                self.pip.transform = .identity
            }
            animator.startAnimation()
            flingAnimator = animator
        default: break
        }
    }

    // MARK: Keyframes & symbol effects

    private func buildEffects() {
        header("Keyframes & SF Symbol effects", "CAKeyframeAnimation for an additive error shake; UIView.animateKeyframes for a choreographed sequence; addSymbolEffect (iOS 17) for free, system-tuned symbol motion.")
        let bell = UIImageView(image: UIImage(systemName: "bell.fill"))
        bell.tintColor = .systemYellow
        bell.preferredSymbolConfiguration = .init(pointSize: 34)
        bell.contentMode = .center
        let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
        heart.tintColor = .systemPink
        heart.preferredSymbolConfiguration = .init(pointSize: 34)
        heart.contentMode = .center
        let box = UIView()
        box.backgroundColor = Theme.accent
        box.layer.cornerRadius = 10
        box.widthAnchor.constraint(equalToConstant: 44).isActive = true
        box.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let icons = UIStackView(arrangedSubviews: [bell, heart, box])
        icons.distribution = .equalCentering
        icons.alignment = .center
        icons.heightAnchor.constraint(equalToConstant: 70).isActive = true
        stack.addArrangedSubview(icons)

        let shake = ChipButton(title: "Shake")
        shake.addAction(UIAction { _ in
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, -0.35, 0.3, -0.22, 0.15, -0.06, 0]
            a.duration = 0.6
            a.isAdditive = true
            bell.layer.add(a, forKey: "wiggle")
        }, for: .touchUpInside)
        let bounce = ChipButton(title: "Bounce")
        bounce.addAction(UIAction { _ in heart.addSymbolEffect(.bounce) }, for: .touchUpInside)
        let keyframes = ChipButton(title: "Keyframes")
        keyframes.addAction(UIAction { _ in
            UIView.animateKeyframes(withDuration: 1.0, delay: 0, options: [.calculationModeCubic]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) { box.transform = CGAffineTransform(translationX: 0, y: -24).rotated(by: .pi / 4) }
                UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.25) { box.transform = CGAffineTransform(scaleX: 1.3, y: 1.3).rotated(by: .pi / 2) }
                UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.25) { box.backgroundColor = Theme.yes }
                UIView.addKeyframe(withRelativeStartTime: 0.75, relativeDuration: 0.25) { box.transform = .identity; box.backgroundColor = Theme.accent }
            }
        }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [shake, bounce, keyframes])
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        stack.addArrangedSubview(buttons)
    }
}
