import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var showExport = false
    @State private var showImport = false
    @State private var aiOn = false

    private var lastExport: String {
        session.lastExportAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? L("Never")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { session.gateEnabled }, set: { value in Task { await session.setGate(value) } })) {
                        Label(Biometry.current == .none ? L("Ask for the passcode to open") : LB("Ask for Face ID to open"), systemImage: Biometry.current.symbol)
                    }.tint(Palette.control)
                    if !session.deviceHasLock {
                        Label("This iPhone has no passcode", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.secondary)
                    }
                } header: { Text("Lock") } footer: {
                    Text(session.deviceHasLock
                        ? LB("PassBy asks when you open it, and again after 5 minutes away. Without Face ID it asks for your iPhone passcode.")
                        : L("Without a passcode, iPhone does not encrypt your notebook file and anyone holding the phone can open PassBy. Set a passcode in iPhone Settings."))
                }
                Section {
                    LabeledContent("Last export", value: lastExport)
                    Button { showExport = true } label: { Label("Export notebook", systemImage: "square.and.arrow.up") }
                        .disabled(session.vault.entries.isEmpty)
                    Button { showImport = true } label: { Label("Import from a file", systemImage: "square.and.arrow.down") }
                } header: { Text("Backup") } footer: {
                    Text("PassBy has no account, so a backup is yours to keep. Export an encrypted file and store it somewhere else. Your notebook is also part of this iPhone’s own backups: turn on Advanced Data Protection for iCloud Backup, or use an encrypted computer backup, so nobody else can read it there.")
                }
                Section {
                    NavigationLink { SyncView() } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                } footer: {
                    Text("With another device on the same Wi-Fi. Nothing passes through our servers.")
                }
                Section {
                    NavigationLink { AiView() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI grouping")
                                Text(L(aiOn ? "On. Connects to the network when used" : "Off"))
                                    .font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                        } icon: { Image(systemName: "sparkles") }
                    }
                    .onAppear { aiOn = AiSettings().load() != nil }
                }
                Section {
                    NavigationLink { RecentlyDeletedView() } label: {
                        LabeledContent {
                            Text("\(session.recentlyDeleted.count)").monospacedDigit()
                        } label: { Label("Recently Deleted", systemImage: "trash") }
                    }
                } footer: {
                    Text("Deleted passwords stay on this iPhone for 30 days. They are not part of an export.")
                }
                Section {
                    Label("Kept on this iPhone", systemImage: "iphone")
                    Label("No account; nothing passes through our servers", systemImage: "wifi.slash")
                    Label("Clipboard expires after 60 seconds", systemImage: "doc.on.clipboard")
                } header: { Text("Privacy") } footer: {
                    Text("Copying makes a password temporarily available to the app you paste into. Copies stay on this iPhone and do not use Universal Clipboard.")
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
                    Link("Terms of Service", destination: PassByLinks.page("terms/"))
                    Link("Support", destination: PassByLinks.page("support/"))
                    Link("Email support", destination: SupportMail.url(subject: "PassBy Support"))
                    NavigationLink("About PassBy") { AboutPassByView() }
                }
                if session.gateEnabled && session.deviceHasLock {
                    Section {
                        Button { session.lock() } label: { Label("Lock notebook", systemImage: "lock") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showExport) { ExportView() }
            .sheet(isPresented: $showImport) { ImportView() }
        }
    }
}

/// Mail to support, with the app and system version filled in where the
/// person can see and remove them before sending.
enum SupportMail {
    static func url(subject: String) -> URL {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
        let body = "\n\nPassBy \(version), iOS \(UIDevice.current.systemVersion)"
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@tenonai.cn"
        parts.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return parts.url ?? URL(string: "mailto:support@tenonai.cn")!
    }
}

