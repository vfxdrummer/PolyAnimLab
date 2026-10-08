# PolyAnim Lab — Technical Notes

Background on the UIKit animation and rendering techniques used in this project, with pointers to the code that demonstrates each one. For a screen-by-screen walkthrough of each animation, see [ANIMATIONS.md](ANIMATIONS.md).

**Contents**
1. The rendering pipeline
2. The layer tree: model vs presentation vs render
3. UIKit animation APIs, and when to use each
4. Core Animation toolbox
5. Springs, velocity, and fluid interfaces
6. Polish checklist
7. Rendering performance
8. Profiling with Instruments
9. Design principles
10. Matching a reference app frame by frame
11. Component reference
12. Further reading

---

## 1. The rendering pipeline

Every frame goes through:

1. **Event**: touches, timers, network callbacks, `CADisplayLink`. App code changes state.
2. **Commit** (in the app, on the main thread). Four sub-phases:
   - **Layout**: `layoutSubviews` and Auto Layout solving
   - **Display**: `draw(_:)`, text rendering, `CAShapeLayer` path rasterization prep
   - **Prepare**: image decoding and format conversion
   - **Commit**: the layer tree is packaged and sent over IPC to the render server
3. **Render prepare / render execute**, in the **render server** (a separate process): it compiles the layer tree into GPU work and the GPU draws it.
4. **Display**: the frame is swapped onto the screen.

Budget: **16.67 ms @ 60 Hz, 8.33 ms @ 120 Hz** (ProMotion). The pipeline is overlapped across frames, but **each phase must finish within its frame's deadline**.

**Hitch** = a frame shows up later than expected. Two kinds:
- **Commit hitch**: the main thread took too long (heavy `cellForItem`, layout thrash, synchronous image decode, JSON parsing, a big `reloadData`). Fix by doing less on the main thread, caching, or moving work off it.
- **Render hitch**: the render server or GPU couldn't finish (offscreen passes, too many blended layers, huge blurs, masks). Fix by simplifying the layer tree, adding `shadowPath`, avoiding masks, making layers opaque.

**Hitch time ratio** = ms of hitch per second of motion. Apple's guidance: **<5 ms/s good, 5–10 warning, >10 critical.** The app's HUD (`Perf/HitchHUD.swift`) approximates it. Instruments is the ground truth.

> Why Core Animation is fast: once an animation is committed, the **render server interpolates it every frame without the app's process**. A spring on `transform` keeps running smoothly even if the main thread blocks *after* the commit. Gesture-driven or display-link-driven animations stutter when the main thread blocks, because they need it every frame. Hence the rule: animate transform/opacity rather than doing frame-by-frame layout.

---

## 2. The layer tree: model vs presentation vs render

- **Model layer** (`layer.position`): the **target/final** value. This is what code sets.
- **Presentation layer** (`layer.presentation()`): what is **on screen right now** mid-animation (approximate, read-only).
- **Render tree**: private, lives in the render server.

Rules that follow:
- Adding a `CABasicAnimation` does **not** change the model. When it's removed, the layer snaps back to the model. The **correct pattern** (see `LiveChartView.morph`) is:
  1. `from = layer.presentation()?.value ?? layer.value` (handles interruption)
  2. set the model to the final value inside `CATransaction.setDisableActions(true)`
  3. add the explicit animation `from → to`
- **Anti-pattern:** `fillMode = .forwards` + `isRemovedOnCompletion = false` to "keep" the end state. The model and the screen then disagree, which breaks hit-testing and the next animation's start value.
- **Implicit animations:** a *standalone* `CALayer` animates property changes automatically (0.25 s) via `action(forKey:)`. A **view's backing layer does not**, because the `UIView` (as layer delegate) returns `NSNull` outside an animation block. Inside `UIView.animate`, UIView returns a real action, which is how UIKit animations work. (`ChanceGaugeView` uses the implicit strokeColor fade on purpose and disables it for geometry.)
- `CATransaction`: groups changes, sets duration/timing for implicit animations, provides a completion block, and `setDisableActions(true)` keeps scrubbing 1:1 with the finger (`LiveChartView.updateScrub`).
- Hit-testing uses the **model** frame. A view animating across the screen is tappable at its *destination* unless hit-testing uses `presentation()`.

