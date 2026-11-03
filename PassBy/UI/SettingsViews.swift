import SwiftUI
import UIKit

struct FoldersView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editingID: UUID?
    @State private var showName = false
    @State private var deleting: VaultFolder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.vault.folders) { folder in
                        Button {
                            editingID = folder.id; name = folder.name; showName = true
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(session.vault.entries.filter { $0.folderID == folder.id }.count)")
                                    .foregroundStyle(Palette.secondary)
                            }.frame(minHeight: 40).foregroundStyle(Palette.ink)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = folder }.tint(Palette.ink)
                        }
                    }
                    Button {
                        editingID = nil; name = ""; showName = true
                    } label: { Label("New folder", systemImage: "plus") }
                        .frame(minHeight: 40)
                } footer: { Text("Deleting a folder keeps its passwords in Unfiled.") }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Folders").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(L(editingID == nil ? "New folder" : "Rename folder"), isPresented: $showName) {
                TextField("Folder name", text: $name)
                Button("Cancel", role: .cancel) { name = "" }
                Button("Save") { _ = session.saveFolder(id: editingID, name: name) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog("Delete this folder?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Delete folder") {
                    if let deleting { _ = session.deleteFolder(deleting.id) }
                    deleting = nil
                }
            } message: { Text("Its passwords will move to Unfiled.") }
        }
    }
}

