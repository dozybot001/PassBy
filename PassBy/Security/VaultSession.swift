import CryptoKit
import LocalAuthentication
import SwiftUI
import UIKit

@MainActor
final class VaultSession: ObservableObject {
    static let shared = VaultSession()
    private static let gateKey = "gateEnabled"
    private static let noLockNoticeKey = "noLockNoticeShown"

    @Published private(set) var phase: SessionGate.Phase = .locked
    @Published private(set) var vault = Vault()
    @Published private(set) var recentlyDeleted: [DeletedEntry] = []
    @Published private(set) var lastExportAt: Date?
    @Published private(set) var showExportReminder = false
    @Published private(set) var gateEnabled: Bool
    @Published private(set) var deviceHasLock = true
    @Published var showNoLockNotice = false
    /// 1.x notebooks on this iPhone that are not in the 2.0 notebook yet.
    @Published private(set) var pendingLegacy: [LegacyNotebook] = []
    @Published private(set) var migrationNeedsRecovery = false
    @Published private(set) var migrationSummary: MigrationSummary?
    @Published var migrationDeferred = false
    @Published var message: String?
    @Published private(set) var toast: String?
    /// A button beside the toast, such as View after copying from the list.
    private(set) var toastAction: (title: String, run: () -> Void)?

    private var gate = SessionGate()
    private let store: NotebookStore
    private let defaults: UserDefaults
    /// In memory only while the notebook is open.
    private var notebook: Notebook?
    private var context: LAContext?
    private var toastTask: Task<Void, Never>?
    private var promptedSinceForeground = false

    init(store: NotebookStore = NotebookStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        gateEnabled = defaults.object(forKey: Self.gateKey) as? Bool ?? true
    }

    var needsMigration: Bool { !pendingLegacy.isEmpty && !migrationDeferred && migrationSummary == nil }
    var draft: VaultEntry? { notebook?.draft }

    // MARK: The door

    private func refreshDeviceLock() {
        deviceHasLock = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Opens the notebook: directly when the door is off or the phone has no
    /// screen lock, otherwise after Face ID, Touch ID or the device passcode.
    func unlock() async {
        refreshDeviceLock()
        guard gate.phase == .locked else { return }
        message = nil
        guard gateEnabled, deviceHasLock else {
            gate.open()
            publishOpened()
            return
        }
        guard let token = gate.beginAuthentication() else { return }
        phase = gate.phase
        let auth = LAContext()
        auth.localizedCancelTitle = L("Cancel")
        context = auth
        do {
            let success = try await auth.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: L("Open your password notebook."))
            guard gate.accepts(token) else { return }
            guard success else { throw VaultError.authenticationFailed }
            gate.authenticationSucceeded(token)
            publishOpened()
        } catch {
            guard gate.accepts(token) else { return }
            gate.authenticationFailed(token)
            clearMemory()
            phase = gate.phase
            if let laError = error as? LAError, [.userCancel, .systemCancel, .appCancel].contains(laError.code) { return }
            message = VaultError.authenticationFailed.localizedDescription
        }
    }

    private func publishOpened() {
        context?.invalidate()
        context = nil
        do {
            var loaded = try store.load()
            let before = loaded
            loaded.pruneDeleted()
            if loaded != before { try? store.save(loaded) }
            adopt(loaded)
            pendingLegacy = LegacyNotebook.all(root: store.directory).filter { !loaded.migratedLegacy.contains($0.name) }
            phase = gate.phase
            if !deviceHasLock, !defaults.bool(forKey: Self.noLockNoticeKey) {
                defaults.set(true, forKey: Self.noLockNoticeKey)
                showNoLockNotice = true
            }
        } catch {
            // The file on disk is left exactly as it is.
            gate.lock()
            clearMemory()
            phase = gate.phase
            message = error.localizedDescription
        }
    }

    private func adopt(_ value: Notebook) {
        notebook = value
        if vault != value.vault { vault = value.vault }
        if recentlyDeleted != value.recentlyDeleted { recentlyDeleted = value.recentlyDeleted }
        lastExportAt = value.lastExportAt
        showExportReminder = value.needsExportReminder()
    }

