import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession
    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.paper.ignoresSafeArea()
            if session.phase == .unlocked {
                if let recovery = session.recoveryToSave {
                    RecoverySetupView(recovery: recovery)
                } else {
                    LibraryView()
                        .alert("Could not save", isPresented: Binding(
                            get: { session.message != nil },
                            set: { if !$0 { session.message = nil } }
                        )) {
                            Button("OK", role: .cancel) { session.message = nil }
                        } message: { Text(session.message ?? "") }
                }
            } else {
                LockView()
            }
            if let toast = session.toast { StatusToast(text: toast) }
        }
        .foregroundStyle(Palette.ink)
    }
}

struct LockView: View {
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var account: TenonAccount
    @State private var recovery = ""
    @State private var understood = false
    @State private var retrying = false
    @State private var unlocking = false
    private var needsRecovery: Bool { session.setup == .recovery || session.setup == .localRecovery }
    private var working: Bool { unlocking || session.phase == .authenticating || session.setup == .checking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NotebookTitle().padding(.bottom, 62)
                Text(L(session.setup == .newNotebook ? "A place for your passwords." : "Your notebook.\nFor your eyes."))
                    .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)
                Text("Four fields. One quiet place to keep them.")
                    .font(.body).foregroundStyle(Palette.secondary).padding(.bottom, 34)
                if session.setup == .newNotebook {
                    VStack(alignment: .leading, spacing: 18) {
                        securityLine("Face ID, every time", icon: Biometry.current.symbol)
                        securityLine("Encrypted before syncing", icon: "icloud")
                        securityLine("One Tenon Account", icon: "person.crop.circle")
                    }.padding(.bottom, 30)
                    Text(LB("Keep your recovery key somewhere safe, outside PassBy. You need it on a new device or after resetting Face ID. We cannot recover a lost key."))
                        .font(.footnote).foregroundStyle(Palette.secondary).padding(.bottom, 14)
                    Toggle("I understand how recovery works", isOn: $understood).tint(Palette.control)
                        .font(.subheadline).padding(.bottom, 24)
                }
                if needsRecovery {
                    Text(L(session.setup == .localRecovery
                        ? "Restore the encrypted notebook already on this iPhone to your current Apple Account. Your original local copy will be kept. Enter its recovery key to continue."
                        : "Enter your recovery key to open your notebook on this iPhone."))
                        .font(.subheadline).foregroundStyle(Palette.secondary).padding(.bottom, 12)
                    SecureField("Recovery key", text: $recovery)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(16).background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 24)
                }
                if let message = session.message {
                    Text(message).font(.subheadline).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 22)
                }
                if session.setup == .newNotebook {
                    if account.identity == nil {
                        SignInOptions().padding(.bottom, 16)
                    } else if let identity = account.identity {
                        Text("Tenon: \(identity.name)").font(.subheadline).foregroundStyle(Palette.secondary).padding(.bottom, 16)
                    }
                }
                if session.setup == .unavailable || retrying {
                    Button {
                        guard !retrying else { return }
                        retrying = true
                        Task { defer { retrying = false }; await session.prepare() }
                    } label: { OperationLabel(title: "Try again", working: retrying).tint(Palette.paper) }
                    .buttonStyle(PrimaryButton()).disabled(retrying)
                } else {
                    Button {
                        guard !working else { return }
                        let text = needsRecovery ? recovery : nil
                        unlocking = true
                        Task {
                            defer { unlocking = false }
                            if session.setup == .newNotebook, !(await account.ensureCurrentSession()) { return }
                            await session.unlock(recoveryText: text)
                        }
                    } label: {
                        if working { ProgressView().tint(Palette.paper) }
                        else { Label(session.setup == .newNotebook ? L("Create my notebook") : session.setup == .localRecovery ? LB("Restore with Face ID") : LB("Unlock with Face ID"), systemImage: Biometry.current.symbol) }
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(working || account.working || (session.setup == .newNotebook && !understood)
                        || (session.setup == .newNotebook && account.identity == nil)
                        || (needsRecovery && recovery.isEmpty))
                }
                if session.setup != .newNotebook && session.setup != .checking && account.identity == nil {
                    SignInOptions().disabled(working).padding(.top, 16)
                }
                if let message = account.message {
                    Text(message).font(.subheadline).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                }
                Text("Your notebook is encrypted before it syncs.")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                    .padding(.top, 22).frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: 20) {
                    Link("Privacy policy", destination: URL(string: "https://passby.tenon.asia/privacy/")!)
                    Link("Terms of Service", destination: URL(string: "https://passby.tenon.asia/terms/")!)
                }
                .font(.footnote).tint(Palette.secondary).padding(.top, 10).frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, PageMetrics.horizontalPadding).padding(.top, 32).padding(.bottom, 32)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .onDisappear { recovery = "" }
    }

    private func securityLine(_ text: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.accent).frame(width: 26)
            Text(LB(text)).font(.subheadline)
        }
    }
}

struct RecoverySetupView: View {
    @EnvironmentObject private var session: VaultSession
    let recovery: String
    @State private var confirming = false
    @State private var group = 0
    @State private var typed = ""
    @State private var mismatch = false
    private var groups: Int { RecoveryKey.groupCount(recovery) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NotebookMark(size: 54)
                if confirming { confirmation } else { key }
                if let message = session.message {
                    InlineError(text: message)
                }
            }
            .padding(PageMetrics.horizontalPadding).frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
        .onDisappear { typed = "" }
    }

    @ViewBuilder private var key: some View {
        Text("Keep your recovery key.").font(.largeTitle.weight(.semibold))
        Text("Write it down or save it in a secure place outside this app. Anyone with this key and access to your Apple-linked notebook can read your passwords.")
            .foregroundStyle(Palette.secondary)
        Text(recovery).font(.system(.body, design: .monospaced)).lineSpacing(8)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            .privacySensitive()
        Button {
            session.copy(recovery, label: L("Recovery key copied for 60 seconds"))
        } label: { Label("Copy recovery key", systemImage: "doc.on.doc") }
            .buttonStyle(SecondaryButton())
        Text("PassBy never uploads this key. If you lose every device and this key, your passwords cannot be recovered.")
            .font(.footnote).foregroundStyle(Palette.secondary)
        Button("I have saved it") {
            // A random group, so the check reads the saved copy, not memory.
            group = Int.random(in: 0..<groups)
            typed = ""
            mismatch = false
            confirming = true
        }.buttonStyle(PrimaryButton())
    }

    @ViewBuilder private var confirmation: some View {
        Text("Check your saved copy.").font(.largeTitle.weight(.semibold))
        Text(String(format: L("Enter group %d of %d from the recovery key you saved. Groups are separated by hyphens."), group + 1, groups))
            .foregroundStyle(Palette.secondary)
        TextField(String(format: L("Group %d"), group + 1), text: $typed)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .font(.system(.title3, design: .monospaced))
            .padding(16).background(Palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .privacySensitive()
            .onChange(of: typed) { mismatch = false }
        if mismatch {
            InlineError(text: L("This group does not match. Check your saved copy."))
        }
        Button("Open my notebook") {
            if RecoveryKey.confirms(typed, group: group, of: recovery) { session.confirmRecoverySaved() }
            else { mismatch = true }
        }
        .buttonStyle(PrimaryButton()).disabled(typed.isEmpty)
        Button("Show the key again") { confirming = false }
            .buttonStyle(SecondaryButton())
    }
}
