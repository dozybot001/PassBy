import SwiftUI

/// What the AI grouping pages show and do. It lives as long as the AI grouping page. Nothing is
/// sent until the person taps Send on the page that shows the request.
@MainActor
final class AiModel: ObservableObject {
    enum Stage { case preview, result }

    /// Nil while AI grouping is off.
    @Published private(set) var config: AiSettings.Config?
    @Published private(set) var hasKey: Bool
    @Published private(set) var draft: AiGrouping.Draft?
    @Published private(set) var rows: [AiGrouping.Row] = []
    @Published private(set) var working = false
    /// While waiting for the model: suggestions received so far, and seconds since Send.
    @Published private(set) var received = 0
    @Published private(set) var seconds = 0
    @Published private(set) var error: String?
    /// What the last Apply changed, until it is undone or the page is left.
    @Published private(set) var applied: AiGrouping.Applied?
    /// The page on top of the AI grouping page, if any.
    @Published var stage: Stage?

    private let settings: AiSettings
    private var task: Task<Void, Never>?

    init(settings: AiSettings = AiSettings()) {
        self.settings = settings
        config = settings.load()
        hasKey = settings.hasKey
    }

    /// Turns AI grouping on with the given address and model, or changes them. A key for another host is removed.
    @discardableResult
    func save(_ next: AiSettings.Config) -> Bool {
        guard settings.save(next) else {
            error = VaultError.storageFailed.localizedDescription
            return false
        }
        error = nil
        config = next
        hasKey = settings.hasKey
        return true
    }

    /// Turns AI grouping off and removes the API key and settings from this iPhone.
    func turnOff() {
        cancel()
        settings.turnOff()
        config = nil
        hasKey = false
        draft = nil
        rows = []
        error = nil
    }

    func saveKey(_ text: String) -> Bool {
        guard let authority = config.flatMap({ AiGrouping.endpoint($0.endpoint) })?.authority,
              let key = AiGrouping.apiKey(text) else { return false }
        guard settings.saveKey(key, host: authority) else {
            error = VaultError.storageFailed.localizedDescription
            return false
        }
        error = nil
        hasKey = true
        return true
    }

    func removeKey() {
        settings.removeKey()
        hasKey = false
    }

    /// Builds the request from titles and folder names and opens the page that shows it. Nothing is sent here.
    func prepare(session: VaultSession) {
        guard let config else { return }
        draft = AiGrouping.draft(vault: session.vault, model: config.model)
        error = nil
        stage = .preview
    }

    /// Sends the request the preview page is showing, as it is shown, and opens the suggestions.
    func send(session: VaultSession) {
        guard let draft, !working else { return }
        working = true
        error = nil
        received = 0
        seconds = 0
        let settings = settings
        let count = draft.titles.count
        task = Task {
            // The page shows time passing, so a slow model does not look like a frozen app.
            let clock = Task {
                while (try? await Task.sleep(for: .seconds(1))) != nil { seconds += 1 }
            }
            var failure: String?
            do {
                let content = try await AiClient.send(settings: settings, approved: AiClient.Approved(body: draft.body)) { _, items in
                    Task { @MainActor in
                        if self.working { self.received = max(self.received, min(items, count)) }
                    }
                }
                let suggestions = try AiGrouping.parseContent(content, count: count)
                rows = AiGrouping.rows(vault: session.vault, draft: draft, suggestions: suggestions, unclearName: L("To clarify"))
                stage = .result
            } catch let problem as AiClient.Failure {
                hasKey = settings.hasKey
                failure = Self.text(problem)
            } catch {
                // Its own text is not shown or kept.
                failure = L("The AI’s answer was not in the agreed form. Nothing was changed. Try again, or use another model.")
            }
            clock.cancel()
            task = nil
            working = false
            error = failure
        }
    }

    /// The only sentences shown for a failed request. Nothing from the provider or the system is in them.
    static func text(_ failure: AiClient.Failure) -> String? {
        let status = failure.status ?? 0
        switch failure.problem {
        case .cancelled: return nil
        case .off, .address: return L("The endpoint is not right. Go back and check it. Nothing was sent.")
        case .noKey: return L("There is no usable API key. Go back and enter it again. Nothing was sent.")
        case .network: return L("Could not reach the provider. Check the network and the endpoint.")
        case .timeout: return L("The provider did not answer in time. Try again later.")
        case .redirect: return String(format: L("The provider asked to go to another address (status %d). PassBy does not follow redirects. Check the endpoint."), status)
        case .status:
            return String(format: status == 401 || status == 403
                ? L("The provider refused this API key (status %d). Check the key and your balance.")
                : L("The provider returned an error (status %d). Check the endpoint and the model name."), status)
        case .tooLarge: return L("The AI’s answer was not in the agreed form. Nothing was changed. Try again, or use another model.")
        }
    }

