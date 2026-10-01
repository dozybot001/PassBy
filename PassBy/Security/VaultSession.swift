import CloudKit
import CryptoKit
import LocalAuthentication
import SwiftUI
import UIKit

@MainActor
final class VaultSession: ObservableObject {
    static let shared = VaultSession()
    enum Setup { case checking, newNotebook, recovery, localRecovery, ready, unavailable }
    enum SyncStatus { case waiting, syncing, synced, failed }

    @Published private(set) var phase: SessionGate.Phase = .locked
    @Published private(set) var vault = Vault()
    @Published private(set) var setup: Setup = .checking
    @Published private(set) var syncStatus: SyncStatus = .waiting
    @Published private(set) var syncMessage: String?
    @Published private(set) var needsCloudRestore = false
    @Published private(set) var recoveryToSave: String?
    @Published var message: String?
    @Published private(set) var toast: String?

    var isAppleAccountLinked: Bool { keyStore != nil && setup == .ready }

    private var gate = SessionGate()
    private let cloud = CloudNotebook()
    private var storage: VaultStorage?
    private var keyStore: KeyStore?
    private var key: SymmetricKey?
    private var localState: LocalVaultState?
    private var pending: (key: SymmetricKey, state: LocalVaultState)?
    private var context: LAContext?
    private var toastTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var syncRunning = false
    private var syncAgain = false
    private var bindingGeneration: UInt64 = 0

    func prepare() async {
        guard setup == .checking || setup == .unavailable else { return }
        setup = .checking
        message = nil
        let token = bindingGeneration
        do {
            let owner = try await cloud.ownerID()
            guard token == bindingGeneration else { return }
            let disk = VaultStorage(ownerID: owner)
            let initial: Setup
            if disk.exists { initial = .ready }
            else if try await cloud.fetch() != nil { initial = .recovery }
            else { initial = try disk.otherSnapshots().isEmpty ? .newNotebook : .localRecovery }
            guard token == bindingGeneration else { return }
            storage = disk
            keyStore = KeyStore(ownerID: owner)
            setup = initial
        } catch {
            guard token == bindingGeneration else { return }
            setup = .unavailable
            message = cloudErrorMessage(error)
        }
    }

    func accountChanged() {
        bindingGeneration &+= 1
        lock()
        storage = nil
        keyStore = nil
        setup = .checking
        Task { await prepare() }
    }

