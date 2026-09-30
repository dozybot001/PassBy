import SwiftUI

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
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
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
                    Label(session.isAppleAccountLinked ? L("Linked to your Apple Account") : L("Apple Account unavailable"),
                          systemImage: "person.crop.circle.badge.checkmark")
                    Text("PassBy uses the Apple Account signed in to iCloud on this iPhone. It does not request your Apple password, name or email.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Text("Changing the iCloud account locks this notebook. Each account has separate encrypted data. A new device also needs your recovery key.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                } header: { Text("Apple Account") }
                Section("iCloud") {
                    LabeledContent("Status", value: status)
                    Button("Sync now") { Task { await session.syncNow() } }
                        .disabled(session.syncStatus == .syncing)
                    if let message = session.syncMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                Section {
                    Label("Locked whenever you leave", systemImage: "faceid")
                    Label("Encrypted on device and in iCloud", systemImage: "lock.shield")
                    Label("Clipboard expires after 60 seconds", systemImage: "doc.on.clipboard")
                } header: { Text("Privacy") } footer: {
                    Text("Copying makes a password temporarily available to the app you paste into. Copies stay on this iPhone and do not use Universal Clipboard.")
                }
                Section("Recovery") {
                    Text("Use the recovery key you saved when creating this notebook to open it on a new device or after resetting Face ID. PassBy cannot recover lost keys.")
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                }
                Section("About PassBy") {
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }
                    Link("Support", destination: URL(string: "https://tenon.asia/passby/support")!)
                    Link("Email support", destination: URL(string: "mailto:support@tenonai.cn?subject=PassBy%20Support")!)
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                }
                Section {
                    Button("Lock notebook") { session.lock() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Privacy policy").font(.largeTitle.weight(.semibold))
                Text("Effective October 1, 2026 · Zeng Deyang")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                policySection("Your notebook", "Titles, accounts, passwords, notes and folders are encrypted on your device using AES-256-GCM before they are synced to your private iCloud database. PassBy has no developer-operated password server, advertising or analytics SDK.")
                policySection("Apple Account and Face ID", "Your system iCloud account identifies the notebook. PassBy does not receive your Apple password, name or email. Face ID is handled by iOS; PassBy receives authentication results, never your facial data.")
                policySection("Keys and recovery", "The local encryption key is protected by the device Keychain and current Face ID enrollment. Your recovery key is never uploaded. Save it outside PassBy. Without a working device key or your recovery key, your notebook cannot be decrypted by the developer.")
                policySection("Clipboard and drafts", "Copied values stay on this device and expire after 60 seconds. The app you paste into can read them. Unfinished entries are saved as encrypted local drafts and are not synced to iCloud.")
                policySection("Retention and deletion", "Delete entries and folders inside PassBy and allow iCloud sync to finish to apply those deletions to your notebook. Removing the app deletes its local files, but does not delete the iCloud notebook. Apple manages iCloud storage and service metadata under its own privacy policy.")
                policySection("Support and your choices", "You can contact support@tenonai.cn for technical or privacy questions. Any details you voluntarily send are used to answer your request. Never send passwords, recovery keys, Apple verification codes or device passcodes.")
                Link("Online privacy policy", destination: URL(string: "https://tenon.asia/passby/privacy")!)
                Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Palette.paper).navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(Palette.secondary)
        }
    }
}