// MARK: - Export

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Writes the notebook to an encrypted file (docs/export-format.md). The code
/// or passphrase is shown once here and is not kept anywhere.
struct ExportView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var ownPassphrase = false
    @State private var code = ExportFormat.newCode()
    @State private var passphrase = ""
    @State private var showPassphrase = false
    @State private var working = false
    @State private var document: ExportDocument?
    @State private var showExporter = false
    @State private var saved = false
    @State private var error: String?

    private var problem: PassphraseProblem? { ExportFormat.passphraseProblem(passphrase) }
    private var typed: String { ownPassphrase ? passphrase : code }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if saved { savedNote } else { form }
                        if let error { InlineError(text: error) }
                    }
                    .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
                    .frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity)
                }
                VStack(spacing: 12) {
                    if saved {
                        Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }.buttonStyle(PrimaryButton())
                    } else {
                        Button { export() } label: {
                            if working { ProgressView().tint(Palette.paper) }
                            else { Label("Save export file", systemImage: "square.and.arrow.down") }
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(working || (ownPassphrase && problem != nil))
                    }
                }
                .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
            }
            .background(Palette.paper)
            .navigationTitle("Export notebook").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? "Close" : "Cancel") { dismiss() } } }
            .fileExporter(isPresented: $showExporter, document: document, contentType: .data,
                          defaultFilename: ExportFormat.fileName()) { result in
                document = nil
                if case .success = result {
                    session.exportCompleted()
                    saved = true
                }
            }
            .privacySensitive()
        }
        .onDisappear { passphrase = ""; code = ""; document = nil }
    }

    @ViewBuilder private var form: some View {
        Text(String(format: L("All %d passwords and your folders go into one encrypted file. Recently Deleted is left out."), session.vault.entries.count))
            .foregroundStyle(Palette.secondary)
        Picker("Protect the file with", selection: $ownPassphrase) {
            Text("Export code").tag(false)
            Text("My own passphrase").tag(true)
        }.pickerStyle(.segmented)
        if ownPassphrase {
            HStack {
                Group {
                    if showPassphrase { TextField("Passphrase", text: $passphrase) }
                    else { SecureField("Passphrase", text: $passphrase) }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { showPassphrase.toggle() } label: { Image(systemName: showPassphrase ? "eye.slash" : "eye") }
                    .buttonStyle(IconButton()).accessibilityLabel(L(showPassphrase ? "Hide passphrase" : "Show passphrase"))
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            if !passphrase.isEmpty {
                Label(problem?.message ?? L(passphrase.unicodeScalars.count >= 20 ? "Strong enough." : "Acceptable. A longer passphrase is stronger."),
                      systemImage: problem == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            Text("A passphrase you make up is easier to guess than an export code. Use at least 12 characters. PassBy does not keep it; without it the file cannot be opened.")
                .font(.footnote).foregroundStyle(Palette.secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(code).font(.system(.title3, design: .monospaced).weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                if let image = QRCode.image(code) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 148, height: 148).padding(10).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Export code as a QR code")
                }
                Button { session.copy(code, label: L("Export code copied for 60 seconds")) } label: {
                    Label("Copy export code", systemImage: "doc.on.doc")
                }.buttonStyle(SecondaryButton())
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            Text("You need this code to open the file. Write it down or save it away from the file. PassBy does not keep it; without it the file cannot be opened.")
                .font(.footnote).foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder private var savedNote: some View {
        Label("Export saved", systemImage: "checkmark.circle").font(.title2.weight(.semibold))
        Text(L(ownPassphrase ? "Keep your passphrase. Without it the file cannot be opened."
               : "Keep the export code. Without it the file cannot be opened."))
            .foregroundStyle(Palette.secondary)
        if !ownPassphrase {
            Text(code).font(.system(.title3, design: .monospaced).weight(.medium)).textSelection(.enabled)
        }
    }

    private func export() {
        guard !working else { return }
        working = true
        error = nil
        let vault = session.vault, secret = typed
        Task {
            defer { working = false }
            // Key derivation takes a moment; keep it off the main thread.
            let data = await Task.detached { try? ExportFormat.export(vault, typed: secret) }.value
            guard let data else { error = VaultError.storageFailed.localizedDescription; return }
            document = ExportDocument(data: data)
            showExporter = true
        }
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - Import

/// Reads an export file from this or another device: choose the file, enter
/// its code, then merge it into the notebook or replace the notebook with it.
struct ImportView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var file: Data?
    @State private var fileName = ""
    @State private var typed = ""
    @State private var payload: ExportPayload?
    @State private var replacing = false
    @State private var confirmReplace = false
    @State private var summary: ImportSummary?
    @State private var showPicker = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                        if let error { InlineError(text: error) }
                    }
                    .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
                    .frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity)
                }
                actions.padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 12)
            }
            .background(Palette.paper)
            .navigationTitle("Import from a file").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(summary == nil ? "Cancel" : "Close") { dismiss() } } }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data]) { result in read(result) }
            .confirmationDialog("Replace your notebook?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace notebook", role: .destructive) { apply() }
            } message: {
                Text(String(format: L("All %d passwords now in your notebook move to Recently Deleted for 30 days."), session.vault.entries.count))
            }
            .privacySensitive()
        }
        .onDisappear { typed = ""; file = nil; payload = nil }
    }

    @ViewBuilder private var content: some View {
        if let summary {
            Label("Import finished", systemImage: "checkmark.circle").font(.title2.weight(.semibold))
            Text(String(format: L("Added %d. Already here, skipped %d. Different from yours, added with “(Imported)” %d."),
                        summary.added, summary.skipped, summary.marked))
                .foregroundStyle(Palette.secondary)
            Text("The file is still where you chose it from. Delete it there if you no longer need it.")
                .font(.footnote).foregroundStyle(Palette.secondary)
        } else if let payload {
            Text(String(format: L("This file holds %d passwords."), payload.entries.count)).font(.title3.weight(.semibold))
            if session.vault.entries.isEmpty {
                Text("They will be added to your empty notebook.").foregroundStyle(Palette.secondary)
            } else {
                Picker("How to import", selection: $replacing) {
                    Text("Merge").tag(false)
                    Text("Replace").tag(true)
                }.pickerStyle(.segmented)
                Text(L(replacing
                    ? "Your notebook becomes the same as the file. Everything in it now moves to Recently Deleted for 30 days."
                    : "Nothing in your notebook is changed. New passwords are added; ones you already have are skipped; ones that differ are added with “(Imported)” after the title."))
                    .foregroundStyle(Palette.secondary)
            }
        } else if file != nil {
            Label(fileName, systemImage: "doc").font(.subheadline).foregroundStyle(Palette.secondary)
            Text("Enter the export code or passphrase for this file.").foregroundStyle(Palette.secondary)
            TextField("Export code or passphrase", text: $typed, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(16).background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            Text("An export code is 20 letters and digits. Spaces, hyphens and capitals do not matter.")
                .font(.footnote).foregroundStyle(Palette.secondary)
        } else {
            Text("Choose a .passby file exported from PassBy on this or another phone.")
                .foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        if summary != nil {
            Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }.buttonStyle(PrimaryButton())
        } else if payload != nil {
            Button { if replacing && !session.vault.entries.isEmpty { confirmReplace = true } else { apply() } } label: {
                Label(L(replacing && !session.vault.entries.isEmpty ? "Replace notebook" : "Import"), systemImage: "square.and.arrow.down")
            }.buttonStyle(PrimaryButton())
        } else if file != nil {
            Button { open() } label: {
                if working { ProgressView().tint(Palette.paper) }
                else { Label("Open file", systemImage: "lock.open") }
            }.buttonStyle(PrimaryButton()).disabled(working || typed.isEmpty)
        } else {
            Button { showPicker = true } label: { Label("Choose file", systemImage: "folder") }.buttonStyle(PrimaryButton())
        }
    }

    private func read(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            // An export of a very large notebook is still far below this size.
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024, let data = try? Data(contentsOf: url) else { throw ExportError.notExport }
            try ExportFormat.inspect(data)
            file = data
            fileName = url.lastPathComponent
        } catch { self.error = (error as? ExportError ?? .notExport).localizedDescription }
    }

    private func open() {
        guard !working, let file else { return }
        working = true
        error = nil
        let secret = typed
        Task {
            defer { working = false }
            let result = await Task.detached { Result { try ExportFormat.open(file, typed: secret) } }.value
            switch result {
            case .success(let value): payload = value; typed = ""
            case .failure(let failure): error = (failure as? ExportError ?? .damaged).localizedDescription
            }
        }
    }

    private func apply() {
        guard let payload else { return }
        if let result = session.applyImport(payload, replacing: replacing && !session.vault.entries.isEmpty) {
            summary = result
            self.payload = nil
            file = nil
        } else { error = VaultError.storageFailed.localizedDescription }
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
        } message: { Text("Restoring puts it back in your notebook. Deleting now removes it for good.") }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Privacy policy").font(.largeTitle.weight(.semibold))
                Text("Version 4.3").font(.footnote).foregroundStyle(Palette.secondary)
                Text("PassBy is provided by Tenon Artificial Intelligence Technology Co., Ltd. (长沙榫卯人工智能科技有限公司), the company behind Tenon AI (\"we\"). We handle the personal information described in this policy. Contact us at support@tenonai.cn.")
                Text("In short: no account, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. The app stays offline by default, with two exceptions: when you turn on AI grouping it connects to the model provider you choose, and when you use Sync it connects directly to your other device on the same Wi-Fi.")
                policySection("Your notebook", "Your entries (title, account, password and notes), folders, Recently Deleted and the date of your last export are kept in one PassBy file on this iPhone, protected by iOS file encryption: the file cannot be read while your iPhone is locked. PassBy adds no key of its own, so your notebook is only as secure as your device passcode and Face ID or Touch ID. Entries in Recently Deleted stay on this iPhone for 30 days, and you can delete them sooner. Deleting PassBy deletes the notebook on this iPhone.")
                policySection("Backups and new iPhones", "Your notebook is included in system backups and device transfers, including iCloud Backup, computer backups and Quick Start. Apple or your computer keeps these backups; they do not pass through us. iCloud Backup: unless you turn on Advanced Data Protection, Apple can read the contents of your backup. We recommend turning on Advanced Data Protection where it is available, or using encrypted computer backups instead. Unencrypted computer backups: your notebook is likely stored unencrypted in the backup on your computer. We recommend selecting “Encrypt local backup” in Finder on a Mac, or in the Apple Devices app (or iTunes) on Windows.")
                policySection("Encrypted export", "An export file is created only when you choose Export. It contains all entries and folders, but not Recently Deleted. It is encrypted with AES-256-GCM, using a key derived from your export code or passphrase with PBKDF2-HMAC-SHA256. The app generates the export code. We never store the export code or your passphrase; without them the file cannot be opened. You choose where the file goes. We never receive export files. If you save one to iCloud Drive, a computer or another app, that service keeps it under its own terms.")
                policySection("Face ID and clipboard", "Face ID and Touch ID are handled by iOS. PassBy receives only the result, never your face or fingerprint data. Copied values stay on this iPhone and expire after 60 seconds; the app you paste into can read them.")
                policySection("Network", "PassBy stays offline by default. It does not connect to our servers and includes no third-party advertising, analytics or crash-reporting SDK. It uses the network in only two cases: when you turn on AI grouping, and when you use Sync. Links in the app, such as this policy or Support, open in your browser only when you tap them.")
                policySection("Sync", "Sync happens only when you start it in Settings › Sync, with another device on the same local network. The two devices connect directly; nothing passes through our servers. All entries and folders are sent, encrypted with a key derived from the pairing code. The first time, iOS asks whether PassBy may use the local network. See the online privacy policy for details.")
                policySection("AI grouping", "AI grouping is off by default. It uses the model provider you choose and your own API key; the service is provided by that provider, not by us. Only after you tap Send does PassBy send your entries' titles and folder names from this iPhone straight to that provider; accounts, passwords and notes are never sent, and nothing passes through our servers. Your API key is kept in the iOS keychain on this device only. Uninstalling PassBy does not remove it; turn AI grouping off first. See the online privacy policy for details.")
                policySection("Information we may receive", "Crash reports and usage statistics: if you turn on Share With App Developers in Settings › Privacy & Security › Analytics & Improvements, Apple provides us with PassBy crash reports and aggregated usage statistics. They do not include your notebook, and Apple states that they do not identify you personally. Support email: when you email support@tenonai.cn, we receive your email address, your message and anything you attach, and use them only to reply to you. Never send passwords, export codes or your device passcode. Website: when you visit passby.tenonai.cn, our servers record the time, IP address and page requested, and delete these logs automatically after 6 months. Downloads: Apple handles downloads on the App Store; we see only aggregated figures.")
                policySection("Data left by earlier versions", "From version 2.0, PassBy no longer uses Tenon Account sign-in or iCloud sync. Sign-in records that earlier versions left on our servers were deleted when that service shut down. The encrypted notebook that earlier versions synced to iCloud stays in your own iCloud, and we cannot delete it; you can delete PassBy's data when you manage your iCloud storage in iPhone Settings. The earlier notebook file on this iPhone is kept after it is moved into this version.")
                policySection("Your rights", "You can access, copy, correct or delete your personal information, withdraw consent, or ask us to explain how we handle it. You manage your notebook yourself in the app. For anything else, email support@tenonai.cn and we will reply within 15 working days.")
                Link("Online privacy policy", destination: PassByLinks.page("privacy/"))
                Link("Terms of Service", destination: PassByLinks.page("terms/"))
                Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Palette.paper).navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(title)).font(.headline)
            Text(L(body)).font(.body).foregroundStyle(Palette.secondary)
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
                Text("No account, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. The app stays offline by default, with two exceptions: when you turn on AI grouping it connects to the model provider you choose, and when you use Sync it connects directly to your other device on the same Wi-Fi. Export an encrypted file to keep a backup of your own or to move to another phone.")
                    .foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    // Publisher: the small Tenon lockup, the orange T beside the company name.
                    HStack(spacing: 0) {
                        Text("Publisher").font(.subheadline).foregroundStyle(Palette.secondary)
                        Spacer().frame(width: 16)
                        Image("TenonMark").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                        Spacer().frame(width: 6)
                        Text("榫卯 Tenon AI").font(.system(size: 15, weight: .semibold))
                    }.accessibilityElement(children: .combine)
                    Link("tenonai.cn", destination: URL(string: "https://tenonai.cn/")!)
                }
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }
                    Link("Terms of Service", destination: PassByLinks.page("terms/"))
                    Link("Send feedback", destination: SupportMail.url(subject: "PassBy Feedback"))
                }
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            .frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .navigationTitle("About PassBy").navigationBarTitleDisplayMode(.inline)
    }
}
