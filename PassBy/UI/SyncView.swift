import SwiftUI

/// What the sync page shows and does. It lives as long as the page: leaving the page, or the app
/// going to the background, stops listening.
@MainActor
final class SyncModel: ObservableObject {
    struct Hosting: Equatable {
        let address: SyncAddress
        let code: String
    }

    @Published private(set) var ownAddress: SyncAddress?
    @Published private(set) var hosting: Hosting?
    @Published private(set) var stopped: SyncHost.Stop?
    @Published private(set) var summary: SyncSummary?
    @Published private(set) var working = false
    @Published private(set) var error: String?
    @Published var address = UserDefaults.standard.string(forKey: SyncModel.lastAddressKey) ?? ""
    @Published var code = ""

    private static let portKey = "syncPort"
    private static let lastAddressKey = "syncLastAddress"
    private var host: SyncHost?
    private var task: Task<Void, Never>?

    /// Chosen at random the first time and kept, so this iPhone's address stays the same.
    private static var port: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: portKey)
        if (49152...65535).contains(saved) { return UInt16(saved) }
        let port = UInt16.random(in: 49152...65535)
        UserDefaults.standard.set(Int(port), forKey: portKey)
        return port
    }

    func refresh() { ownAddress = SyncAddress.local(port: Self.port) }

    /// Starts listening with a fresh pairing code.
    func startHosting(session: VaultSession) {
        guard host == nil, !working else { return }
        error = nil; stopped = nil; summary = nil
        refresh()
        guard let local = ownAddress else { error = L("This iPhone is not on Wi-Fi or a local network."); return }
        let code = SyncCrypto.newCode()
        let marker = L(" (Conflict copy)")
        do {
            var started: SyncHost?
            let next = try SyncHost(code: code, address: local, exchange: { guest in
                // On the host's own queue. The merge and the save happen as one step on the main actor.
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        guard let outcome = session.syncMerge(guest: guest, marker: marker) else { return nil }
                        self.summary = outcome.mine
                        return outcome.reply
                    }
                }
            }, onStopped: { reason in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard self.host === started else { return }
                        self.host = nil
                        self.hosting = nil
                        if reason != .closed { self.stopped = reason }
                    }
                }
            })
            started = next
            host = next
            hosting = Hosting(address: local, code: code)
            next.start()
        } catch {
            self.error = L("Could not start. Please try again.")
        }
    }

    func stopHosting() {
        host?.stop()
        host = nil
        hosting = nil
    }

    /// Connects to a phone that is listening, and takes the merged notebook.
    func join(session: VaultSession) {
        guard !working, host == nil else { return }
        summary = nil
        let typed = code
        code = ""
        guard let target = SyncAddress.parse(address) else { error = L("The address is the one shown on the other phone, like 192.168.1.20:52814."); return }
        guard let pairing = SyncCrypto.canonicalCode(typed) else { error = L("The pairing code is 12 letters and digits."); return }
        error = nil
        working = true
        task = Task {
            let guest = SyncGuest(address: target, code: pairing)
            var failure: String? = L("The notebook changed during the sync. Please sync again.")
            do {
                // If the notebook changes while the other phone is merging, nothing is taken and the
                // exchange is made again in the same session: the code is good for one session.
                for _ in 1...3 {
                    guard let sent = session.syncState() else { failure = L("The sync did not finish and nothing was changed. Update PassBy on both devices and try again."); break }
                    let result = try await guest.exchange(sent)
                    if Task.isCancelled { return }
                    guard let taken = session.syncTake(result.state, ifUnchangedFrom: sent) else { failure = VaultError.storageFailed.localizedDescription; break }
                    if taken {
                        summary = result.summary
                        failure = nil
                        break
                    }
                }
            } catch let problem as SyncGuestError {
                switch problem {
                case .unreachable: failure = L("Could not connect. Check that both devices are on the same Wi-Fi, that the sync page is open on the other phone, and that PassBy is allowed to use the local network in iPhone Settings.")
                case .wrongCode: failure = L("The other phone did not accept. The code is wrong or has already been used: start again there and use the new code.")
                case .stopped: failure = L("The other phone has stopped. Start again there.")
                case .untrusted: failure = L("The reply could not be verified. Nothing was changed.")
                case .failed: failure = L("The sync did not finish and nothing was changed. Update PassBy on both devices and try again.")
                }
            } catch {
                failure = L("The sync did not finish and nothing was changed. Update PassBy on both devices and try again.")
            }
            if Task.isCancelled { return }
            working = false
            error = failure
            if failure == nil { UserDefaults.standard.set(target.description, forKey: Self.lastAddressKey) }
        }
    }

    /// Leaving the page stops everything.
    func leave() {
        stopHosting()
        task?.cancel()
        task = nil
        working = false
    }
}

