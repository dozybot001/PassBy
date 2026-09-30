import SwiftUI

private enum FolderFilter: Hashable {
    case all, unfiled, folder(UUID)
}

struct LibraryView: View {
    @EnvironmentObject private var session: VaultSession
    @State private var search = ""
    @State private var filter: FolderFilter = .all
    @State private var editor: VaultEntry?
    @State private var showFolders = false
    @State private var showSettings = false

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        folderChip("All", count: session.vault.entries.count, value: .all)
                        folderChip("Unfiled", count: session.vault.entries.filter { $0.folderID == nil }.count, value: .unfiled)
                        ForEach(session.vault.folders) { folder in
                            folderChip(folder.name,
                                count: session.vault.entries.filter { $0.folderID == folder.id }.count,
                                value: .folder(folder.id), literal: true)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12)
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
                            NavigationLink(value: entry.id) {
                                HStack(spacing: 14) {
                                    Text(String(entry.title.prefix(1)).uppercased())
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(Palette.accent)
                                        .frame(width: 44, height: 44)
                                        .background(Palette.rule.opacity(0.4), in: Circle())
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                                        Text(entry.account.isEmpty ? L("No account added") : entry.account)
                                            .font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(1)
                                    }
                                    .padding(.vertical, 10)
                                }.privacySensitive()
                            }
                            .listRowBackground(Palette.paper)
                            .listRowSeparatorTint(Palette.rule)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background(Palette.paper)
            .navigationTitle("PassBy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                NotebookControls(search: $search, folders: { showFolders = true }, newPassword: {
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
            .padding(.horizontal, 14).padding(.vertical, 12)
            .foregroundStyle(filter == value ? Palette.paper : Palette.ink)
            .background(filter == value ? Palette.ink : Palette.rule.opacity(0.35), in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
}

struct NotebookControls: View {
    @Binding var search: String
    let folders: () -> Void
    let newPassword: () -> Void
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: folders) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .frame(width: height, height: height)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modifier(ControlSurface(circle: true))
                .accessibilityLabel("Manage folders")

                Button(action: newPassword) {
                    Label("New password", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.paper)
                .modifier(ControlSurface(prominent: true))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("Search titles or accounts", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
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
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Palette.paper)
    }
}

private struct ControlSurface: ViewModifier {
    var circle = false
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if circle {
                content.glassEffect(.regular.interactive(), in: Circle())
            } else if prominent {
                content.glassEffect(.regular.tint(Palette.ink).interactive(), in: Capsule())
            } else {
                content.glassEffect(.regular, in: Capsule())
            }
        } else if circle {
            content.background(Palette.rule.opacity(0.4), in: Circle())
        } else {
            content.background(prominent ? Palette.ink : Palette.rule.opacity(0.4), in: Capsule())
        }
    }
}

#Preview("Notebook controls") {
    VStack {
        Spacer()
        NotebookControls(search: .constant(""), folders: {}, newPassword: {})
    }
    .background(Palette.paper).tint(Palette.accent).preferredColorScheme(.dark)
}
