import SwiftUI

struct EntryDetailView: View {
    let id: UUID
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var editing: VaultEntry?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let entry = session.vault.entries.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.title).font(.largeTitle.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let folderID = entry.folderID,
                               let folder = session.vault.folders.first(where: { $0.id == folderID }) {
                                Label(folder.name, systemImage: "folder").font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                        }.padding(.bottom, 8)
                        credential("Account", value: entry.account, hidden: false) {
                            session.copy(entry.account, label: L("Account copied for 60 seconds"))
                        }
                        credential("Password", value: entry.password, hidden: !revealed, isPassword: true) {
                            session.copy(entry.password, label: L("Password copied for 60 seconds"))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notes").font(.subheadline).foregroundStyle(Palette.secondary)
                            Text(entry.notes.isEmpty ? L("No notes added") : entry.notes)
                                .font(.body).foregroundStyle(entry.notes.isEmpty ? Palette.secondary : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    .privacySensitive()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { editing = entry }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button { confirmDelete = true } label: {
                            Label("Delete password", systemImage: "trash")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Password removed", systemImage: "note.text")
            }
        }
        .background(Palette.paper).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EntryEditorView(entry: $0, isNew: false) }
        .confirmationDialog("Delete this password?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete password") {
                if session.deleteEntry(id) { dismiss() }
            }
        } message: { Text("This removes it from your notebook on all synced devices. This iPhone keeps a copy in Recently Deleted for 30 days.") }
        .onDisappear { revealed = false }
    }

    private func credential(_ label: LocalizedStringKey, value: String, hidden: Bool,
        isPassword: Bool = false, copy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.subheadline).foregroundStyle(Palette.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(value.isEmpty ? L("Not added") : hidden ? "••••••••••••" : value)
                    .font(isPassword ? .system(.body, design: .monospaced) : .body)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel(hidden && !value.isEmpty ? L("Password hidden") : value)
                if isPassword {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                    }.buttonStyle(IconButton())
                        .accessibilityLabel(L(revealed ? "Hide password" : "Show password"))
                }
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                }.buttonStyle(IconButton()).disabled(value.isEmpty)
                    .accessibilityLabel(L(isPassword ? "Copy password" : "Copy account"))
            }
        }
    }
}

struct EntryEditorView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State var entry: VaultEntry
    let isNew: Bool
    @State private var revealed = false
    @FocusState private var focused: Bool
    @State private var showGenerator = false
    @State private var editingActive = false
    @State private var showNewFolder = false
    @State private var folderName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("For example, personal email", text: $entry.title).focused($focused)
                }
                Section("Account") {
                    TextField("Username or email", text: $entry.account)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Password") {
                    HStack {
                        Group {
                            if revealed { TextField("Password", text: $entry.password) }
                            else { SecureField("Password", text: $entry.password) }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { showGenerator = true } label: {
                            Image(systemName: "die.face.5")
                        }.buttonStyle(IconButton()).accessibilityLabel("Generate strong password")
                        Button { revealed.toggle() } label: {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                        }.buttonStyle(IconButton())
                            .accessibilityLabel(L(revealed ? "Hide password" : "Show password"))
                    }
                }
                Section("Notes") {
                    TextEditor(text: $entry.notes).frame(minHeight: 110)
                }
                Section("Folder") {
                    Picker("Folder", selection: $entry.folderID) {
                        Text("Unfiled").tag(nil as UUID?)
                        ForEach(session.vault.folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    Button {
                        folderName = ""
                        showNewFolder = true
                    } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }
                }
                Section {
                    Text("Your draft is saved encrypted on this iPhone. After unlocking, tap New password to resume it.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle(L(isNew ? "New password" : "Edit password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if session.saveDraft(nil) { editingActive = false; dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if session.save(entry) { editingActive = false; dismiss() } }
                        .fontWeight(.semibold)
                        .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .privacySensitive()
            .alert("New folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $folderName)
                Button("Cancel", role: .cancel) { folderName = "" }
                Button("Save") {
                    if let id = session.createFolder(name: folderName) {
                        entry.folderID = id
                        _ = session.saveDraft(entry)
                    }
                    folderName = ""
                }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(isPresented: $showGenerator) {
                PasswordGeneratorView { password in
                    var updated = entry
                    updated.password = password
                    guard session.saveDraft(updated) else { return false }
                    entry = updated
                    session.copy(password, label: L("Password copied for 60 seconds"))
                    return true
                }
            }
            .onAppear { editingActive = true }
            .onChange(of: entry) { _, value in
                if editingActive { _ = session.saveDraft(value) }
            }
        }
        .onDisappear {
            if editingActive { _ = session.saveDraft(entry) }
            editingActive = false; entry = VaultEntry(); revealed = false; folderName = ""
        }
    }
}
