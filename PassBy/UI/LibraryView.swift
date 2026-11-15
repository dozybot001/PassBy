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
    @State private var showExport = false
    @State private var path: [UUID] = []

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

    private var unfiledCount: Int { session.vault.entries.filter { $0.folderID == nil }.count }

    var body: some View {
        NavigationStack(path: $path) {
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
                            // Shown only while some entry has no folder.
                            if unfiledCount > 0 {
                                folderChip("Unfiled", count: unfiledCount, value: .unfiled)
                            }
                            ForEach(session.vault.folders) { folder in
                                folderChip(folder.name,
                                    count: session.vault.entries.filter { $0.folderID == folder.id }.count,
                                    value: .folder(folder.id), literal: true)
                            }
                        }.padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
                    }
                    .opacity(showSearch ? 0 : 1)
                    .accessibilityHidden(showSearch)
                    if !session.pendingLegacy.isEmpty {
                        notice("Your notebook from the earlier version has not been moved yet.", icon: "arrow.right.doc.on.clipboard",
                               action: "Move it now", run: { session.migrationDeferred = false })
                    } else if session.showExportReminder {
                        notice(session.lastExportAt == nil ? "You have no backup yet. Export one and keep it somewhere else."
                               : "Your notebook changed since the last export, more than 30 days ago.",
                               icon: "square.and.arrow.up", action: "Export", run: { showExport = true },
                               dismiss: { session.dismissExportReminder() })
                    }
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
                                LibraryEntryRow(entry: entry, copyPassword: { copyPassword(entry) },
                                    copyAccount: { copyAccount(entry) }, view: { path.append(entry.id) })
                                .listRowBackground(Palette.paper)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: PageMetrics.horizontalPadding, bottom: 0, trailing: PageMetrics.horizontalPadding))
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
                        editor = session.draft ?? VaultEntry(folderID: id)
                })
            }
            .navigationDestination(for: UUID.self) { id in EntryDetailView(id: id) }
            .sheet(item: $editor) { entry in
                EntryEditorView(entry: entry, isNew: !session.vault.entries.contains { $0.id == entry.id })
            }
            .sheet(isPresented: $showFolders) { FoldersView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showExport) { ExportView() }
            .sheet(isPresented: $showGenerator) {
                PasswordGeneratorView(copyOnly: true) { password in
                    session.copy(password, label: L("Password copied for 60 seconds"))
                    return true
                }
            }
            .onChange(of: session.vault.folders) { _, folders in
                if case .folder(let id) = filter, !folders.contains(where: { $0.id == id }) { filter = .all }
            }
            .onChange(of: unfiledCount) { _, count in
                if filter == .unfiled, count == 0 { filter = .all }
            }
        }
    }

    private func copyPassword(_ entry: VaultEntry) {
        session.copy(entry.password, label: L("Password copied for 60 seconds"),
                     action: (L("View"), { path.append(entry.id) }))
    }

    private func copyAccount(_ entry: VaultEntry) {
        session.copy(entry.account, label: L("Account copied for 60 seconds"))
    }

    private func notice(_ text: LocalizedStringKey, icon: String, action: LocalizedStringKey, run: @escaping () -> Void,
                        dismiss: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.secondary).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Button(action, action: run).font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .foregroundStyle(Palette.secondary).accessibilityLabel("Dismiss")
            }
        }
        .padding(16)
        .background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.bottom, 8)
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

/// Tapping a row copies its password. The button at the end copies the
/// account; a long press offers both and the details page.
struct LibraryEntryRow: View {
    let entry: VaultEntry
    var copyPassword: () -> Void = {}
    var copyAccount: () -> Void = {}
    var view: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Button(action: copyPassword) {
                HStack(spacing: 14) {
                    Text(String(entry.title.prefix(1)).uppercased())
                        .font(.title3.weight(.medium)).foregroundStyle(Palette.accent)
                        .frame(width: 44, height: 44)
                        .background(Palette.rule.opacity(0.4), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                        Text(entry.account.isEmpty ? L("No account added") : entry.account)
                            .font(.callout).foregroundStyle(entry.account.isEmpty ? Palette.secondary : Palette.ink.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Copies the password")
            if !entry.account.isEmpty {
                Button(action: copyAccount) { Image(systemName: "person.crop.circle") }
                    .buttonStyle(IconButton()).accessibilityLabel("Copy account")
            }
        }
        .padding(.vertical, 10)
        .privacySensitive()
        .contextMenu {
            Button(action: copyAccount) { Label("Copy account", systemImage: "person.crop.circle") }
                .disabled(entry.account.isEmpty)
            Button(action: copyPassword) { Label("Copy password", systemImage: "doc.on.doc") }
            Button(action: view) { Label("View", systemImage: "doc.text.magnifyingglass") }
        }
        .accessibilityAction(named: Text("View"), view)
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
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
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
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
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
                }.padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
                .opacity(showSearch ? 0 : 1)
                List {
                    ForEach([VaultEntry(title: "Mail", account: "name@example.com"),
                             VaultEntry(title: "Travel", account: "traveler"),
                             VaultEntry(title: "Work", account: "name@example.com")]) { entry in
                        LibraryEntryRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 0, leading: PageMetrics.horizontalPadding, bottom: 0, trailing: PageMetrics.horizontalPadding))
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
