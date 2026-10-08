import UIKit

/// Search tab, matched to a screen recording of the real app:
/// • Browse state: Categories chips (2 rows), Live tiles, MLB tiles, Futures cards.
/// • Focus: the field narrows as a ✕ slides in; keyboard rises.
/// • Typing: content swaps to a spinner; results land after a short debounce, rows fade up in a stagger,
///   and their icons arrive a beat later (like remote images).
/// • Clear / ✕: cross-fade back to browse.
final class SearchViewController: UIViewController, UITextFieldDelegate {
    private enum State { case browse, loading, results }

    private var state: State = .browse
    private var pendingSearch: DispatchWorkItem?
    private let debounce: TimeInterval = 0.6

    // MARK: Search field

    private lazy var fieldContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: 0x1A1D24)
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var magnifier: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        imageView.tintColor = Theme.textSecondary
        imageView.preferredSymbolConfiguration = .init(pointSize: 15, weight: .semibold)
        // Equal hugging with the text field lets Auto Layout stretch the icon instead of the field.
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var textField: UITextField = {
        let field = UITextField()
        field.attributedPlaceholder = NSAttributedString(string: "Search", attributes: [.foregroundColor: Theme.textSecondary])
        field.font = Theme.font(17)
        field.textColor = Theme.textPrimary
        field.tintColor = Theme.accent
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.keyboardAppearance = .dark
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
        button.tintColor = Theme.textSecondary
        button.alpha = 0
        button.addAction(UIAction { [weak self] _ in self?.clearText() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        button.tintColor = .white
        button.alpha = 0
        button.addAction(UIAction { [weak self] _ in self?.cancelSearch() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Two trailing constraints for the field: swapping them (inside an animation) narrows it for the ✕.
    private lazy var fieldTrailingRest: NSLayoutConstraint = {
        fieldContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
    }()

    private lazy var fieldTrailingFocused: NSLayoutConstraint = {
        fieldContainer.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8)
    }()

    // MARK: Content

    private lazy var browsePage: SearchBrowsePage = {
        let page = SearchBrowsePage()
        page.scrollView.keyboardDismissMode = .onDrag
        page.translatesAutoresizingMaskIntoConstraints = false
        return page
    }()

    private lazy var resultsPage: SearchResultsPage = {
        let page = SearchResultsPage()
        page.alpha = 0
        page.scrollView.keyboardDismissMode = .onDrag
        page.translatesAutoresizingMaskIntoConstraints = false
        return page
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.textSecondary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func setupViews() {
        view.backgroundColor = Theme.background
        [browsePage, resultsPage, spinner, fieldContainer, cancelButton].forEach(view.addSubview)
        [magnifier, textField, clearButton].forEach(fieldContainer.addSubview)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            fieldContainer.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            fieldContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldContainer.heightAnchor.constraint(equalToConstant: 46),
            fieldTrailingRest,

            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 40),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            magnifier.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 16),
            magnifier.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            textField.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            textField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            clearButton.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -6),
            clearButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 34),

            browsePage.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 8),
            browsePage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browsePage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browsePage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resultsPage.topAnchor.constraint(equalTo: browsePage.topAnchor),
            resultsPage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsPage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsPage.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 120),
        ])
    }

    // MARK: Focus

    func textFieldDidBeginEditing(_ textField: UITextField) { setFocused(true) }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func setFocused(_ focused: Bool) {
        fieldTrailingRest.isActive = !focused
        fieldTrailingFocused.isActive = focused
        UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: 0, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.cancelButton.alpha = focused ? 1 : 0
            self.view.layoutIfNeeded()
        }
    }

    // MARK: Typing

    @objc private func textChanged() {
        let query = textField.text ?? ""
        UIView.animate(withDuration: 0.15) { self.clearButton.alpha = query.isEmpty ? 0 : 1 }
        pendingSearch?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return show(.browse) }

        show(.loading)
        // Debounce: only "hit the network" once typing pauses.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resultsPage.reload(SearchIndex.search(query))
            self.show(.results)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func clearText() {
        textField.text = ""
        textChanged()
    }

    private func cancelSearch() {
        clearText()
        textField.resignFirstResponder()
        setFocused(false)
    }

    // MARK: State

    private func show(_ next: State) {
        guard next != state else { return }
        state = next
        next == .loading ? spinner.startAnimating() : spinner.stopAnimating()
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.browsePage.alpha = next == .browse ? 1 : 0
            self.resultsPage.alpha = next == .results ? 1 : 0
        }
        if next == .results { resultsPage.animateIn() }
    }
}

// MARK: - Browse page

