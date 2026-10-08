import UIKit

/// A fake-3D football helmet that spins around its vertical axis and lands on its back view
/// (where the logo decal lives) — modeled on the real app's launch animation.
///
/// How it fakes 3D cheaply:
///   • Four poses (back, right profile, front, left profile) are pre-rendered ONCE to bitmaps.
///   • A CADisplayLink advances the angle on an ease-out curve; each frame cross-fades the two
///     nearest poses and squashes the helmet slightly mid-turn to sell the rotation.
///   • The host layer is a CAReplicatorLayer: when spinning fast it draws trailing copies with
///     falling alpha → motion blur whose length tracks angular speed.
/// Per frame we only touch alpha + transforms, so the GPU just composites cached bitmaps.
final class HelmetSpinView: UIView {
    override class var layerClass: AnyClass { CAReplicatorLayer.self }

    var duration: CFTimeInterval = 0.62
    /// 1.75 turns: starts on the right profile (−3.5π ≡ π/2) and ends on the back view (0).
    var totalTurn: CGFloat = 3.5 * .pi

    private var replicator: CAReplicatorLayer { layer as! CAReplicatorLayer }
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    /// Order matters: index k is the pose at angle k × 90°.
    private lazy var poses: [UIImageView] = [
        HelmetSprites.back, HelmetSprites.rightProfile, HelmetSprites.front, HelmetSprites.leftProfile,
    ].map { image in
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: HelmetSprites.size)
        imageView.alpha = 0
        return imageView
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        bounds = CGRect(origin: .zero, size: HelmetSprites.size)
        isUserInteractionEnabled = false
        replicator.instanceCount = 1
        replicator.instanceAlphaOffset = -0.16
        poses.forEach(addSubview)
        render(angle: 0, speed: 0)
    }

    override var intrinsicContentSize: CGSize { HelmetSprites.size }

    // MARK: Spin

    func spin(completion: @escaping () -> Void) {
        self.completion = completion
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: LinkTarget(self), selector: #selector(LinkTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        render(angle: -totalTurn, speed: 0)
    }

    /// Static back view, e.g. for Reduce Motion.
    func showBackView() { render(angle: 0, speed: 0) }

    fileprivate func step(_ link: CADisplayLink) {
        // Sample at the time the frame will actually be shown, not when the callback fires.
        let x = min(1, (link.targetTimestamp - startTime) / duration)
        let remaining = pow(1 - x, 3)                      // ease-out cubic: e(x) = 1 − (1 − x)³
        let angle = -totalTurn * CGFloat(remaining)
        let speed = totalTurn * CGFloat(3 * pow(1 - x, 2) / duration) // dθ/dt, rad/s
        render(angle: angle, speed: speed)

        guard x >= 1 else { return }
        link.invalidate()
        self.link = nil
        render(angle: 0, speed: 0)
        completion?()
        completion = nil
    }

    private func render(angle: CGFloat, speed: CGFloat) {
        let quarter = CGFloat.pi / 2
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        let k = Int(a / quarter) % 4
        let f = (a - CGFloat(k) * quarter) / quarter
        let s = f * f * (3 - 2 * f) // smoothstep cross-fade between neighbouring poses
        for (i, pose) in poses.enumerated() {
            pose.alpha = i == k ? 1 - s : (i == (k + 1) % 4 ? s : 0)
        }

        let squash = 1 - 0.14 * abs(sin(2 * a))
        let trail = min(abs(speed) * 0.3, 11) // pt between blur copies

        CATransaction.begin()
        CATransaction.setDisableActions(true) // frame-driven: no implicit animations
        replicator.sublayerTransform = CATransform3DMakeScale(squash, 1, 1)
        replicator.instanceCount = trail > 0.5 ? 6 : 1
        replicator.instanceTransform = CATransform3DMakeTranslation(-trail, 0, 0)
        CATransaction.commit()
    }

    /// CADisplayLink retains its target; this breaks the cycle.
    private final class LinkTarget: NSObject {
        weak var view: HelmetSpinView?
        init(_ view: HelmetSpinView) { self.view = view }
        @objc func step(_ link: CADisplayLink) {
            guard let view else { link.invalidate(); return }
            view.step(link)
        }
    }
}

