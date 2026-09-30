import SwiftUI

private enum FolderFilter: Hashable {
    case all, unfiled, folder(UUID)
}

struct LibraryView: View {
    @EnvironmentObject private var session: VaultSession
    @State private var search = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var filter: FolderFilter = .all
    @State private var editor: VaultEntry?
    @State private var showFolders = false
    @State private var showSettings = false
    @State private var showGenerator = false

    private var entries: [VaultEntry] {
        session.vault.entries.filter { entry in
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .unfiled: matches = entry.folderID == nil
            case .folder(let id): matches = entry.folderID == id
            }
            return matches && (search.isEmpty || entry.title.localizedCaseInsensitiveContains(search)
                || entry.account.localizedCaseInsensitiveContains(search))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NotebookHeader(search: {
                    showSearch.toggle()
                    searchFocused = showSearch
                    if !showSearch { search = "" }
                }, generator: { showGenerator = true }, settings: { showSettings = true })
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            folderChip("All", count: session.vault.entries.count, value: .all)
                            folderChip("Unfiled", count: session.vault.entries.filter { $0.folderID == nil }.count, value: .unfiled)
                            ForEach(session.vault.folders) { folder in
                                folderChip(folder.name,
                                    count: session.vault.entries.filter { $0.folderID == folder.id }.count,
                                    value: .folder(folder.id), literal: true)
                            }
                        }.padding(.horizontal, 28).padding(.vertical, 12)
                    }
                    .opacity(showSearch ? 0 : 1)
                    .accessibilityHidden(showSearch)
                    if entries.isEmpty {
                        ContentUnavailableView {
                            Label(L(search.isEmpty ? "Your notebook starts here" : "No matching passwords"),
                                  systemImage: search.isEmpty ? "note.text" : "magnifyingglass")
                        } description: {
                            Text(L(search.isEmpty ? "Add an account and password. Keep the details in one place." : "Try a different title or account."))
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(entries) { entry in
                                NavigationLink(value: entry.id) {
                                    LibraryEntryRow(entry: entry)
                                }
                                .listRowBackground(Palette.paper)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                            }
                        }
                        .listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }
                .overlay(alignment: .top) {
                    if showSearch {
                        NotebookSearchOverlay(search: $search, focused: $searchFocused) {
                            showSearch = false
                            searchFocused = false
                            search = ""
                        }
                        .onAppear { searchFocused = true }
                    }
                }
            }
            .background(Palette.paper)
            .safeAreaInset(edge: .bottom) {
                NotebookControls(folders: { showFolders = true }, newPassword: {
                        let id: UUID?
                        if case .folder(let value) = filter { id = value } else { id = nil }
                        editor = VaultEntry(folderID: id)
                })
            }
            .navigationDestination(for: UUID.self) { id in EntryDetailView(id: id) }
            .sheet(item: $editor) { entry in
                EntryEditorView(entry: entry, isNew: !session.vault.entries.contains { $0.id == entry.id })
            }
            .sheet(isPresented: $showFolders) { FoldersView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showGenerator) {
                PasswordGeneratorView(copyOnly: true) { password in
                    session.copy(password, label: L("Password copied for 60 seconds"))
                    return true
                }
            }
            .onChange(of: session.vault.folders) { _, folders in
                if case .folder(let id) = filter, !folders.contains(where: { $0.id == id }) { filter = .all }
            }
            .task {
                if let draft = session.draft { editor = draft }
                // Sync remote edits while the notebook is open. No sync task reads
                // a decrypted notebook when the app is locked.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    await session.syncNow()
                }
            }
        }
    }

    private func folderChip(_ name: String, count: Int, value: FolderFilter, literal: Bool = false) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 7) {
                Text(literal ? name : L(name)).font(.subheadline.weight(.medium))
                Text("\(count)").font(.caption).monospacedDigit().opacity(0.7)
            }
        }.buttonStyle(SecondaryButton(selected: filter == value))
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
}

struct LibraryEntryRow: View {
    let entry: VaultEntry

    var body: some View {
        HStack(spacing: 14) {
            Text(String(entry.title.prefix(1)).uppercased())
                .font(.title3.weight(.medium)).foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.rule.opacity(0.4), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                Text(entry.account.isEmpty ? L("No account added") : entry.account)
                    .font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .privacySensitive()
    }
}

struct NotebookControls: View {
    let folders: () -> Void
    let newPassword: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: folders) { Image(systemName: "folder.badge.plus") }
                .buttonStyle(IconButton()).accessibilityLabel("Manage folders")
            Button(action: newPassword) { Label("New password", systemImage: "plus") }
                .buttonStyle(PrimaryButton())
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(Palette.paper)
    }
}

struct NotebookSearchField: View {
    @Binding var search: String
    var focused: FocusState<Bool>.Binding
    @ScaledMetric(relativeTo: .body) private var height = ControlMetrics.height

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
            TextField("Search titles or accounts", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused(focused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: height)
        .modifier(ControlSurface())
    }
}

struct NotebookSearchOverlay: View {
    @Binding var search: String
    var focused: FocusState<Bool>.Binding
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NotebookSearchField(search: $search, focused: focused)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(IconButton()).accessibilityLabel("Close search")
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
    }
}

#Preview("Notebook controls") {
    @Previewable @State var showSearch = false
    @Previewable @State var search = ""
    @Previewable @FocusState var focused: Bool
    NavigationStack {
        VStack(spacing: 0) {
            NotebookHeader(search: { showSearch.toggle() }, generator: {}, settings: {})
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button("All") {}.buttonStyle(SecondaryButton(selected: true))
                    Button("Unfiled") {}.buttonStyle(SecondaryButton())
                    Spacer()
                }.padding(.horizontal, 28).padding(.vertical, 12)
                .opacity(showSearch ? 0 : 1)
                List {
                    ForEach([VaultEntry(title: "Mail", account: "name@example.com"),
                             VaultEntry(title: "Travel", account: "traveler"),
                             VaultEntry(title: "Work", account: "name@example.com")]) { entry in
                        NavigationLink {} label: { LibraryEntryRow(entry: entry) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                            .listRowBackground(Palette.paper).listRowSeparator(.hidden)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
            .overlay(alignment: .top) {
                if showSearch {
                    NotebookSearchOverlay(search: $search, focused: $focused) {
                        showSearch = false
                        search = ""
                    }
                }
            }
            NotebookControls(folders: {}, newPassword: {})
        }
        .background(Palette.paper)
    }
    .tint(Palette.accent).preferredColorScheme(.dark)
}
