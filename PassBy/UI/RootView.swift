import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession
    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.paper.ignoresSafeArea()
            if session.phase == .unlocked {
                if session.needsMigration || session.migrationSummary != nil {
                    MigrationView()
                } else {
                    LibraryView()
                        .alert("Could not save", isPresented: Binding(
                            get: { session.message != nil },
                            set: { if !$0 { session.message = nil } }
                        )) {
                            Button("OK", role: .cancel) { session.message = nil }
                        } message: { Text(session.message ?? "") }
                        .alert("This iPhone has no passcode", isPresented: $session.showNoLockNotice) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text("Without a passcode, iPhone does not encrypt your notebook file and anyone holding the phone can open PassBy. Set a passcode in iPhone Settings.")
                        }
                }
            } else {
                LockView()
            }
            if let toast = session.toast {
                StatusToast(text: toast, action: session.toastAction.map { action in
                    (action.title, { action.run(); session.dismissToast() })
                })
            }
        }
        .foregroundStyle(Palette.ink)
    }
}

/// Shown only while the door is closed. Nothing from the notebook is in the
/// view tree, or in memory, at this point.
struct LockView: View {
    @EnvironmentObject private var session: VaultSession
    private var working: Bool { session.phase == .authenticating }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotebookTitle().padding(.bottom, 62)
            Text("Your notebook.\nFor your eyes.")
                .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)
            Text("No account. Your notebook is kept on this iPhone.")
                .font(.body).foregroundStyle(Palette.secondary)
            if let message = session.message {
                InlineError(text: message).padding(.top, 22)
            }
            Spacer(minLength: 24)
            Button {
                guard !working else { return }
                Task { await session.unlock() }
            } label: {
                if working { ProgressView().tint(Palette.paper) }
                else { Label(L("Open notebook"), systemImage: Biometry.current.symbol) }
            }
            .buttonStyle(PrimaryButton()).disabled(working)
            HStack(spacing: 20) {
                Link("Privacy policy", destination: PassByLinks.page("privacy/"))
                Link("Terms of Service", destination: PassByLinks.page("terms/"))
            }
            .font(.footnote).tint(Palette.secondary).padding(.top, 16).frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.top, 32).padding(.bottom, 24)
        .frame(maxWidth: 540).frame(maxWidth: .infinity)
    }
}

/// Carries a PassBy 1.x notebook on this iPhone into 2.0. The earlier file and
/// its key are only read; they stay where they are.
struct MigrationView: View {
    @EnvironmentObject private var session: VaultSession
    @State private var recovery = ""
    @State private var working = false
    @State private var showExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NotebookMark(size: 54)
                    if let summary = session.migrationSummary { done(summary) } else { start }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let summary = session.migrationSummary {
                if summary.entries > 0 {
                    Button { showExport = true } label: { Label("Export a backup now", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButton()).frame(maxWidth: .infinity).padding(.bottom, 12)
                }
                Button { session.finishMigration() } label: { Label("Open my notebook", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButton())
            } else {
                Button {
                    guard !working else { return }
                    working = true
                    Task { defer { working = false }; await session.migrate(recoveryText: recovery) }
                } label: {
                    if working { ProgressView().tint(Palette.paper) }
                    else { Label(L("Move my notebook"), systemImage: "arrow.right.doc.on.clipboard") }
                }
                .buttonStyle(PrimaryButton())
                .disabled(working || (session.migrationNeedsRecovery && recovery.isEmpty))
                Button("Not now") { session.migrationDeferred = true }
                    .font(.subheadline).tint(Palette.secondary).frame(maxWidth: .infinity).padding(.top, 16)
            }
        }
        .padding(.horizontal, PageMetrics.horizontalPadding).padding(.top, 32).padding(.bottom, 24)
        .frame(maxWidth: 540).frame(maxWidth: .infinity)
        .sheet(isPresented: $showExport) { ExportView() }
        .onDisappear { recovery = "" }
    }

    @ViewBuilder private var start: some View {
        Text("Move your notebook to this version.").font(.largeTitle.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        Text(LB("PassBy no longer uses an account or iCloud sync. Your notebook from the earlier version is still on this iPhone. PassBy reads it with Face ID and keeps it on this iPhone from now on."))
            .foregroundStyle(Palette.secondary)
        Text("Nothing is deleted. The earlier file stays on this iPhone, and your copy in iCloud stays in iCloud.")
            .foregroundStyle(Palette.secondary)
        if session.migrationNeedsRecovery {
            SecureField("Recovery key", text: $recovery)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(16).background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
        if let message = session.message { InlineError(text: message) }
    }

    @ViewBuilder private func done(_ summary: MigrationSummary) -> some View {
        Text("Your notebook has moved.").font(.largeTitle.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        Text(String(format: L("All %d passwords from the earlier version are in this notebook."), summary.entries))
            .foregroundStyle(Palette.secondary)
        if !summary.drafts.isEmpty {
            Text(L("An unsaved draft was kept as its own entry:") + " " + summary.drafts.joined(separator: ", "))
                .foregroundStyle(Palette.secondary)
        }
        Text("Export a backup and keep it somewhere else, such as your computer. PassBy has no account to restore from.")
            .foregroundStyle(Palette.secondary)
    }
}