/// Pre-rendered helmet poses (rendered once, then cached by the static lets).
enum HelmetSprites {
    /// Poses are drawn in a 120×104 design space, scaled up to match the real helmet's on-screen size.
    private static let drawScale: CGFloat = 1.1
    static let size = CGSize(width: 120 * drawScale, height: 104 * drawScale)

    private static let shellLight = UIColor(red: 0.42, green: 0.60, blue: 1.00, alpha: 1)
    private static let shellBlue = UIColor(red: 0.13, green: 0.33, blue: 1.00, alpha: 1)
    private static let shellDark = UIColor(red: 0.04, green: 0.14, blue: 0.58, alpha: 1)
    private static let padding = UIColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1)

    static let back: UIImage = render { ctx in
        let dome = domePath()
        fillShell(dome, in: ctx, lightAt: CGPoint(x: 46, y: 26))
        padding.setFill()
        UIBezierPath(roundedRect: CGRect(x: 24, y: 80, width: 72, height: 13), cornerRadius: 6).fill()
        strokeWhite(lineWidth: 3) { p in
            p.move(to: CGPoint(x: 18, y: 82)); p.addLine(to: CGPoint(x: 26, y: 96))
            p.move(to: CGPoint(x: 102, y: 82)); p.addLine(to: CGPoint(x: 94, y: 96))
            p.move(to: CGPoint(x: 30, y: 96)); p.addLine(to: CGPoint(x: 90, y: 96))
        }
        crownHighlight()
        drawMark(center: CGPoint(x: 60, y: 47), scale: 1.15, in: ctx)
    }

    static let front: UIImage = render { ctx in
        fillShell(domePath(), in: ctx, lightAt: CGPoint(x: 46, y: 26))
        padding.setFill()
        UIBezierPath(roundedRect: CGRect(x: 30, y: 46, width: 60, height: 42), cornerRadius: 12).fill()
        strokeWhite(lineWidth: 3.5) { p in
            for y in [58.0, 70.0, 82.0] {
                p.move(to: CGPoint(x: 24, y: y)); p.addLine(to: CGPoint(x: 96, y: y))
            }
            for x in [44.0, 60.0, 76.0] {
                p.move(to: CGPoint(x: x, y: 50)); p.addLine(to: CGPoint(x: x, y: 92))
            }
            p.move(to: CGPoint(x: 24, y: 52))
            p.addCurve(to: CGPoint(x: 96, y: 52), controlPoint1: CGPoint(x: 22, y: 104), controlPoint2: CGPoint(x: 98, y: 104))
        }
        crownHighlight()
    }

    static let rightProfile: UIImage = render { ctx in
        // Profile drawn in a 140×120 design space, scaled into the sprite.
        ctx.cgContext.translateBy(x: 4, y: 4)
        ctx.cgContext.scaleBy(x: 0.8, y: 0.8)
        let shell = UIBezierPath()
        shell.move(to: CGPoint(x: 18, y: 96))
        shell.addCurve(to: CGPoint(x: 70, y: 8), controlPoint1: CGPoint(x: 2, y: 56), controlPoint2: CGPoint(x: 28, y: 10))
        shell.addCurve(to: CGPoint(x: 126, y: 54), controlPoint1: CGPoint(x: 106, y: 6), controlPoint2: CGPoint(x: 126, y: 28))
        shell.addLine(to: CGPoint(x: 126, y: 62))
        shell.addLine(to: CGPoint(x: 96, y: 62))
        shell.addLine(to: CGPoint(x: 92, y: 82))
        shell.addQuadCurve(to: CGPoint(x: 58, y: 102), controlPoint: CGPoint(x: 86, y: 102))
        shell.close()

        padding.setFill()
        let opening = UIBezierPath()
        opening.move(to: CGPoint(x: 96, y: 60)); opening.addLine(to: CGPoint(x: 128, y: 60))
        opening.addLine(to: CGPoint(x: 134, y: 100)); opening.addLine(to: CGPoint(x: 92, y: 102))
        opening.close()
        opening.fill()

        fillShell(shell, in: ctx, lightAt: CGPoint(x: 56, y: 26))
        padding.setFill()
        UIBezierPath(ovalIn: CGRect(x: 54, y: 54, width: 16, height: 16)).fill()
        UIBezierPath(roundedRect: CGRect(x: 30, y: 92, width: 50, height: 12), cornerRadius: 6).fill()

        strokeWhite(lineWidth: 4.5) { p in
            p.move(to: CGPoint(x: 96, y: 66)); p.addLine(to: CGPoint(x: 138, y: 68))
            p.addLine(to: CGPoint(x: 136, y: 100))
            p.addQuadCurve(to: CGPoint(x: 94, y: 104), controlPoint: CGPoint(x: 122, y: 112))
            p.move(to: CGPoint(x: 92, y: 84)); p.addLine(to: CGPoint(x: 137, y: 84))
            p.move(to: CGPoint(x: 116, y: 67)); p.addLine(to: CGPoint(x: 114, y: 104))
        }
        strokeWhite(lineWidth: 3.5, alpha: 0.85) { p in
            p.move(to: CGPoint(x: 46, y: 18)); p.addQuadCurve(to: CGPoint(x: 96, y: 16), controlPoint: CGPoint(x: 70, y: 4))
        }
    }

    static let leftProfile: UIImage = rightProfile.withHorizontallyFlippedOrientation()

    // MARK: Drawing helpers

    private static func render(_ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            ctx.cgContext.scaleBy(x: drawScale, y: drawScale)
            draw(ctx)
        }
    }

    private static func domePath() -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 14, y: 84))
        p.addCurve(to: CGPoint(x: 60, y: 6), controlPoint1: CGPoint(x: 6, y: 40), controlPoint2: CGPoint(x: 26, y: 6))
        p.addCurve(to: CGPoint(x: 106, y: 84), controlPoint1: CGPoint(x: 94, y: 6), controlPoint2: CGPoint(x: 114, y: 40))
        p.addQuadCurve(to: CGPoint(x: 14, y: 84), controlPoint: CGPoint(x: 60, y: 96))
        p.close()
        return p
    }

    /// Radial gradient (light → blue → dark) clipped to the shell gives the glossy 3D read.
    private static func fillShell(_ path: UIBezierPath, in ctx: UIGraphicsImageRendererContext, lightAt light: CGPoint) {
        let cg = ctx.cgContext
        cg.saveGState()
        path.addClip()
        let colors = [shellLight.cgColor, shellBlue.cgColor, shellDark.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
        cg.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: light, endRadius: 95,
                              options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    private static func crownHighlight() {
        strokeWhite(lineWidth: 3, alpha: 0.85) { p in
            p.move(to: CGPoint(x: 40, y: 16)); p.addQuadCurve(to: CGPoint(x: 80, y: 16), controlPoint: CGPoint(x: 60, y: 6))
        }
    }

    private static func strokeWhite(lineWidth: CGFloat, alpha: CGFloat = 1, _ build: (UIBezierPath) -> Void) {
        let p = UIBezierPath()
        build(p)
        p.lineWidth = lineWidth
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        UIColor.white.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }

    /// The logo mark decal (same geometry as scripts/render_launch_logo.swift).
    private static func drawMark(center: CGPoint, scale: CGFloat, in ctx: UIGraphicsImageRendererContext) {
        let cg = ctx.cgContext
        cg.saveGState()
        cg.translateBy(x: center.x - 14 * scale, y: center.y - 16 * scale)
        cg.scaleBy(x: scale, y: scale)
        strokeWhite(lineWidth: 3.2) { p in
            p.move(to: CGPoint(x: 2, y: 6)); p.addLine(to: CGPoint(x: 26, y: 1))
            p.addLine(to: CGPoint(x: 26, y: 31)); p.addLine(to: CGPoint(x: 2, y: 26)); p.close()
            p.move(to: CGPoint(x: 2, y: 6)); p.addLine(to: CGPoint(x: 26, y: 16)); p.addLine(to: CGPoint(x: 2, y: 26))
        }
        cg.restoreGState()
    }
}
