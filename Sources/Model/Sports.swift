import UIKit

struct Team {
    let name: String
    let city: String
    let monogram: String
    let color: UIColor
}

/// A two-sided sports market ("Game 4: LA Dodgers vs. ATL Braves").
struct Game {
    let id: Int
    let league: String
    let title: String
    let time: String
    let section: String
    let home: Team
    let away: Team
    var homeChance: Double   // 0...1, away = 1 - home
    let marketCount: Int

    func chance(for team: Team) -> Double { team.name == home.name ? homeChance : 1 - homeChance }
    var subtitle: String { "\(time) · \(league == "MLB" ? "Baseball" : "Football")" }
}

/// "BTC Up or Down" style rolling crypto market.
struct UpDownMarket {
    let title: String
    var secondsLeft: Int
    var upChance: Double
    var history: [Double]
}

extension Notification.Name {
    /// userInfo: ["id": Int]
    static let gameDidUpdate = Notification.Name("gameDidUpdate")
    static let upDownDidUpdate = Notification.Name("upDownDidUpdate")
}

/// Fake live feed for the Polymarket-style home screen.
final class SportsSimulator {
    static let shared = SportsSimulator()

    private(set) var games: [Game] = []
    private(set) var btc15m = UpDownMarket(title: "BTC Up or Down 15m", secondsLeft: 123, upChance: 0.05, history: [])
    private var timer: Timer?

    private init() {
        let t = Team.self
        let dodgers = t.init(name: "Dodgers", city: "LA", monogram: "LA", color: UIColor(hex: 0x1B81BE))
        let braves = t.init(name: "Braves", city: "ATL", monogram: "A", color: UIColor(hex: 0xC41050))
        let rays = t.init(name: "Rays", city: "TB", monogram: "TB", color: UIColor(hex: 0xF4F4F4))
        let yankees = t.init(name: "Yankees", city: "NY", monogram: "NY", color: UIColor(hex: 0x225891))
        let brewers = t.init(name: "Brewers", city: "MIL", monogram: "M", color: UIColor(hex: 0xC58E06))
        let padres = t.init(name: "Padres", city: "SD", monogram: "SD", color: UIColor(hex: 0x8C6E5D))
        let guardians = t.init(name: "Guardians", city: "CLE", monogram: "C", color: UIColor(hex: 0xD50032))
        let whiteSox = t.init(name: "White Sox", city: "CHI", monogram: "SOX", color: UIColor(hex: 0x6E7681))
        let bucs = t.init(name: "Buccaneers", city: "TB", monogram: "TB", color: UIColor(hex: 0xD50A0A))
        let cowboys = t.init(name: "Cowboys", city: "DAL", monogram: "★", color: UIColor(hex: 0x2B5BA8))
        let eagles = t.init(name: "Eagles", city: "PHI", monogram: "PHI", color: UIColor(hex: 0x0B6E5F))
        let jaguars = t.init(name: "Jaguars", city: "JAC", monogram: "JAX", color: UIColor(hex: 0x1F9AA6))
        let browns = t.init(name: "Browns", city: "CLE", monogram: "CLE", color: UIColor(hex: 0xE8590C))
        let jets = t.init(name: "Jets", city: "NY", monogram: "NYJ", color: UIColor(hex: 0x1E6B4F))
        let bengals = t.init(name: "Bengals", city: "CIN", monogram: "B", color: UIColor(hex: 0xFB4F14))
        let dolphins = t.init(name: "Dolphins", city: "MIA", monogram: "MIA", color: UIColor(hex: 0x1FA3A8))

        games = [
            Game(id: 0, league: "MLB", title: "Game 4: LA Dodgers vs. ATL Braves", time: "3:00 PM", section: "Today", home: dodgers, away: braves, homeChance: 0.57, marketCount: 347),
            Game(id: 1, league: "MLB", title: "Game 3: TB Rays vs. NY Yankees", time: "5:00 PM", section: "Today", home: rays, away: yankees, homeChance: 0.40, marketCount: 328),
            Game(id: 2, league: "MLB", title: "Game 4: MIL Brewers vs. SD Padres", time: "7:00 PM", section: "Today", home: brewers, away: padres, homeChance: 0.50, marketCount: 321),
            Game(id: 3, league: "MLB", title: "Game 3: CLE Guardians vs. CHI White Sox", time: "1:00 PM", section: "Today", home: guardians, away: whiteSox, homeChance: 0.46, marketCount: 412),
            Game(id: 10, league: "NFL", title: "TB Buccaneers vs. DAL Cowboys", time: "Oct 8 @ 5:15 PM", section: "Tomorrow", home: bucs, away: cowboys, homeChance: 0.20, marketCount: 718),
            Game(id: 11, league: "NFL", title: "PHI Eagles vs. JAC Jaguars", time: "Oct 11 @ 10:00 AM", section: "Sun, Oct 11", home: eagles, away: jaguars, homeChance: 0.24, marketCount: 654),
            Game(id: 12, league: "NFL", title: "CLE Browns vs. NY Jets", time: "Oct 11 @ 10:00 AM", section: "Sun, Oct 11", home: browns, away: jets, homeChance: 0.45, marketCount: 613),
            Game(id: 13, league: "NFL", title: "CIN Bengals vs. MIA Dolphins", time: "Oct 11 @ 10:00 AM", section: "Sun, Oct 11", home: bengals, away: dolphins, homeChance: 0.75, marketCount: 541),
        ]

        var p = 0.5
        btc15m.history = (0..<90).map { _ in
            p = min(0.97, max(0.03, p + Double.random(in: -0.05...0.04)))
            return p
        }
        btc15m.upChance = p
    }

    func game(id: Int) -> Game? { games.first { $0.id == id } }
    func games(league: String) -> [Game] { games.filter { $0.league == league } }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        // One game moves per second, like a trickle of fills.
        let i = Int.random(in: games.indices)
        let next = games[i].homeChance + Double.random(in: -0.03...0.03)
        games[i].homeChance = (min(0.97, max(0.03, next)) * 100).rounded() / 100
        NotificationCenter.default.post(name: .gameDidUpdate, object: nil, userInfo: ["id": games[i].id])

        btc15m.secondsLeft = btc15m.secondsLeft > 0 ? btc15m.secondsLeft - 1 : 899
        let up = min(0.97, max(0.03, btc15m.upChance + Double.random(in: -0.04...0.04)))
        btc15m.upChance = (up * 100).rounded() / 100
        btc15m.history.append(btc15m.upChance)
        if btc15m.history.count > 90 { btc15m.history.removeFirst() }
        NotificationCenter.default.post(name: .upDownDidUpdate, object: nil)
    }
}