struct SettingsView: View {
    @State private var confirmWebAccess = false
    @State private var syncing = false
    @State private var shownRecovery: String?
    @State private var revealing = false
    @State private var revealMessage: String?
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var account: TenonAccount
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var status: String {
        switch session.syncStatus {
        case .waiting: return L("Waiting to sync")
        case .syncing: return L("Syncing")
        case .synced: return L("Up to date")
        case .failed: return L("Saved on this iPhone")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let identity = account.identity {
                        Text(identity.name)
                        Link("Manage sign-in methods", destination: URL(string: "https://account.tenon.asia/account/")!)
                        Button("Sign out of PassBy") { account.signOut() }
                    } else {
                        SignInOptions().listRowSeparator(.hidden)
                    }
                    if account.identity != nil {
                        Button { Task { if let url = await account.beginDeletion() { openURL(url) } } }
                        label: { OperationLabel(title: "Delete account", working: account.working) }.disabled(account.working)
                    }
                    DisclosureGroup("Account deletion details") {
                        Text("Choose to delete only your PassBy sign-in or your entire Tenon account. Your Apple-stored notebook, device recovery keys and browser authorization are not deleted by this process.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    if let message = account.message { Text(message).font(.footnote).foregroundStyle(Palette.secondary) }
                } header: { Text("Tenon Account") } footer: {
                    Text(LB("Stay signed in to Tenon. Use Face ID each time you open your notebook. Manage your sign-in methods in Tenon Account."))
                }
                Section("Sync") {
                    LabeledContent("Status", value: status)
                    Button { sync() } label: { OperationLabel(title: "Sync now", working: syncing || session.syncStatus == .syncing) }
                        .disabled(syncing || session.syncStatus == .syncing)
                    if session.needsCloudRestore {
                        Button { confirmWebAccess = true } label: { OperationLabel(title: "Enable web access", working: syncing) }
                            .disabled(syncing || session.syncStatus == .syncing)
                    }
                    if let message = session.syncMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    if !session.isAppleAccountLinked {
                        Label("Apple Account unavailable", systemImage: "exclamationmark.icloud")
                            .foregroundStyle(Palette.secondary)
                    }
                    DisclosureGroup("Sync details") {
                        Label(session.isAppleAccountLinked ? L("Linked to your Apple Account") : L("Apple Account unavailable"),
                              systemImage: "icloud")
                        Text("PassBy uses the Apple Account signed in to iCloud on this iPhone. It does not request your Apple password, name or email.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                        Text("Changing the Apple Account locks this notebook. Each account has separate encrypted data. A new device also needs your recovery key.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                Section {
                    NavigationLink { RecentlyDeletedView() } label: {
                        LabeledContent {
                            Text("\(session.recentlyDeleted.count)").monospacedDigit()
                        } label: { Label("Recently Deleted", systemImage: "trash") }
                    }
                } footer: {
                    Text("Deleted passwords stay encrypted on this iPhone for 30 days, including those deleted on the web or another device. They are not synced.")
                }
                Section {
                    Label("Locked whenever you leave", systemImage: Biometry.current.symbol)
                    Label("Encrypted before syncing", systemImage: "lock.shield")
                    Label("Clipboard expires after 60 seconds", systemImage: "doc.on.clipboard")
                } header: { Text("Privacy") } footer: {
                    Text("Copying makes a password temporarily available to the app you paste into. Copies stay on this iPhone and do not use Universal Clipboard.")
                }
                Section {
                    Text(LB("Use the recovery key you saved when creating this notebook to open it on a new device or after resetting Face ID. PassBy cannot recover lost keys."))
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    if let shownRecovery {
                        Text(shownRecovery).font(.system(.body, design: .monospaced)).lineSpacing(6)
                            .privacySensitive()
                        Button {
                            session.copy(shownRecovery, label: L("Recovery key copied for 60 seconds"))
                        } label: { Label("Copy recovery key", systemImage: "doc.on.doc") }
                        Button("Hide recovery key") { self.shownRecovery = nil }
                    } else {
                        Button { reveal() } label: { OperationLabel(title: "Show recovery key", working: revealing) }
                            .disabled(revealing)
                    }
                    if let revealMessage {
                        Text(revealMessage).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                } header: { Text("Recovery") } footer: {
                    Text(LB("Showing the key requires Face ID again. Anyone with it can open your notebook on another device."))
                }
                Section {
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        HStack {
                            Label("Language", systemImage: "globe")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                        }
                        .foregroundStyle(Palette.ink)
                    }
                } footer: {
                    Text("Choose English or Simplified Chinese in iOS Settings for PassBy. If Language is missing, add the language in General > Language & Region first.")
                }
                Section {
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }
                    Link("Support", destination: URL(string: "https://passby.tenon.asia/support/")!)
                    Link("Email support", destination: URL(string: "mailto:support@tenonai.cn?subject=PassBy%20Support")!)
                    NavigationLink("About PassBy") { AboutPassByView() }
                }
                Section {
                    Button("Lock notebook") { session.lock() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear { shownRecovery = nil }
            .alert("Enable web access?", isPresented: $confirmWebAccess) {
                Button("Cancel", role: .cancel) {}
                Button("Enable web access") { sync(enableWeb: true) }
            } message: {
                Text("Sync this iPhone’s encrypted notebook with your current Apple Account so it can open on the web. Your entries and recovery key stay the same.")
            }
        }
    }
    private func reveal() {
        guard !revealing else { return }
        revealing = true
        revealMessage = nil
        Task {
            defer { revealing = false }
            do { shownRecovery = try await session.revealRecoveryKey() }
            catch { revealMessage = error.localizedDescription }
        }
    }

    private func sync(enableWeb: Bool = false) {
        guard !syncing, session.syncStatus != .syncing else { return }
        syncing = true
        Task {
            defer { syncing = false }
            if enableWeb { await session.enableWebAccess() }
            else { await session.syncNow() }
        }
    }

}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var session: VaultSession
    @State private var selected: DeletedEntry?

    var body: some View {
        Group {
            if session.recentlyDeleted.isEmpty {
                ContentUnavailableView("No recently deleted passwords", systemImage: "trash")
            } else {
                List {
                    Section {
                        ForEach(session.recentlyDeleted.sorted { $0.deletedAt > $1.deletedAt }) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.entry.title).font(.body.weight(.semibold)).lineLimit(1)
                                    Text(String(format: L("Deleted %@"),
                                        item.deletedAt.formatted(date: .abbreviated, time: .omitted)))
                                        .font(.subheadline).foregroundStyle(Palette.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                .foregroundStyle(Palette.ink)
                            }
                            .privacySensitive()
                        }
                    } footer: { Text("Kept for 30 days on this iPhone, then removed automatically.") }
                }
                .listStyle(.insetGrouped)
            }
        }
        .scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("Recently Deleted").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(selected?.entry.title ?? "", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }
        ), titleVisibility: .visible) {
            Button("Restore password") {
                if let selected { _ = session.restoreDeleted(selected.id) }
                selected = nil
            }
            Button("Delete now") {
                if let selected { _ = session.purgeDeleted(selected.id) }
                selected = nil
            }
        } message: { Text("Restoring returns it to your notebook on all synced devices. Deleting now removes this iPhone’s copy.") }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Privacy policy").font(.largeTitle.weight(.semibold))
                Text("Effective November 3, 2026 · Zeng Deyang")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                policySection("Your notebook", "Titles, accounts, passwords, notes and folders are encrypted on your device using AES-256-GCM before they are synced to your private iCloud database. PassBy has no developer-operated password server, advertising or analytics SDK.")
                policySection("Tenon Account", "Tenon manages your sign-in methods. PassBy account sessions last up to 30 days after verification. A rotating sign-in credential in this iPhone’s device-only Keychain securely renews the session. Closing the app does not sign you out. Sign out, credential revocation or 30 days without renewal may require a new sign-in. Face ID is still required to open the notebook, including offline. No passwords or recovery keys are sent to the account service.")
                policySection("Account information", "Tenon processes your email, display name, account identifier and login security records for authentication and account management. PassBy receives verified identity details to establish and securely renew its account session. These are linked to your account and are not used for advertising or tracking. Notebook contents and recovery keys are never sent to Tenon.")
                Link("Tenon Account privacy notice", destination: URL(string: "https://account.tenon.asia/account/privacy.html")!)
                policySection("Apple Account and Face ID", "Your system Apple Account identifies private notebook storage. PassBy does not receive your Apple password. Apple may share identity information with Tenon when you use it to sign in. Face ID is handled by iOS; PassBy receives authentication results, never your facial data.")
                policySection("Keys and recovery", "The local encryption key is protected by the device Keychain and current Face ID enrollment. Your recovery key is never uploaded. Save it outside PassBy. Without a working device key or your recovery key, your notebook cannot be decrypted by the developer.")
                policySection("Clipboard and drafts", "Copied values stay on this device and expire after 60 seconds. The app you paste into can read them. Unfinished entries are saved as encrypted local drafts and are not synced to iCloud.")
                policySection("Retention and deletion", "Delete entries and folders inside PassBy and allow iCloud sync to finish to apply those deletions to your notebook. Each iPhone keeps deleted passwords encrypted in Recently Deleted for 30 days without syncing them; you can delete them sooner there. Removing the app deletes its local files, but does not delete the iCloud notebook. Apple manages iCloud storage and service metadata under its own privacy policy.")
                Text("To keep our network secure, our servers record access and security logs: the time, IP address and page requested, without URL parameters. These logs are deleted automatically after 6 months.")
                    .foregroundStyle(Palette.secondary)
                Text("Delete your Tenon Account from Settings. Tenon verifies your identity and asks you to confirm before deleting central account information and revoking available Apple sign-in tokens. This affects all Tenon products. Your Apple-stored notebook and recovery key are managed separately and are not deleted by Tenon.")
                    .foregroundStyle(Palette.secondary)
                policySection("Support and your choices", "You can contact support@tenonai.cn for technical or privacy questions. Any details you voluntarily send are used to answer your request. Never send passwords, recovery keys, Apple verification codes or device passcodes.")
                Link("Online privacy policy", destination: URL(string: "https://passby.tenon.asia/privacy/")!)
                Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Palette.paper).navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LB(title)).font(.headline)
            Text(LB(body)).font(.body).foregroundStyle(Palette.secondary)
        }
    }
}

struct AboutPassByView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NotebookTitle()
                LabeledContent("Version", value: version).font(.subheadline).foregroundStyle(Palette.secondary)
                Text("PassBy is a simple password notebook. Keep titles, accounts, passwords and notes together, organize them in folders, and generate strong passwords to copy into other apps.")
                Text(LB("Your notebook is encrypted on your device before syncing to Apple private storage. It locks whenever you leave; Face ID unlocks it. Web access uses your recovery key to decrypt the same notebook in the browser."))
                    .foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Publisher").font(.footnote).foregroundStyle(Palette.secondary)
                    HStack(spacing: 10) {
                        Image("TenonMark").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text("榫卯 Tenon AI")
                    }
                    Link("tenon.asia", destination: URL(string: "https://tenon.asia/")!)
                }
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            .frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .navigationTitle("About PassBy").navigationBarTitleDisplayMode(.inline)
    }
}