    /// Switching the door off asks once more, so a bystander cannot do it.
    func setGate(_ enabled: Bool) async {
        refreshDeviceLock()
        guard enabled != gateEnabled, gate.phase == .unlocked else { return }
        if !enabled, deviceHasLock {
            let auth = LAContext()
            auth.localizedCancelTitle = L("Cancel")
            guard (try? await auth.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: L("Turn off the lock for PassBy."))) == true, gate.phase == .unlocked else { return }
        }
        defaults.set(enabled, forKey: Self.gateKey)
        gateEnabled = enabled
    }

    func didEnterBackground() {
        gate.didEnterBackground(at: Uptime.now)
        promptedSinceForeground = false
        if gate.phase == .locked { clearMemory() }
        phase = gate.phase
    }

    func didBecomeActive() {
        gate.didBecomeActive(at: Uptime.now)
        if gate.phase == .locked { clearMemory() }
        phase = gate.phase
        // Ask once per return to the app; after a cancel the lock page has a button.
        if gate.phase == .locked, !promptedSinceForeground {
            promptedSinceForeground = true
            Task { await unlock() }
        }
    }

    func lock() {
        gate.lock()
        clearMemory()
        phase = gate.phase
    }

    private func clearMemory() {
        context?.invalidate()
        context = nil
        notebook = nil
        vault = Vault()
        recentlyDeleted = []
        lastExportAt = nil
        showExportReminder = false
        pendingLegacy = []
        migrationSummary = nil
        migrationNeedsRecovery = false
        dismissToast()
    }

    // MARK: Changes

    /// Applies a change to the notebook and writes it at once.
    @discardableResult
    private func write(_ change: (inout Notebook) -> Void) -> Bool {
        guard gate.phase == .unlocked, var next = notebook else { return false }
        change(&next)
        guard next != notebook else { return true }
        do {
            try store.save(next)
            adopt(next)
            return true
        } catch {
            message = VaultError.storageFailed.localizedDescription
            return false
        }
    }

    @discardableResult
    private func commit(_ next: Vault, clearingDraft: Bool = false) -> Bool {
        write { notebook in
            notebook.update(next)
            if clearingDraft { notebook.draft = nil }
        }
    }

    @discardableResult
    func save(_ entry: VaultEntry) -> Bool {
        var next = vault
        var value = entry
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { return false }
        next.save(value)
        return commit(next, clearingDraft: true)
    }

    @discardableResult
    func saveDraft(_ entry: VaultEntry?) -> Bool {
        write { $0.draft = entry }
    }

    @discardableResult
    func deleteEntry(_ id: UUID) -> Bool {
        var next = vault
        next.entries.removeAll { $0.id == id }
        return commit(next)
    }

    /// Puts a recently deleted entry back. Its folder may be gone; it then
    /// returns to Unfiled.
    @discardableResult
    func restoreDeleted(_ id: UUID) -> Bool {
        guard let item = recentlyDeleted.first(where: { $0.id == id }) else { return false }
        var next = vault
        next.save(item.entry)
        return commit(next)
    }

    @discardableResult
    func purgeDeleted(_ id: UUID) -> Bool {
        write { $0.recentlyDeleted.removeAll { $0.id == id } }
    }

    // MARK: Sync (docs/sync.md)

    /// The notebook as it is sent to the other device; nil while it is locked.
    func syncState() -> SyncState? {
        gate.phase == .unlocked ? notebook?.syncState() : nil
    }

    /// Listening side: merges the guest's state into the notebook and saves it as one step. Returns
    /// what to answer and what changed here, or nil when nothing could be saved.
    func syncMerge(guest: SyncState, marker: String) -> (reply: (state: SyncState, summary: SyncSummary), mine: SyncSummary)? {
        guard let before = syncState(),
              let merged = try? SyncMerge.merge(host: before, guest: guest, marker: marker),
              let theirs = try? SyncMerge.summary(before: guest, after: merged.state, conflicts: merged.conflicts),
              let mine = try? SyncMerge.summary(before: before, after: merged.state, conflicts: merged.conflicts),
              syncTake(merged.state, ifUnchangedFrom: before) == true else { return nil }
        return ((merged.state, theirs), mine)
    }

    /// Takes a merged state. False when the notebook is no longer what was sent, so nothing was
    /// taken; nil when it could not be saved.
    func syncTake(_ state: SyncState, ifUnchangedFrom sent: SyncState) -> Bool? {
        guard syncState() == sent else { return false }
        var taken = true
        let saved = write { notebook in
            do { try notebook.takeSynced(state) } catch { taken = false }
        }
        return saved && taken ? true : nil
    }

    @discardableResult
    func createFolder(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = VaultFolder(name: trimmed)
        var next = vault
        next.folders.append(folder)
        return commit(next) ? folder.id : nil
    }

    @discardableResult
    func saveFolder(id: UUID? = nil, name: String) -> Bool {
        guard let id else { return createFolder(name: name) != nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var next = vault
        if let index = next.folders.firstIndex(where: { $0.id == id }) {
            next.folders[index].name = trimmed
        } else { next.folders.append(VaultFolder(name: trimmed)) }
        return commit(next)
    }

    @discardableResult
    func deleteFolder(_ id: UUID) -> Bool {
        var next = vault
        next.removeFolder(id)
        return commit(next)
    }

    func copy(_ value: String, label: String, action: (title: String, run: () -> Void)? = nil) {
        guard gate.phase == .unlocked, !value.isEmpty else { return }
        SecureClipboard.copy(value)
        toastTask?.cancel()
        toastAction = action
        toast = label
        UIAccessibility.post(notification: .announcement, argument: label)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(action == nil ? 2 : 4))
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
        toastAction = nil
    }

    // MARK: Export and import

    /// Call once the file has been handed to the person.
    func exportCompleted() {
        write { notebook in
            notebook.lastExportAt = Date()
            notebook.changedSinceExport = false
            notebook.exportReminderDismissedAt = nil
        }
    }

    func dismissExportReminder() {
        write { $0.exportReminderDismissedAt = Date() }
    }

    func applyImport(_ payload: ExportPayload, replacing: Bool) -> ImportSummary? {
        var summary: ImportSummary?
        let saved = write { notebook in
            summary = replacing ? NotebookImport.replace(payload.vault, in: &notebook)
                : NotebookImport.merge(payload.vault, into: &notebook)
        }
        return saved ? summary : nil
    }

    // MARK: Notebooks from PassBy 1.x

    /// Carries the 1.x notebooks on this iPhone into the 2.0 notebook. Old keys
    /// need Face ID or Touch ID; when a key is gone, the recovery key opens the
    /// file instead. The old files and keys are left untouched either way.
    func migrate(recoveryText: String? = nil) async {
        guard gate.phase == .unlocked, var next = notebook, !pendingLegacy.isEmpty else { return }
        message = nil
        var recovery: SymmetricKey?
        if let recoveryText, !recoveryText.isEmpty {
            do { recovery = try RecoveryKey.parse(recoveryText) }
            catch { message = error.localizedDescription; return }
        }
        let auth = LAContext()
        auth.localizedFallbackTitle = ""
        auth.localizedCancelTitle = L("Cancel")
        defer { auth.invalidate() }
        var biometric = false
        if auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            do {
                biometric = try await auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: LB("Use Face ID to read your earlier notebook."))
            } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
                return
            } catch { biometric = false }
        }
        guard gate.phase == .unlocked else { return }
        var books: [(name: String, state: LegacyState)] = []
        for book in pendingLegacy {
            var keys: [SymmetricKey] = []
            if biometric, let key = try? LegacyKeyStore(ownerID: book.name).read(context: auth) { keys.append(key) }
            if let recovery { keys.append(recovery) }
            guard let state = keys.lazy.compactMap({ try? book.open(key: $0) }).first else {
                migrationNeedsRecovery = true
                message = recovery == nil
                    ? LB("The key for your earlier notebook is no longer on this iPhone. This happens after Face ID is set up again. Enter the recovery key you saved.")
                    : RecoveryError.wrongNotebook.localizedDescription
                return
            }
            books.append((book.name, state))
        }
        do {
            let summary = try Migration.carry(books, into: &next)
            try store.save(next)
            adopt(next)
            pendingLegacy = []
            migrationNeedsRecovery = false
            migrationSummary = summary
        } catch {
            // Nothing was written; the earlier notebook is still where it was.
            message = L("Your earlier notebook could not be moved completely, so nothing was changed. It is still on this iPhone. Please try again.")
        }
    }

    func finishMigration() { migrationSummary = nil }
}

enum SecureClipboard {
    static let lifetime: TimeInterval = 60
    static func options(now: Date = Date()) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: now.addingTimeInterval(lifetime)]
    }
    @MainActor
    static func copy(_ value: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: options())
    }
}

/// How this iPhone unlocks. iPhone SE models use Touch ID; without either,
/// the device passcode opens the notebook.
enum Biometry {
    case faceID, touchID, none
    static var current: Biometry {
        let context = LAContext()
        // biometryType is set by this call whatever it returns.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return .touchID
        case .faceID: return .faceID
        default: return .none
        }
    }
    var symbol: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.open"
        }
    }
}

/// Localized copy is written with "Face ID". Both languages use the product
/// name untranslated, so Touch ID iPhones get the same sentence with their own.
func LB(_ key: String) -> String {
    let text = L(key)
    return Biometry.current == .touchID ? text.replacingOccurrences(of: "Face ID", with: "Touch ID") : text
}