final class SearchBrowsePage: HomePage {
    private let categories: [(String, String, UIColor)] = [
        ("MLB", "baseball.fill", .white), ("NFL", "football.fill", UIColor(hex: 0xC4552A)),
        ("Crypto", "bitcoinsign.circle.fill", Theme.bitcoin), ("Hockey", "hockey.puck.fill", UIColor(hex: 0xD0D4DA)),
        ("Tennis", "tennisball.fill", UIColor(hex: 0xA6D23A)), ("Golf", "figure.golf", Theme.yes),
        ("Motorsports", "car.side.fill", UIColor(hex: 0xC9CED6)), ("Cricket", "cricket.ball.fill", Theme.no),
        ("Basketball", "basketball.fill", UIColor(hex: 0xF97316)), ("Esports", "gamecontroller.fill", UIColor(hex: 0x8B5CF6)),
    ]

    /// Two rows of chips that scroll horizontally together.
    private lazy var categoryGrid: UIView = {
        let chips = categories.map { CategoryChip(title: $0.0, symbol: $0.1, tint: $0.2) }
        let half = (chips.count + 1) / 2
        let top = UIStackView(arrangedSubviews: Array(chips[..<half]))
        let bottom = UIStackView(arrangedSubviews: Array(chips[half...]))
        [top, bottom].forEach { $0.spacing = 8; $0.alignment = .leading }
        let rows = UIStackView(arrangedSubviews: [top, bottom])
        rows.axis = .vertical
        rows.spacing = 10
        rows.alignment = .leading
        let row = carousel([rows])
        row.heightAnchor.constraint(equalToConstant: 86).isActive = true
        return row
    }()

    private lazy var liveRow: UIView = {
        let row = carousel([
            LiveTile(status: "3rd Set", league: "ATP", competitors: [("🇺🇸", "Mackenzie McDonald", "1"), ("🇳🇱", "Ryan Nijboer", "1")]),
            LiveTile(status: "Map 2", league: "Esports", competitors: [("🐺", "Spirit", "1"), ("⚡️", "M80", "0")]),
            LiveTile(status: "2nd Set", league: "WTA", competitors: [("🇺🇸", "T. Townsend", "4"), ("🇰🇿", "Y. Putintseva", "6")]),
        ])
        row.heightAnchor.constraint(equalToConstant: 104).isActive = true
        return row
    }()

    private lazy var mlbRow: UIView = {
        let row = carousel(SportsSimulator.shared.games(league: "MLB").map { PopularTile(game: $0) })
        row.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return row
    }()

    private lazy var futuresRow: UIView = {
        carousel(SearchIndex.futures.map { FuturesCard(market: $0) }, spacing: 12)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        [
            inset(sectionTitle("Categories"), top: 12, bottom: 12),
            categoryGrid,
            inset(sectionTitle("Live"), top: 24, bottom: 12),
            liveRow,
            inset(sectionTitle("MLB  ›"), top: 24, bottom: 12),
            mlbRow,
            inset(sectionTitle("Futures"), top: 24, bottom: 12),
            futuresRow,
        ].forEach(contentStack.addArrangedSubview)
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = Section.header(text)
        label.font = Theme.font(17, .semibold)
        return label
    }
}

// MARK: - Results page

final class SearchResultsPage: HomePage {
    private var cards: [SearchResultCard] = []

    private lazy var countLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.font(17, .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No markets found"
        label.font = Theme.font(16)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        return label
    }()

    func reload(_ markets: [SearchMarket]) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        countLabel.text = "\(markets.count) Result\(markets.count == 1 ? "" : "s")"
        contentStack.addArrangedSubview(inset(countLabel, top: 12, bottom: 4))
        cards = markets.map { SearchResultCard(market: $0) }
        cards.forEach(contentStack.addArrangedSubview)
        if markets.isEmpty { contentStack.addArrangedSubview(inset(emptyLabel, top: 80)) }
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
    }

    /// Rows fade up in a short stagger; icons "load" a beat later, as remote images would.
    func animateIn() {
        layoutIfNeeded()
        for (i, card) in cards.prefix(8).enumerated() {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: 10)
            card.icon.alpha = 0
            card.lines.forEach { $0.badge.alpha = 0 }
            let delay = 0.03 * Double(i)
            UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: 0, delay: delay, options: [.allowUserInteraction]) {
                card.alpha = 1
                card.transform = .identity
            }
            UIView.animate(withDuration: 0.25, delay: 0.2 + delay, options: [.allowUserInteraction]) {
                card.icon.alpha = 1
                card.lines.forEach { $0.badge.alpha = 1 }
            }
        }
    }
}
