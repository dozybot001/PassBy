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
    @State private var recovery = ""
    @State private var understood = false
    private var working: Bool { session.phase == .authenticating || session.setup == .checking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("PassBy").font(.title2.weight(.semibold)).padding(.bottom, 62)
                NotebookMark(size: 76).padding(.bottom, 30)
                Text(L(session.setup == .newNotebook ? "A place for your passwords." : "Your notebook.\nFor your eyes."))
                    .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)
                Text("Four fields. One quiet place to keep them.")
                    .font(.body).foregroundStyle(Palette.secondary).padding(.bottom, 34)
                if session.setup == .newNotebook {
                    VStack(alignment: .leading, spacing: 18) {
                        securityLine("Face ID, every time", icon: "faceid")
                        securityLine("Encrypted before iCloud sync", icon: "icloud")
                        securityLine("Your Apple Account. No extra account.", icon: "person.crop.circle")
                    }.padding(.bottom, 30)
                    Text("Keep your recovery key somewhere safe, outside PassBy. You need it on a new device or after resetting Face ID. We cannot recover a lost key.")
                        .font(.footnote).foregroundStyle(Palette.secondary).padding(.bottom, 14)
                    Toggle("I understand how recovery works", isOn: $understood).tint(Palette.control)
                        .font(.subheadline).padding(.bottom, 24)
                }
                if session.setup == .recovery {
                    Text("Enter your recovery key to open the notebook from iCloud.")
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
                if session.setup == .unavailable {
                    Button("Try again") { Task { await session.prepare() } }.buttonStyle(PrimaryButton())
                } else {
                    Button {
                        let text = session.setup == .recovery ? recovery : nil
                        Task { await session.unlock(recoveryText: text) }
                    } label: {
                        if working { ProgressView().tint(Palette.paper) }
                        else { Label(session.setup == .newNotebook ? L("Create my notebook") : L("Unlock with Face ID"), systemImage: "faceid") }
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(working || (session.setup == .newNotebook && !understood)
                        || (session.setup == .recovery && recovery.isEmpty))
                }
                Text("Passwords stay encrypted on this iPhone and in your iCloud.")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                    .padding(.top, 22).frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 32)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .onDisappear { recovery = "" }
    }

    private func securityLine(_ text: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.accent).frame(width: 26)
            Text(text).font(.subheadline)
        }
    }
}

struct RecoverySetupView: View {
    @EnvironmentObject private var session: VaultSession
    let recovery: String
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NotebookMark(size: 54)
                Text("Keep your recovery key.").font(.largeTitle.weight(.semibold))
                Text("Write it down or save it in a secure place outside this app. Anyone with this key and access to your iCloud notebook can read your passwords.")
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
                Toggle("I have saved my recovery key", isOn: $saved).tint(Palette.control).font(.subheadline)
                Button("Open my notebook") { session.confirmRecoverySaved() }
                    .buttonStyle(PrimaryButton()).disabled(!saved)
                if let message = session.message {
                    InlineError(text: message)
                }
            }
            .padding(28).frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
    }
}