    /// Stops waiting for the model. Nothing has been changed, so there is nothing to undo.
    func cancel() {
        task?.cancel()
    }

    /// Applies the ticked suggestions in one save. Entries are renamed and moved; none is removed.
    func apply(_ picked: Set<UUID>, session: VaultSession) {
        let changes = rows.filter { picked.contains($0.entryID) }
            .map { AiGrouping.Change(entryID: $0.entryID, title: $0.title, folder: $0.folder) }
        guard let done = session.applyAiSuggestions(changes) else {
            error = VaultError.storageFailed.localizedDescription
            return
        }
        error = nil
        rows = []
        draft = nil
        stage = nil
        applied = done.before.isEmpty ? nil : done
    }

    func undo(session: VaultSession) {
        guard let done = applied else { return }
        if session.undoAiSuggestions(done) { applied = nil }
    }

    /// Leaving the preview or the suggestions: the request is given up and what was shown is forgotten.
    func leaveStage() {
        cancel()
        error = nil
    }
}

/// The two sentences that say what the model gets, shown wherever something is about to be sent.
private struct OnlyTitles: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The AI gets titles and folder names only.").fontWeight(.semibold)
            Text("The account, password and notes fields are never sent. Before each send, you can see everything that will go out.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// AI grouping's own page: what it does, the switch, and where it sends. It is off until the person
/// turns it on here and confirms; turning it off removes the API key and the settings.
struct AiView: View {
    @EnvironmentObject private var session: VaultSession
    @StateObject private var model = AiModel()
    @State private var confirmOn = false
    @State private var confirmOff = false
    @State private var endpoint = AiGrouping.deepSeekEndpoint
    @State private var modelName = AiGrouping.deepSeekModel
    @State private var key = ""
    @State private var revealed = false

    private var trimmedEndpoint: String { endpoint.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { modelName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parsed: AiGrouping.Endpoint? { AiGrouping.endpoint(endpoint) }
    private var changed: Bool {
        guard let config = model.config else { return false }
        return trimmedEndpoint != config.endpoint || trimmedModel != config.model
    }
    private var hostChanges: Bool {
        guard let config = model.config, let parsed else { return false }
        return parsed.authority != AiGrouping.endpoint(config.endpoint)?.authority
    }

    var body: some View {
        List {
            Section {
                Text("Lets an AI model you choose sort your passwords into folders by their titles, and suggest tidier titles. It sends to the provider you choose only when you tap Send, and it is off by default.")
                OnlyTitles()
                if let applied = model.applied {
                    HStack {
                        Label(String(format: L("Applied %d suggestions"), applied.before.count), systemImage: "checkmark")
                        Spacer()
                        Button("Undo") { model.undo(session: session) }.buttonStyle(.borderless).fontWeight(.semibold)
                    }
                }
                if model.stage == nil, let error = model.error { Text(error).fontWeight(.semibold) }
            }
            Section {
                Toggle(isOn: Binding(get: { model.config != nil }, set: { if $0 { confirmOn = true } else { confirmOff = true } })) {
                    Text("Turn on AI grouping")
                }.tint(Palette.control)
            } footer: {
                Text("When on, PassBy sends to the provider only when you tap Send. Turning it off deletes the API key and these settings.")
            }
            if model.config != nil {
                provider
                apiKey
                Section {
                    Button { model.prepare(session: session) } label: { Label("Start grouping", systemImage: "sparkles") }
                        .disabled(!model.hasKey || changed || session.vault.entries.isEmpty)
                } footer: { Text("The next page shows what will be sent. Nothing is sent yet.") }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("AI grouping").navigationBarTitleDisplayMode(.inline)
        .onAppear { adopt(model.config) }
        .navigationDestination(isPresented: Binding(get: { model.stage != nil }, set: { if !$0 { model.stage = nil } })) {
            AiStageView(model: model)
        }
        .alert("Turn on AI grouping?", isPresented: $confirmOn) {
            Button("Cancel", role: .cancel) {}
            Button("Turn on") {
                let next = AiSettings.Config(endpoint: AiGrouping.deepSeekEndpoint, model: AiGrouping.deepSeekModel)
                if model.save(next) { adopt(next) }
            }
        } message: {
            Text([L("Once this is on, PassBy sends one request to the provider each time you tap Send, and at no other time."),
                  L("Only your entries’ titles and your folder names are sent. Accounts, passwords and notes are never sent."),
                  L("What you send goes from this iPhone straight to the provider you entered, not through us. The service is provided by that provider under its own terms and privacy policy; with a provider outside mainland China, the content is sent abroad. An account name or a person’s name written into a title is sent along with it."),
                  L("The API key is stored encrypted on this iPhone only.")].joined(separator: "\n\n"))
        }
        .alert("Turn off AI grouping?", isPresented: $confirmOff) {
            Button("Cancel", role: .cancel) {}
            Button("Turn off") {
                model.turnOff()
                key = ""
                adopt(nil)
            }
        } message: {
            Text("This deletes the API key and provider settings saved on this iPhone. Your notebook is not affected. Once off, PassBy no longer connects to the provider.")
        }
    }

    private func adopt(_ config: AiSettings.Config?) {
        endpoint = config?.endpoint ?? AiGrouping.deepSeekEndpoint
        modelName = config?.model ?? AiGrouping.deepSeekModel
    }

    @ViewBuilder private var provider: some View {
        Section {
            TextField("Endpoint", text: $endpoint)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Model name", text: $modelName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if changed {
                Button {
                    let next = AiSettings.Config(endpoint: trimmedEndpoint, model: trimmedModel)
                    if model.save(next) { adopt(next) }
                } label: { Label("Save", systemImage: "checkmark") }
                    .disabled(parsed == nil || trimmedModel.isEmpty)
            }
            if trimmedEndpoint != AiGrouping.deepSeekEndpoint || trimmedModel != AiGrouping.deepSeekModel {
                Button {
                    endpoint = AiGrouping.deepSeekEndpoint
                    modelName = AiGrouping.deepSeekModel
                } label: { Label("Use the DeepSeek defaults", systemImage: "arrow.counterclockwise") }
            }
        } header: { Text("Model provider") } footer: {
            if parsed == nil {
                Text("The endpoint has to start with https://.").foregroundStyle(Palette.ink)
            } else if hostChanges && model.hasKey {
                Text("The provider’s address has changed. Saving deletes the API key you entered, and you will need to enter one again.")
                    .foregroundStyle(Palette.ink)
            } else {
                Text("The endpoint filled in by default is DeepSeek’s; you can change it to any provider with a compatible chat/completions endpoint. The service is provided by that provider under its own terms and privacy policy; with a provider outside mainland China, your titles are sent abroad.")
            }
        }
    }

    @ViewBuilder private var apiKey: some View {
        Section {
            if model.hasKey {
                HStack {
                    Label("API key saved", systemImage: "key")
                    Spacer()
                    Button("Delete") { model.removeKey() }.buttonStyle(.borderless)
                }
            } else {
                HStack {
                    Group {
                        if revealed { TextField("API key", text: $key) } else { SecureField("API key", text: $key) }
                    }
                    .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless).accessibilityLabel(L(revealed ? "Hide API key" : "Show API key"))
                }
                if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && AiGrouping.apiKey(key) == nil {
                    Text("An API key can hold only letters, digits and symbols, with no spaces, line breaks or other characters. Check that nothing else was copied with it.")
                        .fontWeight(.semibold)
                }
                Button {
                    if model.saveKey(key) { key = ""; revealed = false }
                } label: { Label("Save API key", systemImage: "checkmark") }
                    .disabled(AiGrouping.apiKey(key) == nil || changed)
            }
        } header: { Text("API key") } footer: {
            Text("The API key is one you get from the provider yourself; its charges are between you and the provider. It is kept in this iPhone’s keychain, does not move to another device with a backup, is left out of export files, and is not shown again once saved.")
        }
    }
}

/// The page on top of AI grouping: first what is about to be sent, then the suggestions.
private struct AiStageView: View {
    @ObservedObject var model: AiModel

    var body: some View {
        Group {
            if model.stage == .result { AiResultView(model: model) } else { AiPreviewView(model: model) }
        }
        .onDisappear { model.leaveStage() }
    }
}

/// Everything that is about to leave the iPhone, before it does. Send sends exactly what is shown here.
private struct AiPreviewView: View {
    @EnvironmentObject private var session: VaultSession
    @ObservedObject var model: AiModel
    @State private var showBody = false

    var body: some View {
        Group {
            if let draft = model.draft {
                List {
                    Section {
                        Text(String(format: L("The text below will be sent to the provider you set up (%@)."),
                                    model.config.flatMap { AiGrouping.endpoint($0.endpoint) }?.host ?? ""))
                        OnlyTitles()
                        if draft.leftOut > 0 {
                            Text(String(format: L("At most %d titles are sent at once. %d more are not sent this time."), draft.titles.count, draft.leftOut))
                        }
                        if !draft.blankIDs.isEmpty {
                            Text(String(format: L("%d entries have no title. They are not sent and go straight to To clarify."), draft.blankIDs.count))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    Section(String(format: L("Titles (%d)"), draft.titles.count)) {
                        ForEach(Array(draft.titles.enumerated()), id: \.offset) { Text($0.element) }
                    }
                    .privacySensitive()
                    Section(String(format: L("Existing folders (%d)"), draft.folders.count)) {
                        if draft.folders.isEmpty { Text("No folders yet.").foregroundStyle(Palette.secondary) }
                        ForEach(Array(draft.folders.enumerated()), id: \.offset) { Text($0.element) }
                    }
                    .privacySensitive()
                    Section {
                        Button { showBody.toggle() } label: {
                            Label(L(showBody ? "Hide the full request" : "Show the full request"), systemImage: "doc.text")
                        }
                        if showBody {
                            Text("This is the request exactly as it will be sent. It starts with a fixed instruction, followed by the titles and folder names above. The API key goes in a request header and is not shown here.")
                                .font(.footnote).foregroundStyle(Palette.secondary)
                            Text(draft.body).font(.footnote.monospaced()).privacySensitive()
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) { controls(draft) }
            } else {
                ContentUnavailableView("Nothing to send", systemImage: "sparkles")
            }
        }
        .scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("Check what will be sent").navigationBarTitleDisplayMode(.inline)
    }

    private func controls(_ draft: AiGrouping.Draft) -> some View {
        VStack(spacing: 12) {
            if model.working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(model.received == 0
                        ? String(format: L("Sent. Waiting for the model to start answering… (%d s)"), model.seconds)
                        : String(format: L("The model is answering: %d of %d suggestions received (%d s)"), model.received, draft.titles.count, model.seconds))
                        .font(.subheadline).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            if let error = model.error { InlineError(text: error).frame(maxWidth: .infinity, alignment: .leading) }
            Button { model.send(session: session) } label: { Label("Send", systemImage: "arrow.up") }
                .buttonStyle(PrimaryButton())
                .disabled(model.working || draft.titles.isEmpty)
            if model.working {
                Button("Stop waiting") { model.cancel() }.frame(minHeight: ControlMetrics.height)
            }
        }
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
        .background(Palette.paper)
    }
}

/// The model's suggestions, one entry a row. Nothing changes until the ticked ones are applied.
private struct AiResultView: View {
    @EnvironmentObject private var session: VaultSession
    @ObservedObject var model: AiModel
    @State private var picked: Set<UUID>
    @State private var editing: VaultEntry?

    init(model: AiModel) {
        self.model = model
        _picked = State(initialValue: Set(model.rows.map(\.entryID)))
    }

    var body: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView("Nothing to change", systemImage: "checkmark",
                                       description: Text("The AI finds the current titles and folders fine."))
            } else {
                let clear = model.rows.filter { !$0.unclear }
                let unclear = model.rows.filter(\.unclear)
                List {
                    Section {
                        Text("Tick the suggestions to accept. Nothing changes until you tap Apply. Only titles and folders change; no password is deleted.")
                            .foregroundStyle(Palette.secondary)
                        HStack(spacing: 24) {
                            Button { picked = Set(model.rows.map(\.entryID)) } label: { Label("Select all", systemImage: "checkmark") }
                            Button { picked = [] } label: { Label("Select none", systemImage: "xmark") }
                        }
                        .buttonStyle(.borderless)
                    }
                    if !clear.isEmpty {
                        Section(String(format: L("Folders and titles (%d)"), clear.count)) {
                            ForEach(clear) { row($0) }
                        }
                    }
                    if !unclear.isEmpty {
                        Section {
                            ForEach(unclear) { row($0) }
                        } header: { Text(String(format: L("To clarify (%d)"), unclear.count)) } footer: {
                            Text("These titles do not say what they are for. Ticked ones go into the To clarify folder; or tap the pencil to edit a title first.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        if let error = model.error { InlineError(text: error).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { model.apply(picked, session: session) } label: {
                            Label(String(format: L("Apply %d"), picked.count), systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButton()).disabled(picked.isEmpty)
                    }
                    .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
                    .background(Palette.paper)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("The AI’s suggestions").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EntryEditorView(entry: $0, isNew: false) }
    }

    private func row(_ row: AiGrouping.Row) -> some View {
        let checked = picked.contains(row.entryID)
        let shown = row.oldTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("(no title)") : row.oldTitle
        return HStack(spacing: 12) {
            Button {
                if checked { picked.remove(row.entryID) } else { picked.insert(row.entryID) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square").font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title.map { String(format: L("%@ → %@"), shown, $0) } ?? shown).fontWeight(.semibold)
                        if let folder = row.folder {
                            Label(String(format: L("%@ → %@"), row.oldFolder ?? L("Unfiled"), folder), systemImage: "folder")
                                .font(.subheadline).foregroundStyle(Palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 40).foregroundStyle(Palette.ink).contentShape(Rectangle())
            }
            .accessibilityAddTraits(checked ? .isSelected : [])
            if row.unclear, let entry = session.vault.entries.first(where: { $0.id == row.entryID }) {
                Button { editing = entry } label: { Image(systemName: "pencil") }
                    .accessibilityLabel(Text("Edit title"))
            }
        }
        .buttonStyle(.borderless)
        .privacySensitive()
    }
}
