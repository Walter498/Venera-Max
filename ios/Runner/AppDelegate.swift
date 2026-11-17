import Flutter
import UIKit
import UniformTypeIdentifiers
import Foundation // 添加此行

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate, FlutterImplicitEngineDelegate {
  var flutterResult: FlutterResult?
  var directoryPath: URL!
  private var flutterRegistrar: FlutterPluginRegistrar?
  private var flutterViewController: FlutterViewController? {
    // The implicit engine attaches its controller after initialization.
    flutterRegistrar?.viewController as? FlutterViewController
  }

  // 定义插件通道名称
  private var directoryPicker: DirectoryPicker?
  // Scene delegates are held weakly by the engine.
  private let appShortcuts = AppShortcutBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let messenger = engineBridge.applicationRegistrar.messenger()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    NativeTabBarFactory.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "VeneraNativeTabBar"), messenger: messenger)
    ReadingWidgetBridge.register(messenger: messenger)
    flutterRegistrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "VeneraAppDelegate")
    FlutterEventChannel(
      name: "venera/notification_route",
      binaryMessenger: messenger
    ).setStreamHandler(appShortcuts)
    flutterRegistrar?.addSceneDelegate(appShortcuts)

    let methodChannel = FlutterMethodChannel(
      name: "venera/method_channel",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    methodChannel.setMethodCallHandler { (call, result) in
      if call.method == "getProxy" {
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?,
          let dict = proxySettings.object(forKey: kCFNetworkProxiesHTTPProxy) as? NSDictionary,
          let host = dict.object(forKey: kCFNetworkProxiesHTTPProxy) as? String,
          let port = dict.object(forKey: kCFNetworkProxiesHTTPPort) as? Int {
          let proxyConfig = "\(host):\(port)"
          result(proxyConfig)
        } else {
          result("")
        }
      } else if call.method == "setScreenOn" {
        if let arguments = call.arguments as? Bool {
          let screenOn = arguments
          UIApplication.shared.isIdleTimerDisabled = screenOn
        }
        result(nil)
      } else if call.method == "getDirectoryPath" {
        self.flutterResult = result
        self.getDirectoryPath()
      } else if call.method == "stopAccessingSecurityScopedResource" {
        self.directoryPath?.stopAccessingSecurityScopedResource()
        self.directoryPath = nil
        result(nil)
      } else if call.method == "selectDirectory" {
        self.directoryPicker = DirectoryPicker()
        self.directoryPicker?.selectDirectory(
          result: result,
          presenter: self.flutterViewController
        )
      } else if call.method == "supportsAlternateIcons" {
        result(UIApplication.shared.supportsAlternateIcons)
      } else if call.method == "setLauncherIcon" {
        // Alias name from CFBundleAlternateIcons, or nil/empty to restore the
        // primary icon. iOS shows its own "icon changed" alert; we deliberately
        // do not suppress it, since that requires a private selector.
        let args = call.arguments as? [String: Any]
        let alias = args?["alias"] as? String
        self.setAlternateIcon(alias?.isEmpty == false ? alias : nil, result: result)
      } else if call.method == "setAppShortcuts" {
        result(self.appShortcuts.publish(call.arguments))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

  }

  /// Swap the home-screen launcher icon to an alternate declared in
  /// CFBundleAlternateIcons. Reports false (not an error) when the device
  /// refuses, matching the Android handler's boolean contract.
  private func setAlternateIcon(_ alias: String?, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }
    UIApplication.shared.setAlternateIconName(alias) { error in
      // setAlternateIconName may call back off the main thread.
      DispatchQueue.main.async {
        if let error = error {
          NSLog("Venera: set launcher icon failed: \(error.localizedDescription)")
          result(false)
        } else {
          result(true)
        }
      }
    }
  }

  func getDirectoryPath() {
    guard let presenter = flutterViewController else {
      flutterResult?(nil)
      flutterResult = nil
      return
    }

    let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    documentPicker.directoryURL = nil
    documentPicker.modalPresentationStyle = .formSheet

    presenter.present(documentPicker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    self.directoryPath = urls.first
    if self.directoryPath == nil {
      flutterResult?(nil)
      return
    }

    let success = self.directoryPath.startAccessingSecurityScopedResource()

    if success {
      flutterResult?(self.directoryPath.path)
    } else {
      flutterResult?(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    flutterResult?(nil)
  }
}

/// UIKit-backed home navigation bar. Flutter embeds this view as a platform
/// view and only owns the selected page state; the pixels are produced by
/// Apple's UITabBar.
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private static let viewType = "venera/native_tab_bar"
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  static func register(
    with registrar: FlutterPluginRegistrar?,
    messenger: FlutterBinaryMessenger
  ) {
    guard let registrar else { return }
    registrar.register(
      NativeTabBarFactory(messenger: messenger),
      withId: viewType
    )
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class NativeBottomMaterialView: UIVisualEffectView {
  override func layoutSubviews() {
    super.layoutSubviews()
    let mask = (layer.mask as? CAGradientLayer) ?? CAGradientLayer()
    mask.frame = bounds
    mask.colors = [
      UIColor.clear.cgColor,
      UIColor.black.withAlphaComponent(0.38).cgColor,
      UIColor.black.cgColor,
    ]
    mask.locations = [0.0, 0.52, 1.0]
    mask.startPoint = CGPoint(x: 0.5, y: 0.0)
    mask.endPoint = CGPoint(x: 0.5, y: 1.0)
    layer.mask = mask
  }
}

final class NativeTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private static let symbols = [
    // Use SF Symbols with distinct silhouettes. In particular, avoid the
    // generic square glyphs that made the tab bar look like four tiles.
    "house", "house.fill",
    "books.vertical", "books.vertical.fill",
    "person.2", "person.2.fill",
    "rectangle.grid.2x2", "rectangle.grid.2x2.fill",
  ]

  private let container: UIView
  private let tabBar: UITabBar
  private let channel: FlutterMethodChannel
  private var bottomMaterial: NativeBottomMaterialView?

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    container = UIView(frame: frame)
    tabBar = UITabBar(frame: CGRect(
      x: 0,
      y: 0,
      width: frame.width,
      height: 64
    ))
    channel = FlutterMethodChannel(
      name: "venera/native_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear
    container.isOpaque = false
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.isOpaque = false
    // The Flutter platform view includes the home indicator inset. Let the
    // UIKit bar fill that whole frame so the inset cannot reveal a black
    // rectangle underneath the material.
    tabBar.frame = container.bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tabBar.items = Self.items(from: args)
    tabBar.selectedItem = tabBar.items?.first(where: {
      $0.tag == ((args as? [String: Any])?["selectedIndex"] as? Int ?? 0)
    })
    container.addSubview(tabBar)

    // iOS 26+ owns the Liquid Glass treatment for system tab bars. On
    // iOS 17–25, use a native masked material: the upper edge is transparent,
    // the material increases gradually toward the home-indicator edge, and no
    // opaque black rectangle is painted behind the page content.
    if #available(iOS 26.0, *) {
      tabBar.backgroundColor = nil
    } else {
      let material = NativeBottomMaterialView(
        effect: UIBlurEffect(style: .systemMaterial)
      )
      material.frame = container.bounds
      material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      material.isUserInteractionEnabled = false
      material.isOpaque = false
      bottomMaterial = material
      container.insertSubview(material, belowSubview: tabBar)

      let appearance = UITabBarAppearance()
      appearance.configureWithTransparentBackground()
      appearance.backgroundEffect = nil
      appearance.backgroundColor = .clear
      appearance.shadowColor = .clear
      tabBar.standardAppearance = appearance
      if #available(iOS 15.0, *) {
        tabBar.scrollEdgeAppearance = appearance
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      DispatchQueue.main.async {
        switch call.method {
        case "setSelectedIndex":
          let index = call.arguments as? Int ?? 0
          self.tabBar.selectedItem = self.tabBar.items?.first(where: {
            $0.tag == index
          })
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  static func items(from args: Any?) -> [UITabBarItem] {
    let labels = (args as? [String: Any])?["labels"] as? [String] ?? []
    return labels.enumerated().map { index, label in
      let symbolIndex = min(index * 2, symbols.count - 2)
      return UITabBarItem(
        title: label,
        image: UIImage(systemName: symbols[symbolIndex]),
        selectedImage: UIImage(systemName: symbols[symbolIndex + 1])
      )
    }.enumerated().map { index, item in
      item.tag = index
      return item
    }
  }

  func view() -> UIView {
    container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else {
      return
    }
    channel.invokeMethod("onTabSelected", arguments: index)
  }
}

/// Home-screen quick actions. A tap is sent to Dart as a route, the same way
/// Android and HarmonyOS deliver notification and shortcut taps.
final class AppShortcutBridge: NSObject, FlutterStreamHandler, FlutterSceneLifeCycleDelegate {
  private static let symbols = [
    "favorites": "star",
    "follow_updates": "bell.badge",
    "history": "clock.arrow.circlepath",
    "search": "magnifyingglass",
  ]
  private var sink: FlutterEventSink?
  // A cold-start tap arrives before Dart listens.
  private var pending: String?

  /// Arguments are `{route, label}` maps in display order.
  func publish(_ arguments: Any?) -> Bool {
    guard let items = arguments as? [[String: Any]] else { return false }
    UIApplication.shared.shortcutItems = items.compactMap { item in
      guard let route = item["route"] as? String,
        let symbol = Self.symbols[route],
        let label = item["label"] as? String, !label.isEmpty
      else { return nil }
      return UIApplicationShortcutItem(
        type: route,
        localizedTitle: label,
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(systemImageName: symbol),
        userInfo: nil
      )
    }
    return true
  }

  private func deliver(_ item: UIApplicationShortcutItem) -> Bool {
    guard Self.symbols[item.type] != nil else { return false }
    if let sink = sink {
      sink(item.type)
    } else {
      pending = item.type
    }
    return true
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    if let route = pending {
      pending = nil
      events(route)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let item = connectionOptions?.shortcutItem {
      _ = deliver(item)
    }
    // A shortcut launch carries no URL; leave the options to other delegates.
    return false
  }

  @objc(windowScene:performActionForShortcutItem:completionHandler:)
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) -> Bool {
    guard deliver(shortcutItem) else { return false }
    completionHandler(true)
    return true
  }
}
