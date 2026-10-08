import Foundation

enum Outcome {
    case yes, no
    var title: String { self == .yes ? "Yes" : "No" }
}

struct Market {
    let id: Int
    let title: String
    let emoji: String
    let hue: CGFloat
    var probability: Double
    var volume: Double
    var history: [Double]

    func price(for outcome: Outcome) -> Double { outcome == .yes ? probability : 1 - probability }
}

extension Notification.Name {
    /// userInfo: ["id": Int, "old": Double]
    static let marketDidUpdate = Notification.Name("marketDidUpdate")
}

/// Fake live data feed. Ticks one random market at a time, like a websocket price stream.
final class MarketSimulator {
    static let shared = MarketSimulator()

    private(set) var markets: [Market] = []
    private var timer: Timer?

    private init() {
        let seeds: [(String, String, CGFloat)] = [
            ("Fed cuts rates at the December meeting?", "🏦", 0.60),
            ("Will it snow in NYC on Christmas Day?", "❄️", 0.55),
            ("BTC above $150k on Dec 31?", "₿", 0.10),
            ("Lakers win the 2027 NBA Finals?", "🏀", 0.75),
            ("Foldable iPhone announced in 2027?", "📱", 0.85),
            ("Will SF get rain tomorrow?", "🌧️", 0.58),
            ("New Tarantino film released in 2027?", "🎬", 0.95),
            ("Mars sample return mission funded?", "🚀", 0.02),
            ("Taylor Swift album #13 by June?", "🎤", 0.88),
            ("World Cup 2026 final goes to penalties?", "⚽️", 0.33),
        ]
        markets = seeds.enumerated().map { i, seed in
            var p = Double.random(in: 0.2...0.8)
            var history: [Double] = []
            for _ in 0..<400 {
                p = min(0.98, max(0.02, p + Double.random(in: -0.015...0.015)))
                history.append(p)
            }
            return Market(id: i, title: seed.0, emoji: seed.1, hue: seed.2,
                          probability: (p * 100).rounded() / 100,
                          volume: Double.random(in: 50_000...25_000_000), history: history)
        }
    }

    func market(id: Int) -> Market? { markets.first { $0.id == id } }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let i = Int.random(in: markets.indices)
        var m = markets[i]
        let old = m.probability
        let next = min(0.99, max(0.01, m.probability + Double.random(in: -0.035...0.035)))
        m.probability = (next * 100).rounded() / 100
        m.volume += Double.random(in: 100...8_000)
        m.history.append(m.probability)
        if m.history.count > 400 { m.history.removeFirst() }
        markets[i] = m
        NotificationCenter.default.post(name: .marketDidUpdate, object: nil, userInfo: ["id": m.id, "old": old])
    }
}
