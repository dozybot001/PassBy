import CloudKit
import SwiftUI
import UIKit

@main
struct PassByApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = VaultSession.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(Palette.accent)
                .task { await session.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: session.didBecomeActive()
                    case .inactive: session.willResignActive()
                    case .background: session.didEnterBackground()
                    @unknown default: session.lock()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    session.accountChanged()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                    if UIScreen.main.isCaptured { session.lock() }
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = PrivacySceneDelegate.self
        return configuration
    }
}

@MainActor
final class PrivacySceneDelegate: NSObject, UIWindowSceneDelegate {
    private var shieldWindow: UIWindow?

    func sceneWillResignActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // UIKit installs an opaque window synchronously, before an app-switcher
        // snapshot. A SwiftUI blur alone can arrive after the snapshot is taken.
        if shieldWindow == nil {
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 1
            let controller = UIHostingController(rootView: PrivacyShield())
            controller.view.backgroundColor = UIColor(Palette.paper)
            window.rootViewController = controller
            shieldWindow = window
        }
        shieldWindow?.isHidden = false
        VaultSession.shared.willResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        VaultSession.shared.didEnterBackground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        VaultSession.shared.didBecomeActive()
        DispatchQueue.main.async { [weak self] in self?.shieldWindow?.isHidden = true }
    }
}
