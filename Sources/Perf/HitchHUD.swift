import UIKit

/// Floating FPS + hitch-time-ratio overlay (its own pass-through window, so it floats over sheets).
///
/// Hitch time ratio = ms of lateness per second of animation/scrolling (Apple's metric):
///   < 5 ms/s good · 5–10 warning · > 10 critical.
/// This is a main-thread CADisplayLink approximation. Instruments' Animation Hitches template
/// is the ground truth (it also sees render-server hitches this can't).
final class HitchHUD {
    static let shared = HitchHUD()

    private var window: UIWindow?

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.text = " -- fps "
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(dragGesture)
        return label
    }()

    private lazy var dragGesture: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    }()
    private var link: CADisplayLink?
    private var lastTarget: CFTimeInterval = 0
    private var sampleStart: CFTimeInterval = 0
    private var frames = 0
    private var hitchTime: CFTimeInterval = 0

    var isVisible: Bool { window?.isHidden == false }

    func toggle(in scene: UIWindowScene) { isVisible ? hide() : show(in: scene) }

    private func show(in scene: UIWindowScene) {
        if window == nil { window = makeWindow(scene) }
        window?.isHidden = false
        let proxy = DisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common) // .common so it keeps ticking during scroll tracking
        self.link = link
        lastTarget = 0
    }

    private func hide() {
        window?.isHidden = true
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTarget > 0 {
            // If this callback's frame was presented later than the previous callback predicted, we were late.
            let late = now - lastTarget
            if late > 0.0005 { hitchTime += late }
        } else {
            sampleStart = now
        }
        lastTarget = link.targetTimestamp
        frames += 1

        let elapsed = now - sampleStart
        guard elapsed >= 0.5 else { return }
        let fps = Double(frames) / elapsed
        let ratio = hitchTime * 1000 / elapsed
        label.text = String(format: " %3.0f fps · %4.1f ms/s ", fps, ratio)
        label.backgroundColor = (ratio < 5 ? UIColor.systemGreen : ratio < 10 ? .systemOrange : .systemRed).withAlphaComponent(0.85)
        frames = 0
        hitchTime = 0
        sampleStart = now
    }

    private func makeWindow(_ scene: UIWindowScene) -> UIWindow {
        let w = PassthroughWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        w.rootViewController = vc
        label.frame = CGRect(x: scene.screen.bounds.width - 170, y: 120, width: 160, height: 26)
        vc.view.addSubview(label)
        return w
    }

    @objc private func drag(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: label.superview)
        label.center.x += t.x
        label.center.y += t.y
        g.setTranslation(.zero, in: label.superview)
    }
}

/// CADisplayLink retains its target strongly — the classic retain-cycle trap. Break it with a weak proxy.
private final class DisplayLinkProxy: NSObject {
    weak var hud: HitchHUD?
    init(_ hud: HitchHUD) { self.hud = hud }
    @objc func tick(_ link: CADisplayLink) {
        guard let hud else { link.invalidate(); return }
        hud.tick(link)
    }
}

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === rootViewController?.view ? nil : hit
    }
}
