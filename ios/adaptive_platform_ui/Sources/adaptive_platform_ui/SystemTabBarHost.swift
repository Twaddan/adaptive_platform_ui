import Flutter
import UIKit

/// iPhone Duo: Apple's own tab bar in the system's vertical bar (iOS 27.1).
///
/// On iPhone Duo (closed, or open in landscape) UIKit moves a tab bar
/// controller's tab bar into the vertical bar beside the camera, as Liquid
/// Glass with the lens that follows a finger along the tabs. It only does that
/// for a `UITabBarController` in the view controller hierarchy, never for a
/// Flutter view, so this adds one as a child of the Flutter view controller,
/// laid over the Flutter view. Its tabs are empty: Flutter keeps drawing every
/// page, the tab controller only supplies the bar and reports taps, and every
/// touch outside the bar goes through to Flutter.
///
/// The bar shows only while Dart asks for it and the system has a vertical
/// bar for this window, so it never shows up as a horizontal bar.
final class SystemTabBarHost: NSObject {
    private let registrar: FlutterPluginRegistrar
    private let channel: FlutterMethodChannel
    private var tabs: UITabBarController?
    private var holder: SystemTabBarHolderView?

    private var wanted = false
    private var items: [[String: Any]] = []
    private var selectedIndex = 0
    private var tint: UIColor = .systemBlue
    private var fontFamily = ""
    private var fontSize: CGFloat = 10
    private var registeredFonts = Set<String>()

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/system_tab_bar",
            binaryMessenger: registrar.messenger()
        )
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return result(nil) }
            switch call.method {
            case "update":
                self.update(call.arguments as? [String: Any] ?? [:])
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: Updates from Dart

    private func update(_ params: [String: Any]) {
        guard #available(iOS 18.0, *) else { return }
        wanted = params["visible"] as? Bool ?? false
        if let fonts = params["fontAssets"] as? [String] { registerFonts(fonts) }
        if let family = params["fontFamily"] as? String { fontFamily = family }
        if let size = params["fontSize"] as? NSNumber { fontSize = CGFloat(truncating: size) }
        if let argb = params["tint"] as? NSNumber { tint = Self.color(argb.intValue) }
        if let index = params["selectedIndex"] as? NSNumber { selectedIndex = index.intValue }
        let newItems = params["items"] as? [[String: Any]] ?? items

        // Nothing to set up until the bar is first wanted (only on iPhone Duo).
        if tabs == nil {
            guard wanted, install() else { return }
        }
        guard let tabs = tabs else { return }
        if !(newItems as NSArray).isEqual(to: items) || tabs.viewControllers?.count != newItems.count {
            items = newItems
            rebuildTabs(tabs)
        }
        applyAppearance(tabs)
        if selectedIndex >= 0, selectedIndex < (tabs.viewControllers?.count ?? 0),
            tabs.selectedIndex != selectedIndex
        {
            tabs.selectedIndex = selectedIndex
        }
        if let dark = params["isDark"] as? Bool {
            tabs.overrideUserInterfaceStyle = dark ? .dark : .light
        }
        applyVisibility(animated: true)
    }

    // MARK: Setup

    /// Adds the tab controller over the Flutter view. False when there is no
    /// Flutter view controller to attach to yet.
    @available(iOS 18.0, *)
    private func install() -> Bool {
        guard let flutter = registrar.viewController, flutter.isViewLoaded else { return false }
        let tabs = UITabBarController()
        tabs.delegate = self
        tabs.view.backgroundColor = .clear
        // Starts hidden, so it never flashes as a horizontal bar.
        tabs.setTabBarHidden(true, animated: false)

        let holder = SystemTabBarHolderView(frame: flutter.view.bounds)
        holder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.tabs = tabs
        holder.onTraitsOrLayoutChange = { [weak self] in self?.applyVisibility(animated: true) }

        flutter.addChild(tabs)
        tabs.view.frame = holder.bounds
        tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(tabs.view)
        flutter.view.addSubview(holder)
        tabs.didMove(toParent: flutter)

        self.tabs = tabs
        self.holder = holder
        return true
    }

    @available(iOS 18.0, *)
    private func rebuildTabs(_ tabs: UITabBarController) {
        tabs.setViewControllers(
            items.enumerated().map { index, item in
                let page = SystemTabPlaceholder()
                let selected = (item["selectedSymbol"] as? String).flatMap(Self.image)
                page.tabBarItem = UITabBarItem(
                    title: item["label"] as? String,
                    image: (item["symbol"] as? String).flatMap(Self.image),
                    // A selected icon of its own keeps its colours, as on the
                    // app's tab bar at the bottom.
                    selectedImage: selected?.withRenderingMode(.alwaysOriginal)
                )
                page.tabBarItem.tag = index
                return page
            },
            animated: false
        )
    }

    /// The same colours and font as the app's tab bar at the bottom of the
    /// phone, so both bars match.
    private func applyAppearance(_ tabs: UITabBarController) {
        let font = UIFont(name: fontFamily, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = .systemGray
        item.selected.iconColor = tint
        item.normal.titleTextAttributes = [.font: font, .foregroundColor: UIColor.systemGray]
        item.selected.titleTextAttributes = [.font: font, .foregroundColor: tint]
        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        tabs.tabBar.tintColor = tint
    }

    /// Shown only while Dart wants it and the system has a vertical bar here.
    private func applyVisibility(animated: Bool) {
        guard #available(iOS 18.0, *), let tabs = tabs, let holder = holder else { return }
        let edge = VerticalBarEdgeStreamHandler.edge(of: holder)
        let show = wanted && (edge == "left" || edge == "right")
        if show, let parent = holder.superview, parent.subviews.last !== holder {
            // Platform views Flutter added since may have gone on top.
            parent.bringSubviewToFront(holder)
        }
        if tabs.isTabBarHidden == show {
            tabs.setTabBarHidden(!show, animated: animated)
        }
    }

    // MARK: Helpers

    /// An SF Symbol, or an image of the app's asset catalog.
    private static func image(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        return UIImage(systemName: name) ?? UIImage(named: name)
    }

    /// Registers fonts bundled with Flutter so UIKit can use them by name.
    private func registerFonts(_ assets: [String]) {
        for asset in assets where !registeredFonts.contains(asset) {
            registeredFonts.insert(asset)
            let key = FlutterDartProject.lookupKey(forAsset: asset)
            guard let path = Bundle.main.path(forResource: key, ofType: nil) else { continue }
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
        }
    }

    private static func color(_ argb: Int) -> UIColor {
        UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}

extension SystemTabBarHost: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        selectedIndex = tabBarController.selectedIndex
        channel.invokeMethod("onTabSelected", arguments: ["index": selectedIndex])
    }
}

/// A tab's page: empty and clear, Flutter draws the content behind it.
private final class SystemTabPlaceholder: UIViewController {
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }
}

/// Holds the tab controller over the Flutter view. Touches on the bar go to the
/// bar; every other touch goes through to Flutter. Reports trait and layout
/// changes, so the bar can hide as soon as the system drops its vertical bar
/// (the phone opened in portrait).
private final class SystemTabBarHolderView: UIView {
    weak var tabs: UITabBarController?
    var onTraitsOrLayoutChange: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), hit !== self else { return nil }
        // A tab's empty page, or a container of the pages: not the bar.
        for page in tabs?.viewControllers?.compactMap({ $0.viewIfLoaded }) ?? []
        where hit === page || hit.isDescendant(of: page) || page.isDescendant(of: hit) {
            return nil
        }
        return hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onTraitsOrLayoutChange?()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        onTraitsOrLayoutChange?()
    }
}