**What happens when `UIView.animate` changes a view's position:** UIKit opens a CATransaction. Setting `center` updates the model layer's `position`, and the view (as the layer's delegate) returns a `CABasicAnimation`/`CASpringAnimation` action configured with the block's timing. At the end of the run loop, the transaction commits the layer tree and animation to the render server, which interpolates every frame independently of the app. The model is already at the final value, and the presentation layer reflects the in-flight value. Since iOS 8 UIKit animations are additive, so retargeting mid-flight blends smoothly.

---

## 3. UIKit animation APIs, and when to use each

| API | Use for | Notes |
|---|---|---|
| `UIView.animate(withDuration:…options:)` | simple fades/moves | curves `.curveEaseInOut`; `.beginFromCurrentState`, `.allowUserInteraction` |
| `UIView.animate(springDuration:bounce:initialSpringVelocity:…)` **(iOS 17)** | **default for UI motion** | `bounce` 0 = critically damped, no overshoot. Same model as SwiftUI `.spring(duration:bounce:)` |
| `UIView.animate(…usingSpringWithDamping:initialSpringVelocity:)` | legacy springs | dampingRatio 1 = no bounce |
| `UIViewPropertyAnimator` | **interruptible / scrubbable / reversible** | `pauseAnimation`, `fractionComplete`, `isReversed`, `continueAnimation(withTimingParameters:durationFactor:)`, `stopAnimation(true)` + `finishAnimation(at:)`, `pausesOnCompletion`, `scrubsLinearly`. States: `.inactive → .active → .stopped` |
| `UIView.animateKeyframes` | choreographed multi-step sequences | relative start/duration, `.calculationModeCubic` (Playground) |
| `UIView.transition(with:…crossDissolve)` | non-animatable changes (text, textColor, image) | used for label colors in `PillSegmentedControl` |
| Custom VC transitions | sheets, hero transitions | `UIViewControllerTransitioningDelegate`, `UIPresentationController`, `UIViewControllerAnimatedTransitioning`, `interruptibleAnimator(using:)`, `UIPercentDrivenInteractiveTransition` |
| `preferredTransition = .zoom { }` **(iOS 18)** | card → detail zoom | interactive and interruptible for free (v1 feed → detail in this app) |
| `imageView.addSymbolEffect(.bounce)` **(iOS 17)** | SF Symbol motion | `.bounce`, `.pulse`, `.variableColor`, `.replace`; iOS 18 adds `.wiggle`, `.breathe`, `.rotate` |
| `UIView.animate(_: SwiftUI.Animation)` **(iOS 18)** | share SwiftUI springs with UIKit | lets one motion design system serve both |
| `CADisplayLink` (or `UIUpdateLink`, iOS 18) | frame-driven custom work (physics, numeric tweening) | runs on the main thread every frame, so keep it tiny; set `preferredFrameRateRange` |

### UIViewPropertyAnimator
- **Interruptible:** a moving view can be grabbed mid-flight. `stopAnimation(true)` leaves properties at their *current* presentation values (Playground → fling).
- **Reversible:** `isReversed = true` runs back from wherever it is (`HoldToConfirmButton.release()`).
- **Scrubbable:** set `fractionComplete` from a gesture. On release, call `continueAnimation(withTimingParameters:durationFactor:)` with a spring carrying the gesture velocity.
- **Gotcha:** `fractionComplete` of a *spring* animator isn't linear in time. Set `scrubsLinearly`, and remember springs with velocity remap progress.
- **Gotcha:** an animator retained after completion has to be stopped before it's deallocated while active, or the app crashes.

### Custom transitions (see `Components/SheetTransition.swift` and `FullSheetPresentationController`)
- `UIPresentationController` owns chrome (dimming) and frames; the **animator** owns motion.
- Animate the dimming with `transitionCoordinator?.animate(alongsideTransition:)`.
- Interactive dismissal: drive `transform` from the pan, decide using the **projected** position, then hand the finger velocity to the dismissal spring.
- Never set `frame` on a transformed view. Use `bounds` + `center` (see `containerViewWillLayoutSubviews`).

---

## 4. Core Animation toolbox

- `CABasicAnimation`: `fromValue`/`toValue`/`byValue`, `timingFunction` (custom bezier via `controlPoints:`).
- `CASpringAnimation(perceptualDuration:bounce:)` **(iOS 17)**; set `duration = settlingDuration`, otherwise it gets cut off or idles.
- `CAKeyframeAnimation`: `values` + `keyTimes`, or a `path` (move along a curve). `calculationMode = .paced/.cubic`. Use `isAdditive = true` for shakes so they compose with the existing transform (`BetSlipViewController.reject`).
- `CAAnimationGroup`: run several key paths with one timing (`LiveChartView.startPulse`).
- `beginTime = CACurrentMediaTime() + delay` with `fillMode = .backwards` for staggered entrances (`animateDrawIn`).
- `CAShapeLayer`: `strokeStart`/`strokeEnd` draw-on effects; **path morphing requires the same number and type of path elements**, which is why `LiveChartView.resample` exists.
- `CAGradientLayer`, `CAReplicatorLayer` (motion blur in `HelmetSpinView`, loading dots, ripples), `CAEmitterLayer` (`Confetti`, where particles are simulated in the render server).
- **Layer `speed` / `timeOffset`**: set `speed = 0` and drive `timeOffset` to scrub a CA animation manually. Setting `window.layer.speed = 0.2` slows *everything* (Playground → Slow‑mo), which is useful for reviewing motion on a device.
- Infinite animations are **removed when the app backgrounds / the layer leaves the window**. Re-add them in `didMoveToWindow` or on foreground (`LiveChartView`, `UpDownCard`).
- Shape layers re-rasterize every frame while animating `path`. That's fine for one chart and not for 50 cells.

---

## 5. Springs, velocity, and fluid interfaces

Based on WWDC18 *Designing Fluid Interfaces*:

1. **Response:** react on touch-down, instantly (`PressableControl`: a quick, bounce-less press-down, then a bouncier release).
2. **Interruptible & redirectable:** any animation can be grabbed or retargeted. Never block input during motion (`.allowUserInteraction`).
3. **Preserve momentum:** hand the gesture's velocity to the spring.
4. **Project** the end position from the velocity: `projection = v/1000 * rate/(1-rate)`, with `rate = UIScrollView.DecelerationRate.normal` (0.998). See `Gesture.project`.
5. **Rubber band** at boundaries: `(1 - 1/(x*c/d + 1)) * d`, c ≈ 0.55 (`Gesture.rubberBand`).
6. Prefer **springs over fixed-duration curves**. A spring's duration emerges from the physics, and it can carry velocity.

**Relative velocity:** UIKit's `initialSpringVelocity` / `UISpringTimingParameters.initialVelocity` are **relative**: `points/sec ÷ total distance to travel`. A flick at 1500 pt/s with 300 pt left → `5`. Get it wrong and the hand-off either lurches or stalls.

Spring parameter models:
- `duration + bounce` (iOS 17, designer-friendly, perceptual)
- `dampingRatio + response` (SwiftUI's older API)
- `mass + stiffness + damping` (physics; duration is derived, and `UISpringTimingParameters(mass:stiffness:damping:initialVelocity:)` ignores the animator's duration)

---

## 6. Polish checklist

- **Haptics:** `UISelectionFeedbackGenerator` for detents and scrubbing (throttle it, see `i % 3` in `LiveChartView`), `UIImpactFeedbackGenerator` (light/medium/rigid with `intensity`), `UINotificationFeedbackGenerator` success/error. Call `prepare()` on touch-down to cut latency.
- **Numbers:** monospaced digits (`.monospacedDigitSystemFont`) so values don't jiggle; rolling digits with a right-to-left stagger (`RollingNumberView`). SwiftUI's equivalent is `.contentTransition(.numericText(value:))`.
- **Live data:** flash the change direction (green/red tint fading out, `MarketCell.flashChange`). Update the *visible cell directly*, never `reloadData` (that kills in-flight animations). Coalesce socket bursts down to the display rate.
- **Reduce Motion:** check `UIAccessibility.isReduceMotionEnabled` and swap translations/zooms for crossfades. Keep the information (color flashes) and drop the vestibular motion. (The launch animation respects it; the rest of the app doesn't yet.)
- **ProMotion (120 Hz):** UIKit/CA animations adapt automatically, but **custom `CADisplayLink`s and some CA animations cap at 60 Hz on iPhone unless `CADisableMinimumFrameDurationOnPhone` = YES** in Info.plist (set in `project.yml`). Use `preferredFrameRateRange` to *lower* the rate for slow ambient animations (the pulsing dot doesn't need 120 Hz, and lower saves battery). Low Power Mode caps at 60.
- **Timing:** press 100–200 ms, small UI 200–350 ms, sheets 400–550 ms. Exits are faster than entrances. Stagger items 20–40 ms.
- **Edges:** a sheet "skirt" so overshoot never reveals a gap; continuous corners (`cornerCurve = .continuous`); a dimming tap to dismiss; the grabber.
- **Reviewing motion:** slow-mo (`window.layer.speed`), Simulator → Debug → Slow Animations (⌘T), and screen recordings stepped frame by frame.

---

## 7. Rendering performance

**Offscreen rendering**: the GPU must render a layer subtree to a temporary texture before compositing it. It costs a render-pass switch every frame. Triggers:
- `shadow*` **without `shadowPath`**: the shape is derived from alpha each frame. **Fix:** set `shadowPath` (`PerfCell.layoutSubviews`).
- `layer.mask` / mask views (the gradient fill in the chart: acceptable once, not in 100 cells).
- `cornerRadius` + `masksToBounds` on layers *with content/sublayers*. Plain backgroundColor + cornerRadius is cheap. **Fix:** pre-clip the image (`AvatarRenderer.cached`) or set `cornerRadius` without masking.
- Group opacity (`allowsGroupOpacity` with alpha < 1 on a subtree), and `UIVisualEffectView` blurs (expensive by nature, so use sparingly).

**Blending**: every non-opaque layer stacked on another costs fill rate. Prefer opaque backgrounds and avoid alpha on large layers.

**Rasterization** (`shouldRasterize`): caches a subtree as a bitmap. A win **only** for complex, *static* content. The cache is limited and evicted when unused (~100 ms), so content that changes thrashes it. **Always set `rasterizationScale = UIScreen.main.scale`**, or it's blurry (Perf Lab "Unoptimized" shows both bugs).

**Images**: decoding a 4000×3000 JPEG into a 44 pt view burns CPU and memory on the main thread at commit. **Fix:** downsample with ImageIO (`CGImageSourceCreateThumbnailAtIndex`), or `UIImage.byPreparingThumbnail(ofSize:)` / `prepareForDisplay()` (iOS 15) off the main thread, and cache the result.

**Main thread**: Auto Layout in cells (prefer stable constraints, avoid constant activate/deactivate), text sizing, `NumberFormatter`/`DateFormatter` creation (cache them), and synchronous I/O.

**Lists**: `UICollectionView` prefetching, `reconfigureItems` (iOS 15) instead of `reloadItems` (it reuses the same cell), diffable data sources, and avoiding `reloadData` during animations.

---

## 8. Profiling with Instruments

**Always profile a Release build on a real device** (⌘I = Product → Profile). The simulator uses the Mac's GPU and CPU, so its numbers mean nothing.

### Templates
1. **Animation Hitches**: tracks *Hitches* (each with duration and type), *Commits*, *Renders*, *GPU*, *Display*, and *Frame Lifetimes*. Click a hitch to see whether the **commit** (main thread) or the **render** ran long, then look at the main thread's call stack in that window.
2. **Time Profiler**: CPU sampling. Use *Invert Call Tree* + *Hide System Libraries*, filter to the main thread, and select a time range around a hitch.
3. **Hangs** (included in Time Profiler/Animation Hitches): main thread unresponsive ≥250 ms (micro‑hang) or ≥500 ms (hang).
4. **Points of Interest / os_signpost**: custom intervals on the timeline. This app emits `ConfigureCell`, `Freeze`, and `Mode changed` (`Perf/Signposts.swift`). Use `OSSignposter.beginInterval/endInterval`. Mark custom animations with `os_signpost(.animationBegin, …)` so Instruments and XCTest attribute hitches to them.
5. **Allocations / Leaks**: retain cycles (a `CADisplayLink` retains its target, see `DisplayLinkProxy`), and transient image memory spikes.
6. **Core Animation** (FPS) / **Metal System Trace**: deeper GPU investigation.

### Visual debug flags
- Simulator: **Debug → Color Blended Layers / Color Offscreen-Rendered / Color Misaligned Images / Slow Animations**.
- On device: Xcode **Debug → View Debugging → Rendering →** the same color overlays.
- Xcode's View Debugger flags *layer optimization opportunities* (e.g. "shadow without path") as runtime issues.

### Regressions in CI, and data in production
- XCTest: `measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) { app.swipeUp(velocity: .fast) }` reports **hitch time ratio** and frame rate. Also `.scrollDraggingMetric` and `.navigationTransitionMetric`, plus custom metrics from animation signposts.
- MetricKit: `MXAnimationMetric.scrollHitchTimeRatio` from real users. Xcode Organizer shows hitch rate and hang rate per release.

### Perf Lab walkthrough
The Perf Lab (bell menu → Perf Lab) has an *Optimized* and an *Unoptimized* mode of the same list.
1. Connect a device, set the scheme to Release, and press ⌘I → **Animation Hitches**.
2. Perf Lab → *Optimized* → ▶︎ auto-scroll for 10 s. Then switch to *Unoptimized* and run another 10 s.
3. Compare the hitch counts. Click a hitch in the Unoptimized section and confirm that `PerfCell.configure` → `AvatarRenderer.render` / `Busy.spin` dominates the commit (a **commit hitch**).
4. Switch to **Time Profiler**, repeat, invert the call tree, and find the same symbols.
5. Tap **Freeze** and look for the Hang plus the `Freeze` signpost interval.
6. Turn on Color Offscreen-Rendered: Unoptimized cards turn yellow (shadow without path, mask), Optimized ones don't.
7. Fix one thing at a time, re-measure, and record the delta.

**Investigating a stuttering list, in order:** reproduce on a device with a Release build → Animation Hitches to split commit vs render hitches → Time Profiler around the commit hitches → offscreen/blending overlays for render hitches → signposts around cell configuration → fix the biggest item, re-measure, and lock it in with an XCTest scroll metric.

---

## 9. Design principles

- **Motion system:** named springs/durations (e.g. `Motion.snappy`, `.smooth`, `.bouncy`) shared by UIKit and SwiftUI (iOS 18 `UIView.animate(_: Animation)`), a haptics vocabulary, and Reduce Motion fallbacks built in.
- **Performance guardrails:** signposts on key interactions, XCTest hitch metrics in CI, MetricKit dashboards, and a "no offscreen rendering in cells" review rule.
- **Tuning with design:** prototype quickly, review in slow-mo, and tune parameters live (a debug menu with sliders for spring values works well).
- **Live-trading UIs:** high-frequency data → coalesce, throttle, diff. Visual stability (no layout jumps when numbers change). Trust: clear confirmation affordances (hold- or swipe-to-confirm, success states), and never animate in a way that misrepresents a price.
- **Corner radius and performance:** `cornerRadius` alone is cheap. `masksToBounds` with content or sublayers forces masking and may go offscreen, as do shadows without a path. Prefer pre-clipped images, `shadowPath`, and continuous corners on opaque backgrounds.

---

## 10. Matching a reference app frame by frame

App Store apps can't run in the Simulator, so reference interactions were captured on a device:
1. **Screen-record** each interaction (cold launch, category paging, opening the bet slip, amount entry, swipe to buy, search).
2. Extract frames (QuickTime, or `AVAssetImageGenerator` at a fixed step) and **step frame by frame**. At 60 fps a frame is 16.7 ms, so counting frames gives durations; look for overshoot (bounce) and staggering.
3. For each interaction note: trigger, duration, curve (overshoot?), what moves (opacity/scale/translate), haptic, and interruptibility.
4. Sample colors from full-resolution frames rather than eyeballing them.
5. Rebuild, record the Simulator (`xcrun simctl io booted recordVideo`), and compare the two frame sheets side by side.

These are approximations built from recordings, not measurements of the original implementation.

**Possible extensions:** Reduce Motion support across the app; a motion-tokens file plus a debug tuning panel; pull-to-refresh with a custom indicator; a skeleton shimmer loader (`CAGradientLayer` `locations` animation); tab bar icon symbol effects; coalescing price updates to the display rate with a `CADisplayLink`.

---

## 11. Component reference

| Piece | Where | Notes |
|---|---|---|
| Launch: wordmark wipe → spinning helmet → logo decal | `HelmetLaunchView`, `HelmetSpinView` | Seamless handoff from `UILaunchScreen` (same color asset + image). Fake 3D = 4 pre-rendered poses + `CADisplayLink` ease-out + `CAReplicatorLayer` motion blur scaled by angular speed. A production version would more likely ship a designer asset (Rive/Lottie/video). |
| Category bar highlight | `CategoryBar.setPagePosition` | The highlight is a *pure function of the pager's scroll offset*: swiping, decelerating and tap-to-jump share one code path, so it's interruptible and can't desync. A selection haptic fires on page-index change. |
| Nested scroll views | `HomeViewController.pager` | Two scroll views that both delay content touches swallow quick taps on controls in the inner one; only the inner vertical scroll view delays. |
| 3D percent pills | `PercentPill` | Face-on-base "key"; press = translate the face down (transform only, no shadow, no layout). Light colors (Rays) get dark text automatically. |
| Odds underline | `OutcomeRow.setUnderline` | Constraint multipliers are immutable → swap the constraint, then animate `layoutIfNeeded()` with a spring. Off-screen pages don't animate (`window != nil`). |
| Live data | `SportsSimulator`, `GameCardView` | Cells observe their own ID and update in place → no reload, in-flight springs retarget smoothly. |
| Bet slip presentation | `FullSheetPresentationController` | Presenter recedes (scale 0.92 + corner radius) alongside the transition; a single `setPresentedFraction` drives both the animated and the interactive (pull-down) paths. |
| Keypad | `KeyButton` | Instant-in / slow-out highlight bloom + soft haptic on touch-down: feels responsive before the finger lifts. |
| Swipe to buy | `BetSlipViewController.handleBuyPan` | Rubber band past the threshold, a haptic "detent" when arming/disarming, projection-based commit, velocity hand-off into the fly-away, success state + confetti. |
| Hit-testing | `swipeStack.isUserInteractionEnabled = false` | Labels layered *above* (not inside) the footer swallowed its pan until made non-interactive. |
| Gradient borders | `GradientBorderView` | Gradient layer masked by a stroked shape layer; it lays itself out because a parent's `layoutSubviews` runs before a stack view sizes its children. |
| Glow & shadows | `BuildComboButton`, `PromoBanner` | `shadowPath` for known shapes; for a static non-rect image glow, `shouldRasterize` at `UIScreen.main.scale` is the legitimate use. |
| Ticking price label | `RollingNumberView` | Monospaced digits plus per-digit columns animating `transform` with staggered springs. |
| Live chart | `LiveChartView` | CAShapeLayer resampled to a fixed point count so the path morphs, explicit `path` animation from the presentation value, pulse re-added on window attach, scrubbing with actions disabled plus selection haptics. |
| Search: focus | `SearchViewController.setFocused` | Two trailing constraints swapped inside one spring → the field narrows as the ✕ fades in; no frame math. |
| Search: typing | `textChanged` + `DispatchWorkItem` | Debounce (cancel + reschedule) so search only runs when typing pauses; explicit browse/loading/results state machine with 0.15 s cross-fades. |
| Search: results | `SearchResultsPage.animateIn` | Rows fade up in a 30 ms stagger; icons arrive ~0.2 s later like remote images, since progressive loading feels faster than one big pop. |
| Auto Layout priorities | magnifier / flag / score labels | Equal hugging priorities let Auto Layout stretch the wrong view (a giant magnifier); equal compression resistance truncated the score instead of the name. |

---

## 12. Further reading

WWDC sessions:
1. *Designing Fluid Interfaces* (WWDC18)
2. *Advanced Animations with UIKit* (WWDC17)
3. *Explore UI animation hitches and the render loop* (WWDC21 Tech Talk), plus *Find and fix hitches in the commit phase* and *…render phase*
4. *Animate with springs* (WWDC23)
5. *Enhance your UI animations and transitions* (WWDC24): zoom transitions, SwiftUI animations in UIKit
6. *Optimize your app's speed and efficiency* / *Analyze hangs with Instruments* (WWDC23)
