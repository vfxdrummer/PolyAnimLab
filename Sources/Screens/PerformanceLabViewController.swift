import UIKit

/// A deliberately "bad vs good" scrolling list to practice with Instruments.
/// Profile both modes with the Animation Hitches + Time Profiler templates while Auto-scroll runs.
final class PerformanceLabViewController: UIViewController, UICollectionViewDataSource {
    private var autoScroll: CADisplayLink?
    private var scrollDirection: CGFloat = 1
    private var unoptimized: Bool { modeControl.selectedSegmentIndex == 1 }

    private lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Optimized", "Unoptimized"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    private lazy var freezeItem: UIBarButtonItem = {
        UIBarButtonItem(title: "Freeze", style: .plain, target: self, action: #selector(freeze))
    }()

    private lazy var hudItem: UIBarButtonItem = {
        UIBarButtonItem(title: "HUD", style: .plain, target: self, action: #selector(toggleHUD))
    }()

    private lazy var autoScrollItem: UIBarButtonItem = {
        UIBarButtonItem(image: UIImage(systemName: "play.fill"), style: .plain, target: self, action: #selector(toggleAutoScroll))
    }()

    private lazy var layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.register(PerfCell.self, forCellWithReuseIdentifier: "cell")
        return collectionView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        title = "Perf Lab"
        view.backgroundColor = Theme.background
        navigationItem.titleView = modeControl
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = freezeItem
        navigationItem.rightBarButtonItems = [hudItem, autoScrollItem]
        collectionView.frame = view.bounds
        view.addSubview(collectionView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout.itemSize = CGSize(width: view.bounds.width - 32, height: 76)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAutoScroll()
    }

    @objc private func modeChanged() {
        Signposts.signposter.emitEvent("Mode changed")
        collectionView.reloadData()
    }

    @objc private func toggleHUD() {
        guard let scene = view.window?.windowScene else { return }
        HitchHUD.shared.toggle(in: scene)
    }

    /// A 400ms main-thread stall → shows up as a Hang in Instruments and as a giant hitch.
    @objc private func freeze() {
        Signposts.signposter.emitEvent("Freeze tapped")
        let state = Signposts.signposter.beginInterval("Freeze")
        Busy.spin(milliseconds: 400)
        Signposts.signposter.endInterval("Freeze", state)
    }

    // MARK: Auto-scroll (repeatable workload for A/B profiling)

    @objc private func toggleAutoScroll() {
        if autoScroll != nil { stopAutoScroll(); return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        autoScroll = link
        autoScrollItem.image = UIImage(systemName: "pause.fill")
    }

    private func stopAutoScroll() {
        autoScroll?.invalidate() // CADisplayLink retains its target; invalidate breaks the cycle
        autoScroll = nil
        autoScrollItem.image = UIImage(systemName: "play.fill")
    }

    @objc private func step(_ link: CADisplayLink) {
        let speed: CGFloat = 1800 // pt/s, frame-rate independent
        let dt = CGFloat(link.targetTimestamp - link.timestamp)
        var y = collectionView.contentOffset.y + speed * dt * scrollDirection
        let maxY = collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        let minY = -collectionView.adjustedContentInset.top
        if y >= maxY { y = maxY; scrollDirection = -1 }
        if y <= minY { y = minY; scrollDirection = 1 }
        collectionView.contentOffset.y = y
    }

    // MARK: Data source

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 1000 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! PerfCell
        cell.configure(index: indexPath.item, unoptimized: unoptimized)
        return cell
    }
}

enum Busy {
    static func spin(milliseconds: Double) {
        let end = CACurrentMediaTime() + milliseconds / 1000
        var x = 0.0
        while CACurrentMediaTime() < end { x += sin(x) }
        _ = x
    }
}

enum AvatarRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    static func render(emoji: String, hue: CGFloat, side: CGFloat, circular: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            if circular { UIBezierPath(ovalIn: rect).addClip() }
            let colors = [UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.8, brightness: 0.45, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            let font = UIFont.systemFont(ofSize: side * 0.5)
            let s = emoji as NSString
            let size = s.size(withAttributes: [.font: font])
            s.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: [.font: font])
        }
    }

    /// Pre-clipped, display-sized, cached: no per-frame masking, no oversized decode.
    static func cached(emoji: String, hue: CGFloat, side: CGFloat) -> UIImage {
        let key = "\(emoji)-\(side)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = render(emoji: emoji, hue: hue, side: side, circular: true)
        cache.setObject(image, forKey: key)
        return image
    }
}

final class PerfCell: UICollectionViewCell {
    private var unoptimized = false

    private lazy var card: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.card
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.6
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        return view
    }()

    private lazy var avatar: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(15, .semibold)
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(13)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.addSubview(card)
        card.addSubview(avatar)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            titleLabel.bottomAnchor.constraint(equalTo: card.centerYAnchor, constant: -1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: card.centerYAnchor, constant: 3),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = contentView.bounds
        // GOOD: an explicit shadowPath lets the render server skip computing the shadow shape
        // from the layer's alpha every frame (which costs an offscreen pass).
        card.layer.shadowPath = unoptimized ? nil : UIBezierPath(roundedRect: card.bounds, cornerRadius: 14).cgPath
    }

    func configure(index: Int, unoptimized: Bool) {
        let state = Signposts.signposter.beginInterval("ConfigureCell")
        defer { Signposts.signposter.endInterval("ConfigureCell", state) }

        self.unoptimized = unoptimized
        let markets = MarketSimulator.shared.markets
        let m = markets[index % markets.count]
        titleLabel.text = "#\(index)  \(m.title)"

        if unoptimized {
            // BAD 1: render a 600×600 image on the main thread for a 44pt view, every configure.
            avatar.image = AvatarRenderer.render(emoji: m.emoji, hue: m.hue, side: 600, circular: false)
            // BAD 2: runtime corner masking on the image view.
            avatar.layer.cornerRadius = 22
            avatar.layer.masksToBounds = true
            // BAD 3: a new NumberFormatter per cell (expensive to create).
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = Locale(identifier: "en_US")
            subtitleLabel.text = "\(f.string(from: NSNumber(value: m.volume)) ?? "") volume"
            // BAD 4: rasterize content that changes on reuse (cache thrash) at scale 1 (blurry on Retina!).
            card.layer.shouldRasterize = true
            // BAD 5: synchronous "work" on the main thread.
            Busy.spin(milliseconds: 4)
        } else {
            avatar.image = AvatarRenderer.cached(emoji: m.emoji, hue: m.hue, side: 44)
            avatar.layer.cornerRadius = 0
            avatar.layer.masksToBounds = false
            subtitleLabel.text = "\(Format.dollars(m.volume)) volume"
            card.layer.shouldRasterize = false
        }
        setNeedsLayout()
    }
}
