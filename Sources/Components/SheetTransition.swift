import UIKit

/// Custom bottom sheet presentation with:
/// - a dimming view driven alongside the transition,
/// - a spring presentation via UIViewPropertyAnimator,
/// - an interactive drag-to-dismiss that hands the finger's velocity to the dismissal spring,
///   so the sheet keeps moving at exactly the speed you flicked it.
final class SheetTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    /// Set by the sheet right before an interactive dismissal (points/sec).
    var dismissVelocity: CGFloat = 0

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        SheetPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SheetAnimator(presenting: true, velocity: 0)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        defer { dismissVelocity = 0 }
        return SheetAnimator(presenting: false, velocity: dismissVelocity)
    }
}

final class SheetPresentationController: UIPresentationController {
    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.alpha = 0
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addGestureRecognizer(dimmingTap)
        return view
    }()

    private lazy var dimmingTap: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
    }()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let fitting = presentedViewController.view.systemLayoutSizeFitting(
            CGSize(width: container.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = min(fitting.height + container.safeAreaInsets.bottom,
                         container.bounds.height - container.safeAreaInsets.top)
        return CGRect(x: 0, y: container.bounds.height - height, width: container.bounds.width, height: height)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimmingView.frame = container.bounds
        container.insertSubview(dimmingView, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.dimmingView.alpha = 1 })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.dimmingView.alpha = 0 })
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let v = presentedView else { return }
        // The sheet may carry a drag transform; setting `frame` with a transform is undefined.
        let f = frameOfPresentedViewInContainerView
        v.bounds = CGRect(origin: .zero, size: f.size)
        v.center = CGPoint(x: f.midX, y: f.midY)
    }

    func setDimming(_ progress: CGFloat) { dimmingView.alpha = max(0, min(1, progress)) }

    @objc private func dimmingTapped() { presentedViewController.dismiss(animated: true) }
}

final class SheetAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    let velocity: CGFloat

    init(presenting: Bool, velocity: CGFloat) {
        self.presenting = presenting
        self.velocity = velocity
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { presenting ? 0.55 : 0.4 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let duration = transitionDuration(using: ctx)
        if presenting {
            guard let toView = ctx.view(forKey: .to), let toVC = ctx.viewController(forKey: .to) else { return }
            ctx.containerView.addSubview(toView)
            toView.frame = ctx.finalFrame(for: toVC)
            toView.transform = CGAffineTransform(translationX: 0, y: toView.bounds.height)
            let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.84) { toView.transform = .identity }
            animator.addCompletion { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
            animator.startAnimation()
        } else {
            guard let fromView = ctx.view(forKey: .from) else { return }
            let current = fromView.transform.ty
            let target = fromView.bounds.height + 40
            // UIKit spring velocity is RELATIVE: (points/sec) / (total distance to travel).
            let distance = target - current
            let relative = distance > 1 ? velocity / distance : 0
            let timing = UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: 0, dy: relative))
            let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
            animator.addAnimations { fromView.transform = CGAffineTransform(translationX: 0, y: target) }
            animator.addCompletion { _ in
                if !ctx.transitionWasCancelled { fromView.removeFromSuperview() }
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            animator.startAnimation()
        }
    }
}

enum Gesture {
    /// Where a flick would come to rest (WWDC18 "Designing Fluid Interfaces").
    static func project(_ velocity: CGFloat, decelerationRate: CGFloat = UIScrollView.DecelerationRate.normal.rawValue) -> CGFloat {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// iOS-style rubber banding: resistance grows the further you pull.
    static func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        (1 - 1 / (offset * coefficient / limit + 1)) * limit
    }
}
