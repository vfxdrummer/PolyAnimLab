import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        MarketSimulator.shared.start()
        SportsSimulator.shared.start()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Theme.applyAppearance()
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.tintColor = Theme.accent
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window

        let splash = HelmetLaunchView(frame: window.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(splash)
        splash.play { splash.removeFromSuperview() }
    }
}

final class RootTabBarController: UITabBarController {
    private lazy var homeTab: UINavigationController = {
        makeTab(HomeViewController(), title: "Home", image: UIImage(systemName: "safari.fill"))
    }()

    private lazy var portfolioTab: UINavigationController = {
        makeTab(TabPlaceholderViewController(title: "Portfolio", symbol: "dollarsign.circle"), title: "Portfolio", image: Self.textIcon("$0"))
    }()

    private lazy var searchTab: UINavigationController = {
        makeTab(SearchViewController(), title: "Search", image: UIImage(systemName: "magnifyingglass"))
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        tabBar.tintColor = Theme.accent
        tabBar.unselectedItemTintColor = UIColor(hex: 0xA0A4AB)
        viewControllers = [homeTab, portfolioTab, searchTab]
    }

    private func makeTab(_ root: UIViewController, title: String, image: UIImage?) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        nav.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: nil)
        return nav
    }

    /// The real Portfolio tab shows your balance ("$0") as its icon.
    private static func textIcon(_ text: String) -> UIImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        let size = (text as NSString).size(withAttributes: attributes)
        return UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width), height: 24)).image { _ in
            (text as NSString).draw(at: CGPoint(x: 0, y: (24 - size.height) / 2), withAttributes: attributes)
        }.withRenderingMode(.alwaysTemplate)
    }
}
