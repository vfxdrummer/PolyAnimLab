import UIKit

/// Launch splash, matched frame-by-frame to a screen recording of the real app.
///
/// Recording timeline (60 fps capture):
///   1.10–1.30s  static launch screen; the wordmark wipes away left → right, the mark stays
///   1.33s       the mark is replaced by a 3D helmet spinning very fast, heavy horizontal motion blur
///   1.33–1.90s  spin decelerates hard (ease-out) and lands on the helmet's BACK — logo decal facing us
///   1.90–2.17s  hold
///   2.17–2.30s  cross-fade straight into the app (no scale)
///
/// Seamless start: Info.plist `UILaunchScreen` shows the same color asset + the same `LaunchLogo` image,
/// centered the same way, so the swap from the static launch screen to this view is invisible.
///
/// Reduce Motion: no wipe/spin — hold the static frame briefly, then cross-fade.
final class HelmetLaunchView: UIView {
    /// Fallback if the asset is missing; matches LaunchBackground (sampled from the recording).
    static let brandBlue = UIColor(red: 0.106, green: 0.349, blue: 0.918, alpha: 1)

    /// x where the wordmark starts inside LaunchLogo (mark 28pt + 16pt gap).
    private let wordmarkStart: CGFloat = 44

    /// Same image the static launch screen shows (rendered by scripts/render_launch_logo.swift).
    private lazy var logo: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "LaunchLogo"))
        imageView.sizeToFit()
        imageView.layer.mask = logoMask
        return imageView
    }()

    /// Mask = solid block over the mark + a sliding soft-edged gradient over the wordmark.
    private lazy var logoMask: CALayer = {
        let layer = CALayer()
        layer.addSublayer(markMask)
        layer.addSublayer(wordmarkWipe)
        return layer
    }()

    private lazy var markMask: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        return layer
    }()

    /// Clear on the left half, opaque on the right, soft edge between. Sliding it right wipes the text away.
    private lazy var wordmarkWipe: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        // Laid out 2.4 × wordmark wide: clear for 1.0w, soft edge 0.2w, opaque for 1.2w.
        layer.locations = [0, 0.4167, 0.5, 1]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()

    private lazy var helmet: HelmetSpinView = {
        let view = HelmetSpinView()
        view.alpha = 0
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = UIColor(named: "LaunchBackground") ?? Self.brandBlue
        addSubview(logo)
        addSubview(helmet)
    }

    private var wordmarkWidth: CGFloat { logo.bounds.width - wordmarkStart }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The launch screen centers its image in the screen; do exactly the same.
        logo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        helmet.center = CGPoint(x: bounds.midX, y: bounds.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let h = logo.bounds.height
        markMask.frame = CGRect(x: 0, y: 0, width: wordmarkStart, height: h)
        // Starts with its opaque part exactly covering the wordmark.
        wordmarkWipe.frame = CGRect(x: wordmarkStart - 1.2 * wordmarkWidth, y: 0, width: 2.4 * wordmarkWidth, height: h)
        CATransaction.commit()
    }

    // MARK: Animation

    func play(completion: @escaping () -> Void) {
        layoutIfNeeded()
        guard !UIAccessibility.isReduceMotionEnabled else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.exit(completion: completion) }
            return
        }

        // 0.30s: wipe the wordmark away, left → right (0.22s). Model first, then explicit animation.
        let travel = 1.25 * wordmarkWidth // until the clear part covers the whole wordmark
        let wipe = CABasicAnimation(keyPath: "position.x")
        wipe.fromValue = wordmarkWipe.position.x
        wipe.toValue = wordmarkWipe.position.x + travel
        wipe.duration = 0.22
        wipe.beginTime = CACurrentMediaTime() + 0.30
        wipe.fillMode = .backwards
        wipe.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wordmarkWipe.position.x += travel
        CATransaction.commit()
        wordmarkWipe.add(wipe, forKey: "wipe")

        // 0.55s: the mark gives way to the spinning helmet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.logo.alpha = 0
            self.helmet.alpha = 1
            self.helmet.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            UIView.animate(springDuration: 0.35, bounce: 0) { self.helmet.transform = .identity }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.helmet.spin {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) // lands on the logo
                // Hold on the back view, then hand off to the app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { self.exit(completion: completion) }
            }
        }
    }

    private func exit(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in completion() }
    }
}
