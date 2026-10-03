import CloudKit
import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security

@main
struct PassByApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = VaultSession.shared
    @StateObject private var account = TenonAccount.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(account)
                .tint(Palette.accent)
                .task { await session.prepare() }
                .task { await account.validateRestoredSession() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: session.didBecomeActive(); account.checkExpiry()
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
final class TenonAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TenonAccount()
    struct Identity: Codable {
        let issuer: String
        let sub: String
        let name: String
        let role: String
        let expires: Double
    }
    struct Grant: Codable { let token: String; let identity: Identity }
    @Published private(set) var identity: Identity?
    @Published private(set) var working = false
    @Published var message: String?
    private var browser: ASWebAuthenticationSession?
    private var token: String?
    private var generation = 0
    private let store: TenonSessionStore
    private let now: () -> Date
    private let transport: (URLRequest) async throws -> (Data, URLResponse)
    private var restored = false
    private let api = "https://tenon.asia/passby/api/auth/"

    init(store: TenonSessionStore = TenonSessionStore(), now: @escaping () -> Date = Date.init,
         transport: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.store = store; self.now = now; self.transport = transport
        super.init()
        guard let data = try? store.read() else { return }
        guard let grant = try? JSONDecoder().decode(Grant.self, from: data), valid(grant) else {
            try? store.clear(); return
        }
        token = grant.token; identity = grant.identity; restored = true
    }
    private func valid(_ grant: Grant) -> Bool {
        let time = now().timeIntervalSince1970 * 1000
        return grant.identity.issuer == "https://account.tenon.asia/api/auth"
            && !grant.identity.sub.isEmpty && ["admin", "user"].contains(grant.identity.role)
            && grant.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
            && grant.identity.expires.isFinite && grant.identity.expires > time
            && grant.identity.expires <= time + 60 * 1000
    }
    func validateRestoredSession() async {
        guard restored, let previous = token else { return }
        restored = false
        let attempt = generation
        var request = URLRequest(url: URL(string: api + "session")!)
        request.timeoutInterval = 10; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(previous)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await transport(request)
            guard generation == attempt, token == previous else { return }
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                try? store.clear(); token = nil; identity = nil; return
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            struct Result: Decodable { let identity: Identity }
            let current = try JSONDecoder().decode(Result.self, from: data).identity
            guard current.issuer == identity?.issuer, current.sub == identity?.sub,
                  current.expires == identity?.expires, valid(Grant(token: previous, identity: current)) else {
                try? store.clear(); token = nil; identity = nil; return
            }
            // Restoring never extends the original expiry or a central role.
            checkExpiry()
        } catch { checkExpiry() }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
        return base64(Data(bytes))
    }
    private func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func checkExpiry() {
        if let identity, identity.expires <= now().timeIntervalSince1970 * 1000 { self.identity = nil; token = nil; try? store.clear() }
    }
    func signIn() {
        guard !working else { return }
        VaultSession.shared.lock(); generation += 1
        let attempt = generation
        working = true; message = nil
        do {
            let verifier = try random(), state = try random()
            let challenge = base64(Data(SHA256.hash(data: Data(verifier.utf8))))
            var start = URLComponents(string: api + "start")!
            start.queryItems = [URLQueryItem(name: "platform", value: "ios"), URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "state", value: state)]
            let browser = ASWebAuthenticationSession(url: start.url!, callbackURLScheme: "passby") { [weak self] url, error in
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    self.browser = nil
                    guard error == nil, let url, url.scheme == "passby", url.host == "auth",
                          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          parts.queryItems?.filter({ $0.name == "state" }).count == 1,
                          parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
                          parts.queryItems?.filter({ $0.name == "ticket" }).count == 1,
                          let ticket = parts.queryItems?.first(where: { $0.name == "ticket" })?.value else {
                        self.working = false
                        if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { self.message = L("Tenon sign-in could not be completed. Please try again.") }
                        return
                    }
                    do {
                        var request = URLRequest(url: URL(string: self.api + "exchange")!)
                        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: ["ticket": ticket, "verifier": verifier, "state": state])
                        let (data, response) = try await self.transport(request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
                        let grant = try JSONDecoder().decode(Grant.self, from: data)
                        guard self.valid(grant) else { throw URLError(.badServerResponse) }
                        guard self.generation == attempt else { return }
                        try self.store.write(JSONEncoder().encode(grant))
                        self.token = grant.token; self.identity = grant.identity; self.restored = false
                    } catch { if self.generation == attempt { self.message = L("Tenon sign-in could not be completed. Please try again.") } }
                    if self.generation == attempt { self.working = false }
                }
            }
            browser.presentationContextProvider = self
            self.browser = browser
            if !browser.start() { self.browser = nil; working = false; message = L("Tenon sign-in could not be completed. Please try again.") }
        } catch { working = false; message = L("Tenon sign-in could not be completed. Please try again.") }
    }
    func signOut() {
        VaultSession.shared.lock(); generation += 1; browser?.cancel(); browser = nil; working = false
        do { try store.clear() }
        catch { message = L("Could not clear the saved sign-in. Please try again."); return }
        let previous = token; token = nil; identity = nil; message = nil; restored = false
        if let previous {
            Task {
                var request = URLRequest(url: URL(string: api + "logout")!)
                request.httpMethod = "POST"; request.setValue("Bearer \(previous)", forHTTPHeaderField: "Authorization")
                _ = try? await transport(request)
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

// Product identity only. Kept on this device, unavailable while locked, never
// synchronized or stored alongside notebook keys; reading does not bypass Face ID.
struct TenonSessionStore {
    var service = "cn.tenonai.apps.passby.tenon-session"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "product-session-v1", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> Data? {
        var request = query; request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.storageFailed }
        return data
    }
    func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw VaultError.storageFailed }
        } else if status != errSecSuccess { throw VaultError.storageFailed }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.storageFailed }
    }
}
