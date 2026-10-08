import UIKit

enum Theme {
    // Sampled from screen recordings of the real app.
    static let background = UIColor(hex: 0x0E1015)
    static let card = UIColor(hex: 0x191D24)
    static let sheet = UIColor(hex: 0x15181F)
    static let raised = UIColor(hex: 0x24272F)      // bell button, selected chips
    static let separator = UIColor.white.withAlphaComponent(0.06)
    static let border = UIColor.white.withAlphaComponent(0.07)
    static let textPrimary = UIColor.white
    static let textSecondary = UIColor(hex: 0x8A8F98)
    static let accent = UIColor(hex: 0x1A59FE)       // Deposit button
    static let yes = UIColor(hex: 0x22B24C)
    static let no = UIColor(hex: 0xE5303A)
    static let bitcoin = UIColor(hex: 0xF7931A)

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Monospaced digits keep every digit the same width so numbers don't "jiggle" as they change.
    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: textPrimary]
        nav.largeTitleTextAttributes = [.foregroundColor: textPrimary]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

enum Format {
    static func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }
    static func cents(_ p: Double) -> String { "\(Int((p * 100).rounded()))¢" }

    private static let dollars0: NumberFormatter = make(fraction: 0)
    private static let dollars2: NumberFormatter = make(fraction: 2)

    private static func make(fraction: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f
    }

    static func dollars(_ v: Double, cents: Bool = false) -> String {
        (cents ? dollars2 : dollars0).string(from: NSNumber(value: v)) ?? ""
    }

    static func volume(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return dollars(v)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Multiplies brightness — used for the darker "depth" edge under 3D pills.
    func darker(_ factor: CGFloat = 0.72) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
    }

    /// True when white text would be hard to read on this color (e.g. the Rays' white pill).
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.7
    }
}
