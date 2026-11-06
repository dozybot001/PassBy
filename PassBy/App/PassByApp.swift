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
                    case .active:
                        session.didBecomeActive()
                        Task { await account.didBecomeActive() }
                        Task { await account.chooseService() }
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

// Web pages live on the service host that answered, so links move with the API.
@MainActor
enum PassByLinks {
    static var host = "passby.tenon.asia"
    static func page(_ path: String) -> URL { URL(string: "https://\(host)/\(path)")! }
}

@MainActor
final class TenonAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TenonAccount()
    static let sessionLifetime: Double = 30 * 24 * 60 * 60 * 1000
    static let sessionVersion = 3
    struct Identity: Codable {
        let issuer: String
        let sub: String
        let name: String
        let role: String
        let expires: Double
    }
    struct Grant: Codable {
        let token: String
        let identity: Identity
        let version: Int
        let refreshToken: String
        let refreshExpires: Double
    }
    @Published private(set) var identity: Identity?
    @Published private(set) var working = false
    @Published var message: String?
    private var browser: ASWebAuthenticationSession?
    private var grant: Grant?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private let store: TenonSessionStore
    private let now: () -> Date
    private let transport: (URLRequest) async throws -> (Data, URLResponse)
    private var restored = false
    private var deletionReturnPending = false
    // PassBy moves to passby.tenonai.cn after its ICP filing. Until that host
    // answers, this build keeps the old address; both reach the same sessions.
    static let services = ["https://passby.tenonai.cn/passby/api/", "https://tenon.asia/passby/api/"]
    private let services: [String]
    private var service: String
    private var serviceChecked = -Double.infinity
    private var api: String { service + "auth/" }
    private var time: Double { now().timeIntervalSince1970 * 1000 }
    // An expired remembered profile is presentation only. Account-gated work
    // needs a current product session; offline Face ID uses the separate vault.
    var hasCurrentAuthorization: Bool { (grant?.identity.expires ?? 0) > time }

    init(store: TenonSessionStore = TenonSessionStore(), now: @escaping () -> Date = Date.init, services: [String] = TenonAccount.services,
         transport: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.store = store; self.now = now; self.transport = transport
        self.services = services; service = services[services.count - 1]
        super.init()
        guard let data = try? store.read() else { return }
        guard let saved = try? JSONDecoder().decode(Grant.self, from: data), valid(saved, restoring: true) else {
            try? store.clear(); return
        }
        grant = saved; identity = saved.identity; restored = true
    }
    private func valid(_ value: Grant, restoring: Bool = false) -> Bool {
        let person = value.identity
        guard person.issuer == "https://account.tenon.asia/api/auth", !person.sub.isEmpty, person.sub.count <= 256,
              ["admin", "user"].contains(person.role), person.expires.isFinite,
              value.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return false }
        guard value.version == Self.sessionVersion,
              value.refreshToken.range(of: "^[A-Za-z0-9._~-]{32,4096}$", options: .regularExpression) != nil,
              value.refreshExpires.isFinite, value.refreshExpires > time, value.refreshExpires <= time + Self.sessionLifetime,
              person.expires > 0, person.expires <= time + Self.sessionLifetime else { return false }
        return restoring || person.expires > time
    }
    func validateRestoredSession() async {
        guard restored, grant != nil else { return }
        restored = false
        await renew(force: true)
    }
    // Moves to the first newer service whose health check answers, checking at
    // most every 10 minutes. It never moves back during a launch.
    func chooseService() async {
        guard service != services[0], time - serviceChecked >= 600_000 else { return }
        serviceChecked = time
        for candidate in services.dropLast() {
            var request = URLRequest(url: URL(string: candidate + "health")!)
            request.timeoutInterval = 5; request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await transport(request), (response as? HTTPURLResponse)?.statusCode == 200,
                  (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true else { continue }
            service = candidate
            if let host = URL(string: candidate)?.host { PassByLinks.host = host }
            return
        }
    }
    func didBecomeActive() async {
        checkExpiry()
        if deletionReturnPending { await checkDeletionReturn() }
        await renew()
    }
    func beginDeletion() async -> URL? {
        guard !working, let previous = grant, hasCurrentAuthorization else { return nil }
        working = true
        defer { working = false }
        let attempt = generation
        var request = URLRequest(url: URL(string: api + "tenon/delete/start")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer \(previous.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        do {
            let (data, response) = try await transport(request)
            guard generation == attempt else { return nil }
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 401 { invalidate(); return nil }
            guard status == 200, let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = payload["url"] as? String, let parts = URLComponents(string: raw),
                  parts.scheme == "https", ["account.tenon.asia", "account.tenonai.cn"].contains(parts.host), parts.port == nil,
                  parts.user == nil, parts.password == nil, parts.fragment == nil, parts.path == "/account/delete/",
                  let source = parts.queryItems?.first(where: { $0.name == "request" })?.value,
                  source.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
                  let url = parts.url else { throw URLError(.badServerResponse) }
            deletionReturnPending = true
            return url
        } catch {
            if generation == attempt { message = L("Could not open the deletion page. Please try again.") }
            return nil
        }
    }
    private func checkDeletionReturn() async {
        guard let previous = grant else { deletionReturnPending = false; return }
        let attempt = generation
        var request = URLRequest(url: URL(string: api + "session")!)
        request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(previous.token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await transport(request)
            guard generation == attempt else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 401 || status == 403 { VaultSession.shared.lock(); invalidate() }
            if status == 200 || status == 401 || status == 403 { deletionReturnPending = false }
        } catch { /* Retry once on the next foreground visit; never poll Tenon. */ }
    }
    func ensureCurrentSession() async -> Bool {
        checkExpiry()
        await renew()
        if !hasCurrentAuthorization, identity != nil {
            message = L("Your account could not be verified. Connect to the internet and try again.")
        }
        return hasCurrentAuthorization
    }
    private func renew(force: Bool = false) async {
        if let task = refreshTask { await task.value; return }
        guard let previous = grant,
              force || previous.identity.expires <= time + 30000 else { return }
        guard valid(previous, restoring: true) else { invalidate(); return }
        let attempt = generation
        let task = Task { await refresh(previous, attempt: attempt) }
        refreshTask = task
        await task.value
        if generation == attempt { refreshTask = nil }
    }
    private func refresh(_ previous: Grant, attempt: Int) async {
        var request = URLRequest(url: URL(string: api + "refresh")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": previous.refreshToken,
                "issuer": previous.identity.issuer, "sub": previous.identity.sub, "session_version": Self.sessionVersion])
            let (data, response) = try await transport(request)
            guard generation == attempt, grant?.refreshToken == previous.refreshToken, !Task.isCancelled else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 401 || status == 403 {
                invalidate(); message = L("Sign in to Tenon again to continue account services."); return
            }
            guard status == 200 else { return } // A temporary outage must not erase a remembered account.
            let next = try JSONDecoder().decode(Grant.self, from: data)
            guard valid(next), next.identity.issuer == previous.identity.issuer,
                  next.identity.sub == previous.identity.sub, next.refreshToken != previous.refreshToken else {
                invalidate(); message = L("Sign in to Tenon again to continue account services."); return
            }
            // Persist the rotated credential before adopting it. Concurrent callers
            // share one task; logout or a newer login invalidates this result.
            try store.write(JSONEncoder().encode(next))
            grant = next; identity = next.identity; message = nil
        } catch {
            // Keep the old credential for a bounded central retry after a lost
            // response. This does not renew access or unlock the local notebook.
        }
    }
    private func invalidate() {
        grant = nil; identity = nil; restored = false
        do { try store.clear() }
        catch { message = L("Could not clear the saved sign-in. Please try again.") }
    }
    func checkExpiry() {
        guard let saved = grant else { return }
        if !valid(saved, restoring: true) { invalidate() }
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
    func signIn(method: String? = nil) {
        guard !working else { return }
        VaultSession.shared.lock(); generation += 1
        refreshTask?.cancel(); refreshTask = nil
        let attempt = generation
        working = true; message = nil
        do {
            let verifier = try random(), state = try random()
            let challenge = base64(Data(SHA256.hash(data: Data(verifier.utf8))))
            var start = URLComponents(string: api + "start")!
            start.queryItems = [URLQueryItem(name: "platform", value: "ios"), URLQueryItem(name: "session_version", value: String(Self.sessionVersion)),
                URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "state", value: state)]
            if let method { start.queryItems?.append(URLQueryItem(name: "method", value: method)) }
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
                        request.httpMethod = "POST"; request.timeoutInterval = 15
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: ["ticket": ticket, "verifier": verifier, "state": state])
                        let (data, response) = try await self.transport(request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
                        let next = try JSONDecoder().decode(Grant.self, from: data)
                        guard self.valid(next) else { throw URLError(.badServerResponse) }
                        guard self.generation == attempt else { return }
                        try self.store.write(JSONEncoder().encode(next))
                        self.grant = next; self.identity = next.identity; self.restored = false
                    } catch { if self.generation == attempt { self.message = L("Tenon sign-in could not be completed. Please try again.") } }
                    if self.generation == attempt { self.working = false }
                }
            }
            browser.presentationContextProvider = self
            // Skips the system "wants to use" prompt before a method the person just chose.
            browser.prefersEphemeralWebBrowserSession = true
            self.browser = browser
            if !browser.start() { self.browser = nil; working = false; message = L("Tenon sign-in could not be completed. Please try again.") }
        } catch { working = false; message = L("Tenon sign-in could not be completed. Please try again.") }
    }
    func signOut() {
        VaultSession.shared.lock(); generation += 1; browser?.cancel(); browser = nil; working = false
        refreshTask?.cancel(); refreshTask = nil
        do { try store.clear() }
        catch { message = L("Could not clear the saved sign-in. Please try again."); return }
        let previous = grant; grant = nil; identity = nil; message = nil; restored = false
        if let previous {
            Task {
                var request = URLRequest(url: URL(string: api + "logout")!)
                request.httpMethod = "POST"; request.timeoutInterval = 15
                request.setValue("Bearer \(previous.token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": previous.refreshToken])
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