/// Sync with another device on the same local network (docs/sync.md). This iPhone either listens,
/// showing an address and a pairing code, or connects to a phone that is listening.
struct SyncView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = SyncModel()

    var body: some View {
        List {
            Section {
                Text("On the same Wi-Fi, sync this iPhone’s notebook with another phone, or with the web page on a computer. What is sent is encrypted and goes only between the two devices, never through our servers.")
                if let summary = model.summary { result(summary) }
                if let error = model.error { Text(error).fontWeight(.semibold) }
                if let stopped = model.stopped { Text(stoppedText(stopped)).fontWeight(.semibold) }
            }
            if let hosting = model.hosting {
                Section {
                    readOut("Address", hosting.address.description)
                    readOut("Pairing code", SyncCrypto.display(hosting.code))
                    Button(role: .cancel) { model.stopHosting() } label: { Label("Stop", systemImage: "xmark") }
                } header: { Text("This iPhone") } footer: {
                    Text("Enter this address and code on the other device. It can connect only while this page is open, and the code is new every time.")
                }
            } else {
                Section {
                    Button { model.startHosting(session: session) } label: { Label("Let another device connect", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.working)
                    if let own = model.ownAddress {
                        ShareLink(item: String(format: L("Open in Chrome or Edge on your computer to sync with PassBy on your phone: %@"), "https://passby.tenonai.cn/app/#\(own)")) {
                            Label("Send the address to a computer", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: { Text("This iPhone") } footer: {
                    Text("The link holds only this iPhone’s address on the local network, not the pairing code. Open it in Chrome or Edge on the computer.")
                }
                Section {
                    TextField("192.168.1.20:52814", text: $model.address)
                        .font(.body.monospaced()).keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(Text("Address"))
                    TextField("XXXX-XXXX-XXXX", text: $model.code)
                        .font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityLabel(Text("Pairing code"))
                    Button { model.join(session: session) } label: {
                        Label(model.working ? L("Syncing…") : L("Sync"), systemImage: "checkmark")
                    }
                    .disabled(model.working || model.address.trimmingCharacters(in: .whitespaces).isEmpty || model.code.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("Connect to another phone") } footer: {
                    Text("On the other phone, tap “Let another device connect” first, then enter the address and code it shows.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("Sync").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
        .onDisappear { model.leave() }
        .onChange(of: scenePhase) { _, phase in
            // Another device can connect only while this page is in front.
            if phase == .background { model.stopHosting() }
        }
    }

    private func readOut(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(Palette.secondary)
            Text(value).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
        }
    }

    @ViewBuilder private func result(_ summary: SyncSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Synced").fontWeight(.semibold)
            if summary.added == 0 && summary.updated == 0 && summary.removed == 0 && summary.conflicts == 0 {
                Text("Both were already the same. Nothing changed.")
            } else {
                Text(String(format: L("%d added, %d updated, %d removed."), summary.added, summary.updated, summary.removed))
            }
            if summary.conflicts > 0 {
                Text(String(format: L("%d changed on both devices, and both versions were kept: the other one has “Conflict copy” in its title."), summary.conflicts))
            }
            if summary.removed > 0 {
                Text("Entries deleted on the other device are in Recently Deleted and can be put back within 30 days.")
            }
        }
    }

    private func stoppedText(_ reason: SyncHost.Stop) -> String {
        switch reason {
        case .idle: return L("Stopped after 10 minutes without a connection.")
        case .wrongCode: return L("Stopped after 5 wrong codes. Starting again gives a new code.")
        default: return L("Could not keep listening and stopped. Check that PassBy is allowed to use the local network in iPhone Settings.")
        }
    }
}
