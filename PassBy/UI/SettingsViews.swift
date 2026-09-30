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
                        .buttonStyle(SecondaryButton())
                        .listRowBackground(Color.clear)
                } footer: { Text("Deleting a folder keeps its passwords in Unfiled.") }
            }
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
                Section {
                    Button("Lock notebook") { session.lock() }
                }
            }
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