    func unlock(recoveryText: String? = nil) async {
        guard !UIScreen.main.isCaptured else {
            message = VaultError.captureActive.localizedDescription
            return
        }
        guard let storage, let keyStore,
              setup != .checking, setup != .unavailable,
              let token = gate.beginAuthentication() else { return }
        phase = gate.phase
        message = nil
        let auth = LAContext()
        auth.localizedFallbackTitle = ""
        auth.localizedCancelTitle = L("Cancel")
        auth.touchIDAuthenticationAllowableReuseDuration = 0
        context = auth
        do {
            var evaluationError: NSError?
            guard auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                error: &evaluationError), auth.biometryType == .faceID else {
                throw VaultError.faceIDRequired
            }
            let success = try await auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                localizedReason: L("Unlock your private notebook."))
            guard gate.accepts(token) else { return }
            gate.biometricPromptFinished(token)
            guard success else { throw VaultError.authenticationFailed }
            let unlockedKey: SymmetricKey
            let state: LocalVaultState
            if let recoveryText {
                unlockedKey = try RecoveryKey.parse(recoveryText)
                let record = try await cloud.fetch()
                guard gate.accepts(token) else { return }
                if setup == .localRecovery {
                    // Explicit on-device restore into an empty production book.
                    // Leave the original encrypted snapshot untouched.
                    guard record == nil else { setup = .recovery; throw CloudError.notebookChanged }
                    state = try storage.recoverLocalState(key: unlockedKey)
                } else {
                    guard let record else { setup = .localRecovery; throw CloudError.notebookChanged }
                    let remote: Vault
                    do { remote = try VaultCipher.open(cloud.ciphertext(in: record), key: unlockedKey) }
                    catch { throw RecoveryError.wrongNotebook }
                    if storage.exists {
                        let previous = try storage.load(key: unlockedKey)
                        state = LocalVaultState(current: VaultMerge.merge(base: previous.base,
                            local: previous.current, remote: remote).vault, base: remote,
                            recoveryConfirmed: true, draft: previous.draft)
                    } else {
                        state = LocalVaultState(current: remote, base: remote, recoveryConfirmed: true)
                    }
                }
                try storage.save(state, key: unlockedKey)
                try keyStore.store(unlockedKey)
            } else if storage.exists {
                unlockedKey = try keyStore.read(context: auth)
                state = try storage.load(key: unlockedKey)
            } else {
                unlockedKey = SymmetricKey(size: .bits256)
                state = LocalVaultState(current: Vault(), base: Vault(), recoveryConfirmed: false)
                try keyStore.store(unlockedKey)
                try storage.save(state, key: unlockedKey)
            }
            guard gate.authenticationSucceeded(token) else { return }
            pending = (unlockedKey, state)
            setup = .ready
            publishIfReady()
        } catch {
            guard gate.accepts(token) else { return }
            gate.authenticationFailed(token)
            clearSensitiveState()
            phase = gate.phase
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel, .systemCancel, .appCancel: message = nil
                case .biometryLockout:
                    message = L("Face ID is temporarily locked. Unlock your iPhone with its passcode, then try again.")
                case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                    message = VaultError.faceIDRequired.localizedDescription
                default: message = VaultError.authenticationFailed.localizedDescription
                }
            } else {
                if let vaultError = error as? VaultError,
                   vaultError == .missingKey || vaultError == .invalidKey { setup = .recovery }
                message = error.localizedDescription
            }
        }
    }

    func willResignActive() {
        gate.willResignActive()
        if gate.phase == .locked { clearSensitiveState() }
        phase = gate.phase
    }

    func didEnterBackground() {
        gate.didEnterBackground()
        clearSensitiveState()
        phase = gate.phase
    }

    func didBecomeActive() {
        gate.didBecomeActive()
        publishIfReady()
    }

    func lock() {
        gate.lock()
        clearSensitiveState()
        phase = gate.phase
    }

    private func publishIfReady() {
        if gate.phase == .unlocked, let pending {
            key = pending.key
            localState = pending.state
            vault = pending.state.current
            recoveryToSave = pending.state.recoveryConfirmed ? nil : RecoveryKey.format(pending.key)
            self.pending = nil
            context?.invalidate()
            context = nil
            if recoveryToSave == nil { requestSync() }
        }
        phase = gate.phase
    }

    private func clearSensitiveState() {
        context?.invalidate()
        context = nil
        pending = nil
        key = nil
        localState = nil
        vault = Vault()
        recoveryToSave = nil
        toastTask?.cancel()
        toast = nil
        syncTask?.cancel()
        syncTask = nil
        syncStatus = .waiting
        syncMessage = nil
        needsCloudRestore = false
    }

    @discardableResult
    private func commit(_ next: Vault, clearingDraft: Bool = false) -> Bool {
        guard gate.phase == .unlocked, gate.isActive, let key, let storage,
              var state = localState else { return false }
        state.current = next
        if clearingDraft { state.draft = nil }
        do {
            try storage.save(state, key: key)
            localState = state
            vault = next
            requestSync()
            return true
        } catch {
            message = VaultError.storageFailed.localizedDescription
            return false
        }
    }

    func confirmRecoverySaved() {
        guard var state = localState, let key, let storage,
              gate.phase == .unlocked, gate.isActive else { return }
        state.recoveryConfirmed = true
        do {
            try storage.save(state, key: key)
            localState = state
            recoveryToSave = nil
            requestSync()
        } catch { message = VaultError.storageFailed.localizedDescription }
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

    var draft: VaultEntry? { localState?.draft }

    @discardableResult
    func saveDraft(_ entry: VaultEntry?) -> Bool {
        guard gate.phase == .unlocked, gate.isActive, let key, let storage,
              var state = localState else { return false }
        guard state.draft != entry else { return true }
        state.draft = entry
        do {
            try storage.save(state, key: key)
            localState = state
            return true
        } catch {
            message = VaultError.storageFailed.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteEntry(_ id: UUID) -> Bool {
        var next = vault
        next.entries.removeAll { $0.id == id }
        return commit(next)
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

    func copy(_ value: String, label: String) {
        guard gate.phase == .unlocked, gate.isActive, !value.isEmpty else { return }
        SecureClipboard.copy(value)
        toastTask?.cancel()
        toast = label
        UIAccessibility.post(notification: .announcement, argument: label)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func requestSync() {
        guard recoveryToSave == nil, gate.phase == .unlocked else { return }
        if syncRunning { syncAgain = true; return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func enableWebAccess() async {
        guard needsCloudRestore else { return }
        await syncNow(restoringMissingNotebook: true)
    }

    func syncNow(restoringMissingNotebook: Bool = false) async {
        guard !syncRunning, recoveryToSave == nil, gate.phase == .unlocked,
              gate.isActive, let key, let storage else { return }
        syncRunning = true
        syncStatus = .syncing
        syncMessage = nil
        let token = gate.generation
        defer {
            syncRunning = false
            if syncAgain { syncAgain = false; requestSync() }
        }
        do {
            let owner = try await cloud.ownerID()
            guard gate.generation == token, gate.phase == .unlocked else { return }
            guard owner == keyStore?.ownerID else { accountChanged(); return }
            for attempt in 0..<3 {
                let record = try await cloud.fetch()
                guard gate.generation == token, gate.phase == .unlocked,
                      gate.isActive, var state = localState else { return }
                let remote = try record.map { try VaultCipher.open(cloud.ciphertext(in: $0), key: key) }
                guard record != nil || state.base == Vault() || restoringMissingNotebook else {
                    needsCloudRestore = true
                    throw CloudError.notebookChanged
                }
                needsCloudRestore = false
                let merge = try state.integratingCloud(remote, restoringMissingNotebook: restoringMissingNotebook)
                state.current = merge.vault
                // The remote changes are now integrated locally. Advance the
                // base even if upload fails, so retries do not merge them twice.
                state.base = remote ?? Vault()
                try storage.save(state, key: key)
                localState = state
                vault = state.current
                let uploaded = state.current
                if let remote, uploaded == remote {
                    state.base = remote
                    try storage.save(state, key: key)
                    localState = state
                    syncStatus = .synced
                    return
                }
                do {
                    _ = try await cloud.save(VaultCipher.seal(uploaded, key: key), replacing: record)
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                    continue
                }
                guard gate.generation == token, gate.phase == .unlocked,
                      var latest = localState else { return }
                latest.base = uploaded
                try storage.save(latest, key: key)
                localState = latest
                syncStatus = latest.current == uploaded ? .synced : .waiting
                if latest.current != uploaded { syncAgain = true }
                if merge.conflictCount > 0 {
                    syncMessage = L("Changes from another device were kept. Conflicting passwords are saved as separate copies.")
                }
                return
            }
        } catch {
            guard gate.generation == token, gate.phase == .unlocked else { return }
            syncStatus = .failed
            syncMessage = L("Saved on this iPhone. iCloud sync will retry.") + " " + cloudErrorMessage(error)
        }
    }

    private func cloudErrorMessage(_ error: Error) -> String {
        if let cloudError = error as? CloudError { return cloudError.localizedDescription }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return CloudError.accountRequired.localizedDescription
            case .quotaExceeded: return L("Your iCloud storage is full. Free up space to resume syncing.")
            case .badContainer, .missingEntitlement:
                return L("iCloud is not configured for this build yet.")
            default: return CloudError.unavailable.localizedDescription
            }
        }
        return error.localizedDescription
    }
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
