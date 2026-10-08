# How every animation in PolyAnim Lab works

A walkthrough of each animation in the app: what you see, how it's built step by step, the parameters it uses, and why it's built that way. For the underlying concepts (render server, model vs presentation layers, springs, hitches), see [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md).

**Contents**
- [Shared building blocks](#shared-building-blocks)
- [1. Launch](#1-launch)
- [2. Home](#2-home)
- [3. Market cards and odds](#3-market-cards-and-odds)
- [4. Bet slip](#4-bet-slip)
- [5. Search](#5-search)
- [6. v1 market demo](#6-v1-market-demo)
- [7. Playground](#7-playground)
- [8. Perf Lab and HUD](#8-perf-lab-and-hud)

---

## Shared building blocks

Several patterns show up repeatedly. They're explained once here.

### Springs everywhere
Almost every motion uses the iOS 17 spring API:

```swift
UIView.animate(springDuration: 0.45, bounce: 0.2, initialSpringVelocity: 0, delay: 0,
               options: [.allowUserInteraction, .beginFromCurrentState]) { … }
```

- `bounce: 0` means critically damped: no overshoot, used for "settling" motion.
- `bounce` 0.2–0.5 gives a visible overshoot, used for playful "release" motion.
- `.allowUserInteraction` keeps the view tappable mid-animation, so nothing is ever blocked.
- `.beginFromCurrentState` makes a new animation start from wherever the old one currently is, so rapid changes retarget smoothly instead of jumping.

### Asymmetric press / release
Buttons squish quickly with no bounce on touch-down, then spring back slower with bounce on release. Touch-down should feel *immediate*; release should feel *alive*.

| Control | Down | Up |
|---|---|---|
| `PressableControl` (Yes/No, chips, banners) | scale 0.96, 0.18 s, bounce 0 | identity, 0.5 s, bounce 0.45 |
| `PercentPill` | face moves down 3 pt, 0.12 s, bounce 0 | identity, 0.4 s, bounce 0.5 |
| Category icon | scale 0.88, 0.15 s | identity, 0.4 s, bounce 0.5 |
| v1 market card | scale 0.975, 0.2 s | identity, 0.45 s, bounce 0.35 |

All of them are driven by overriding `isHighlighted`, which UIKit toggles as the finger goes down, drags out, or lifts.

### Explicit Core Animation, done right
Every `CABasicAnimation` / `CASpringAnimation` in the app follows the same three steps:

```swift
let from = layer.presentation()?.strokeEnd ?? layer.strokeEnd  // 1. start from what's on screen
CATransaction.begin(); CATransaction.setDisableActions(true)
layer.strokeEnd = newValue                                     // 2. model = final value, no implicit animation
CATransaction.commit()
let a = CABasicAnimation(keyPath: "strokeEnd")                 // 3. animate from → to
a.fromValue = from; a.toValue = newValue
layer.add(a, forKey: "strokeEnd")
```

Because the model is set to the final value, nothing snaps back when the animation is removed. Because `from` comes from the presentation layer, an interrupted animation continues from where it visually is.

### Velocity hand-off
When a drag ends, the finger's speed is passed into the spring that finishes the motion. UIKit wants this as *relative* velocity:

```
relative velocity = finger speed (pt/s) ÷ distance left to travel (pt)
```

`Gesture.project(velocity)` predicts where a flick would come to rest (using the scroll view's deceleration rate), so decisions such as "dismiss or snap back?" are made on where the motion is *heading*, not where the finger happens to lift.

`Gesture.rubberBand(offset, limit:)` adds resistance past a boundary: `(1 − 1 / (x·0.55 / limit + 1)) · limit`.

### Haptics
Generators are created lazily and `prepare()`d on touch-down so the tap lands without latency. The vocabulary is:
- **selection:** detents and scrubbing
- **soft / light / rigid impact:** key presses and taps
- **medium impact:** crossing a commit threshold
- **success / error notification:** outcomes

---

## 1. Launch

**Files:** `HelmetLaunchView.swift`, `HelmetSpinView.swift`, `scripts/render_launch_logo.swift`

### What you see
The blue Polymarket launch screen. The wordmark wipes away, the mark turns into a 3D football helmet spinning with motion blur, it lands on the back of the helmet (where the logo decal is), and the app cross-fades in.

### Timeline (from the moment app code runs)

```
0.00  static frame: blue + logo, pixel-identical to the iOS launch screen
0.30  ├─ wordmark wipe, left → right (0.22 s, ease-in)
0.55  ├─ logo hidden, helmet appears (scale 0.85 → 1, light haptic)
0.55  ├─ spin: 1.75 turns, ease-out cubic (0.62 s)
1.17  ├─ lands on the back view (rigid haptic)
1.44  └─ splash fades out (0.15 s) → app
```

### Step 1: The invisible hand-off
Before any app code runs, iOS shows the static launch screen configured in Info.plist (`UILaunchScreen` → `LaunchBackground` colour + `LaunchLogo` image). The splash view uses **the same colour asset and the same image, centred the same way**, so the moment UIKit swaps the static screen for `HelmetLaunchView` is invisible. The logo image is rendered once by `scripts/render_launch_logo.swift`, so both sides are guaranteed identical.

### Step 2: The wordmark wipe
The logo is a single image, so the wipe is done with a **mask**:
- A solid black layer covers the mark (always visible).
- A `CAGradientLayer` covers the wordmark. It's 2.4 × the wordmark's width: clear on the left, a soft edge, opaque on the right. It starts positioned so the opaque part exactly covers the text.
- Animating the gradient's `position.x` to the right slides the clear part across, erasing the letters from left to right with a soft edge.

### Step 3: The fake-3D spin
There's no 3D model. `HelmetSpinView` fakes it:

1. **Four pre-rendered poses** (back, right profile, front, left profile) are drawn once with `UIGraphicsImageRenderer`. They're vector paths with a radial gradient for a glossy shell, and the logo decal is drawn on the back view.
2. A **`CADisplayLink`** fires every frame. For each frame it computes progress `x` (0 → 1 over 0.62 s, sampled at `targetTimestamp`, the time the frame will actually appear) and an ease-out cubic angle:
   ```
   angle = −3.5π · (1 − x)³       // starts at −3.5π ≡ right profile, ends at 0 = back
   speed = 3.5π · 3(1 − x)² / 0.62 // derivative, rad/s
   ```
3. The angle is mapped onto the poses: the two nearest poses are **cross-faded** with a smoothstep (`s = f²(3 − 2f)`), so profile → front → profile → back blends continuously.
4. The helmet is **squashed horizontally** mid-turn (`1 − 0.14·|sin 2θ|`) to sell the rotation.
5. **Motion blur:** the view's backing layer is a `CAReplicatorLayer`. While spinning fast it draws 6 copies, each shifted left by `min(speed × 0.3, 11)` pt and 16% more transparent. As the spin slows, the trail shrinks to nothing, so the blur is proportional to speed.

Per frame only alpha and transforms change, so the GPU just composites cached bitmaps.

### Step 4: Exit
After a 0.27 s hold on the back view, the whole splash fades out over 0.15 s and is removed.

**Reduce Motion:** the wipe and spin are skipped; the static frame holds for 0.6 s, then fades.

---

## 2. Home

**Files:** `HomeViewController.swift`, `CategoryBar.swift`, `HomePages.swift`, `FeedCards.swift`

### Category bar highlight follows your finger
**What you see:** swiping between Home / MLB / NFL… moves the rounded highlight behind the icons *continuously*, tracking your finger, and labels fade from grey to white.

**How it works:** the highlight has **no animation of its own**. On every `scrollViewDidScroll` of the horizontal pager, the controller calls:

```swift
categoryBar.setPagePosition(pager.contentOffset.x / pager.bounds.width)  // e.g. 1.4
```

`setPagePosition` linearly interpolates the highlight frame between the two neighbouring items (1.4 → 40% of the way from MLB to NFL) and blends each label's colour by its distance from that position.

Because the highlight is a pure function of the scroll offset, swiping, decelerating, paging snap, and tap-to-jump (`setContentOffset(animated: true)`) all move it through the **same code path**. It can't drift out of sync with the content, and it's interruptible for free. A selection haptic fires whenever the nearest page index changes, and the bar auto-scrolls to keep the selected item visible.

**Far jumps:** tapping a category more than one page away would fling through several pages, so instead the pager cross-fades (0.2 s `transitionCrossDissolve`) straight to the target.

### Quick taps inside the pager
The pills sit inside two scroll views (the horizontal pager and each page's vertical scroll). If both delay touches, quick taps get swallowed, so the pager sets `delaysContentTouches = false`. The inner page still delays, and the pager still cancels a control's touch once a horizontal swipe begins.

### BTC Up/Down card
- **Countdown:** a `RollingNumberView` (see §3) showing `mm:ss`, updated every second. Its stagger is 0, so all digits roll together.
- **Blinking live dot:** an infinite opacity animation (1 → 0.2, 0.8 s, autoreversing), capped at 30 fps with `preferredFrameRateRange` because background motion doesn't need 120 Hz. It's re-added in `didMoveToWindow` because Core Animation drops animations when a layer leaves the window.
- **Sparkline:** a `LiveChartView` with the fill hidden (see §6 for how the chart morphs and pulses).
- **Up/Down pills:** `PercentPill`s (see §3).

### League hero banner slider
When a league page settles on screen (`pageDidAppear`), the season-progress knob resets to 0 and springs to its position (0.9 s, bounce 0.2, 0.15 s delay). The fill bar and knob frames are computed from a single progress value inside the animation block, so they move together.

### Build a Combo glow
A static gradient capsule with a coloured shadow. The shadow uses an explicit `shadowPath`, so the glow is computed from a known shape instead of an offscreen render pass every frame. The gradient layer clips itself (`masksToBounds` on the gradient layer only), so the control's shadow isn't clipped.

### Promo banner ball glow
The tennis ball's glow is a shadow on a non-rectangular image, which can't use a simple `shadowPath`. Because the content never changes, it's rasterized once (`shouldRasterize` at `UIScreen.main.scale`), which is the legitimate use of rasterization.

---

## 3. Market cards and odds

**Files:** `RollingNumberView.swift`, `PercentPill.swift`, `OutcomeRows.swift`, `ChanceGaugeView.swift`, `SportsSimulator`

### Rolling numbers (odometer digits)
**What you see:** percentages, prices, and amounts roll digit by digit, the rightmost digit first.

**How it works:**
1. Each digit is a `DigitColumn`: a clipping view containing a vertical strip of labels `0…9`.
2. Showing digit *d* means translating the strip up by `d × digitHeight`. Changing digits animates only that `transform`, with a spring (0.55 s, bounce 0.2). The slight overshoot shows a sliver of the neighbouring digit, like a mechanical odometer.
3. Digits stagger from right to left by 25 ms each (`fromRight × stagger`).
4. Non-digits (`%`, `$`, `,`, `.`, `¢`) are static labels.
5. If the string's shape changes (for example `9%` → `10%`), the columns are rebuilt and each new digit column starts at the old digit in the same right-aligned position, then rolls to the new one.

Monospaced-digit fonts keep every digit the same width so nothing jiggles horizontally. Only transforms animate, so there's no layout work per frame.

### 3D percent pills
**What you see:** chunky team-coloured buttons that physically press down.

**How it works:** two stacked views.
- A **base** in a darker shade of the team colour, offset 4 pt down.
- A **face** in the team colour, sitting on top.

Pressing translates the face down by 3 pt so it sits on the base (0.12 s, no bounce); releasing springs it back (0.4 s, bounce 0.5). No shadow, no layout, just one transform. Light team colours (the Rays' white) get a grey base and dark text automatically.

### Odds underline
**What you see:** the thin coloured line under each team name grows or shrinks with its probability.

**How it works:** the underline's width is a constraint: `underline.width = track.width × chance`. Constraint multipliers are immutable, so on each price tick the old constraint is deactivated, a new one is activated with the new multiplier, and the layout pass is animated:

```swift
UIView.animate(springDuration: 0.6, bounce: 0.15, …) { self.layoutIfNeeded() }
```

The multiplier label (`1.7x` = 1 / chance) updates alongside.

### Live updates without reloads
`SportsSimulator` moves one random game's price every second and posts a notification with the game's ID. Each `GameCardView` / `PopularTile` observes it and **updates itself in place**: no `reloadData`, so in-flight springs retarget smoothly instead of restarting. Views that aren't on screen (`window == nil`) apply the new value without animating.

### Chance gauge (v1 cards)
A semicircle `CAShapeLayer`. The progress arc's `strokeEnd` is animated with a `CASpringAnimation(perceptualDuration: 0.6, bounce: 0.15)`, starting from the presentation value. Its colour changes via the layer's **implicit animation**: standalone layers animate property changes automatically, so setting `strokeColor` fades it for free, while geometry changes are wrapped in `setDisableActions(true)`.

---

## 4. Bet slip

**Files:** `BetSlipViewController.swift` (including `KeyButton`, `FullSheetPresentationController`), `SheetTransition.swift`, `Confetti.swift`

### Opening and closing
**What you see:** the slip slides up full-screen while the screen behind shrinks and rounds its corners. The team-coloured footer fades in once the slip lands.

**How it works:**
- A custom `UIPresentationController` owns the dimming view and the receding presenter. A custom animator owns the slip's motion.
- **Slip motion:** the view starts translated down by its own height, then a `UIViewPropertyAnimator` (0.55 s, damping ratio 0.84) brings it to identity.
- **Presenter recede:** alongside the transition, `setPresentedFraction(1)` scales the presenter to 0.92, rounds its corners to 38 pt, and fades in the dimming. Dismissal calls `setPresentedFraction(0)`.
- **Footer:** starts at alpha 0 and fades in over 0.25 s in `viewDidAppear`, with its label rising 10 pt, matching the reference recording where the colour only appears after landing.

### Pull down to dismiss
A pan on the panel (only starting on clearly downward drags) translates the whole slip with the finger and calls `setPresentedFraction(1 − offset/height)`. That one function drives **both** the animated and the interactive paths, so the presenter scales back up 1:1 with your finger. On release:
- If `offset + projected travel` is past 30% of the screen: dismiss, passing the finger velocity into the dismissal spring (damping 1, relative velocity), so the slip keeps moving at the speed you flicked it.
- Otherwise: spring back (0.5 s, bounce 0.15) carrying the finger's velocity.

### Keypad keys
Each `KeyButton` has a rounded "bloom" behind its glyph:
- **Down:** the bloom appears almost instantly (0.06 s) at scale 1.05, the glyph shrinks to 0.9, and a soft haptic fires on touch-down.
- **Up:** the bloom fades out slowly (0.35 s) while shrinking to 0.85.

Instant-in, slow-out makes the key feel responsive before your finger even lifts.

### The amount
- The big number is a `RollingNumberView`. Empty input shows a dim `$0`; any amount turns it white.
- **Pop:** on every change the label's transform jumps to scale 1.07, then springs back to identity (0.45 s, bounce 0.45). Setting the starting value outside the animation and the end value inside it creates the pop.
- **"to win":** fades in and slides into place (spring 0.4 s, bounce 0.1) the first time an amount is entered; its value is a second rolling number with a faster stagger (15 ms).
- **Footer label swap:** "Choose an amount" slides up and out as "Swipe to buy …" slides up and in, in the same spring.
- **Rejected input** (over the $250 balance, a third decimal, deleting from empty): an additive `CAKeyframeAnimation` on `transform.translation.x` (`0, −14, 11, −8, 5, −2, 0` over 0.4 s) plus an error haptic. Additive means the shake composes with whatever transform the label already has.

### Swipe to buy
**What you see:** drag the coloured footer up and the panel follows your finger; past a point you feel a click; release and the panel flies away, a ✓ "Bought …" springs in, and confetti bursts.

**How it works:**
1. **Tracking:** a pan on the footer moves the panel up 1:1 with the finger until 120 pt (the commit threshold), then with rubber-band resistance (`rubberBand(travel − 120, limit: 60)`). The "Swipe to buy" label drifts up at 45% of the panel's travel for a layered parallax feel.
2. **Haptic detent:** crossing 120 pt fires a medium impact at full intensity ("armed"); backing off fires a half-intensity one ("disarmed"). You can feel exactly when releasing will buy.
3. **Decision:** on release, if `travel + projected travel` passes the threshold, it commits; otherwise the panel springs back (0.5 s, bounce 0.3) with the finger's velocity.
4. **Fly-away:** a `UIViewPropertyAnimator` (damping ratio 1, 0.5 s) moves the panel off the top, seeded with the finger's relative velocity (capped) so the motion continues seamlessly from the swipe. The footer colour now fills the screen.
5. **Success:** the ✓ stack starts at scale 0.6 and springs in (0.55 s, bounce 0.45, 0.15 s delay). A success haptic fires immediately.
6. **Confetti** at 0.25 s, then the slip dismisses at 1.6 s.

The labels over the footer are `isUserInteractionEnabled = false`: they sit *above* the footer rather than inside it, and would otherwise swallow the footer's pan.

### Confetti
A one-shot `CAEmitterLayer` with 5 cells (green, blue, yellow, pink, white rectangles), each emitting 70/s upward in a ±60° cone at 420 ± 160 pt/s with gravity (`yAcceleration` 600), spin, and fade. Its `birthRate` is set to 0 after 0.12 s (a burst, not a fountain), and it's removed after 3.5 s. Setting `beginTime = CACurrentMediaTime()` stops the emitter from "pre-warming" as if it had been running since time 0. Particles are simulated in the render server, so hundreds of them cost the main thread nothing.

---

## 5. Search

**Files:** `SearchViewController.swift`, `SearchComponents.swift`

### Focus: the field narrows as ✕ appears
The search field has two trailing constraints: one to the screen edge and one to the ✕ button. Focusing swaps which one is active and animates the layout pass together with the ✕ fading in (spring 0.35 s, bounce 0). There's no frame math: Auto Layout computes both end states.

### Typing: debounce and states
The screen is a small state machine: **browse → loading → results**.
- Every keystroke cancels the pending search (`DispatchWorkItem.cancel()`) and schedules a new one 0.6 s later. Search only runs once typing pauses, like a network request would.
- While waiting, the spinner shows and the other content fades out.
- State changes cross-fade the browse and results layers (0.15 s). Clearing the text (✕ in the field, or the cancel ✕) returns to browse.

### Results entrance
**What you see:** result cards fade up one after another; their icons and badges appear a beat later.

**How it works:** for the first 8 cards:
- Each starts at alpha 0, 10 pt lower, then springs in (0.4 s, bounce 0) with a 30 ms stagger per card.
- Each card's icon and badges start at alpha 0 and fade in over 0.25 s starting 0.2 s later, the way remote images would arrive.

Progressive loading feels faster than one big pop, and staggering gives the eye a reading order.

---

## 6. v1 market demo

**Files:** `MarketFeedViewController.swift`, `MarketDetailViewController.swift`, `LiveChartView.swift`, `PillSegmentedControl.swift`, `BetSheetViewController.swift`, `HoldToConfirmButton.swift` (bell menu → v1 Market Demo)

### Price flash on cards
When a card's price changes, a full-card overlay is set to green or red at alpha 0.16 and fades to 0 over 0.9 s (ease-out). Because the starting alpha is set outside the animation block, each tick restarts the flash cleanly.

### Card → detail zoom (iOS 18)
`preferredTransition = .zoom { … }` on the detail controller, with a closure that returns the tapped card. The closure is called lazily, so if the list scrolled, it finds the card's current view. The system provides an interactive, interruptible zoom for free.

### Live chart
- **Path morphing:** the price history is resampled to a fixed 120 points, so every path has the same number of elements; then the `CAShapeLayer`'s `path` animates from its presentation value to the new path (0.5 s, timing curve `0.25, 1, 0.5, 1`). The end dot's `position` animates with the same timing.
- **Draw-in:** on first appearance, `strokeEnd` animates 0 → 1 (0.9 s); the gradient fill fades in from 0.35 s; the dot pops in with a spring at 0.75 s. Delayed parts use `beginTime` plus `fillMode = .backwards` so they stay invisible until their turn.
- **Pulse:** a `CAAnimationGroup` (scale 1 → 3.2, opacity 0.55 → 0, 1.6 s, repeating forever) on a ring behind the dot, re-added on window attach and app foreground.
- **Scrubbing:** a long press moves a vertical line and a dot to the nearest point inside `setDisableActions(true)`, so they track the finger 1:1 with no implicit 0.25 s lag. A selection haptic fires every third point, and the big number above rolls to the scrubbed value.

### Range selector pill
The selected-segment indicator's frame and background colour animate in one spring (0.45 s, bounce 0.22). Label colours aren't animatable, so they cross-dissolve with `UIView.transition`.

### Bottom sheet (v1 bet sheet)
A custom presentation like the full-screen slip: spring up (damping 0.84), drag to dismiss with rubber banding when pulling up, projection-based decisions, and velocity hand-off. A "skirt" view extends below the sheet so the spring's overshoot never reveals a gap.

### Hold to confirm
**What you see:** holding fills the button; letting go early drains it from wherever it got to; re-pressing resumes filling.

**How it works:** one `UIViewPropertyAnimator` (linear, 0.9 s) scales the fill's X from 0.001 to 1. Its anchor point is the leading edge, so it grows from the left.
- **Release early:** pause, set `isReversed = true`, continue with a critically damped spring at 0.45× the duration, so it drains back quickly from its current point.
- **Re-press mid-drain:** pause, `isReversed = false`, continue linearly.
- **Completion:** at the end position, the label slides up and fades, the checkmark springs in from scale 0.4 (bounce 0.5), and a success haptic fires.

The scale starts at 0.001 rather than 0, because a zero scale isn't invertible and breaks hit-testing and the animation maths.

---

## 7. Playground

**File:** `PlaygroundViewController.swift` (bell menu → Animation Playground)

- **Timing curves:** five dots move the same distance with different timing: ease-in-out 0.5 s, and springs with bounce 0, 0.3 and 0.6, plus a layer-level `CASpringAnimation`. Tapping Run again mid-flight retargets them, which shows that springs with `.beginFromCurrentState` redirect smoothly while curves restart.
- **Interruptible fling:** dragging the card moves it 1:1. On release, the predicted landing point picks the nearest corner, and a `UIViewPropertyAnimator` spring (damping 0.78) takes it there, seeded with the finger's relative velocity. Grabbing it mid-flight calls `stopAnimation(true)`, which leaves it exactly where it visually is.
- **Keyframes and symbol effects:** an additive `transform.rotation.z` keyframe wiggle on the bell, `addSymbolEffect(.bounce)` on the heart, and a four-step `UIView.animateKeyframes` sequence (lift and rotate, scale, recolour, return) with cubic interpolation.
- **Slow-mo:** setting `window.layer.speed = 0.2` slows every animation in the window: UIKit, Core Animation and property animators. Useful for reviewing motion on a device.

---

## 8. Perf Lab and HUD

**Files:** `PerformanceLabViewController.swift`, `HitchHUD.swift`, `Signposts.swift` (bell menu → Perf Lab / Toggle Hitch HUD)

- **Auto-scroll:** a `CADisplayLink` moves the list at 1800 pt/s, using `targetTimestamp − timestamp` as the frame's time step so the speed is the same at 60 or 120 Hz. This gives a repeatable workload for comparing the Optimized and Unoptimized modes in Instruments.
- **Freeze:** spins the main thread for 400 ms inside a signpost interval, producing a visible hang and hitch on purpose.
- **Hitch HUD:** a separate pass-through `UIWindow` above everything, with a `CADisplayLink` that compares each frame's actual `timestamp` to the previous frame's `targetTimestamp`. Any lateness is added up as hitch time and shown twice a second as fps and ms-per-second, coloured green (<5), orange (5–10) or red (>10). The display link reaches the HUD through a weak proxy, because `CADisplayLink` retains its target.
