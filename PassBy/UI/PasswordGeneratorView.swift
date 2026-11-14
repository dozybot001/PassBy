import SwiftUI

struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    var copyOnly = false
    let choose: (String) -> Bool
    @State private var options = PasswordOptions()
    @State private var password = ""
    @State private var lengthText = "16"
    @FocusState private var editingLength: Bool
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Generated password").font(.subheadline).foregroundStyle(Palette.secondary)
                        ScrollView {
                            Text(password.isEmpty ? "—" : password)
                                .font(.system(.title3, design: .monospaced).weight(.medium))
                                .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                                .privacySensitive()
                        }
                        .frame(height: options.length > 64 ? 140 : 74)
                        Button { generate() } label: { Label("Generate another", systemImage: "arrow.clockwise") }
                            .buttonStyle(SecondaryButton()).disabled(options.alphabets.isEmpty)
                    }
                    VStack(spacing: 18) {
                        HStack {
                            Text("Length").fontWeight(.medium)
                            Spacer()
                            TextField("Password length", text: $lengthText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                .monospacedDigit().frame(width: 80)
                                .focused($editingLength)
                                .accessibilityLabel("Password length")
                        }
                        Slider(value: Binding(get: { Double(min(options.length, PasswordOptions.commonLengthRange.upperBound)) },
                            set: { lengthText = String(Int($0)) }), in: Double(PasswordOptions.commonLengthRange.lowerBound)...Double(PasswordOptions.commonLengthRange.upperBound), step: 1)
                            .accessibilityLabel("Password length")
                            .accessibilityValue("\(options.length)")
                        Text("Enter 8–4096 characters. The slider covers 8–24.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Lowercase letters (a–z)", isOn: $options.lowercase).tint(Palette.control)
                        Toggle("Uppercase letters (A–Z)", isOn: $options.uppercase).tint(Palette.control)
                        Toggle("Numbers (0–9)", isOn: $options.digits).tint(Palette.control)
                        Toggle("Symbols (!@#)", isOn: $options.symbols).tint(Palette.control)
                    }
                    if let error { InlineError(text: error) }
                    if options.length < 20 || options.alphabets.count == 1 {
                        Text("For important accounts, use 20 or more characters and multiple character types.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Text(L(copyOnly ? "Copies the password for 60 seconds. Paste it into another app." : "Use fills the password field and copies it for 60 seconds. Your draft stays on this iPhone when you switch apps."))
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Button {
                        if choose(password) { dismiss() }
                        else { error = VaultError.storageFailed.localizedDescription }
                    } label: { Label(L(copyOnly ? "Copy password" : "Use this password"), systemImage: copyOnly ? "doc.on.doc" : "checkmark") }
                        .buttonStyle(PrimaryButton()).disabled(password.isEmpty)
                }
                .padding(.horizontal, PageMetrics.horizontalPadding).padding(.vertical, 24)
            }
            .background(Palette.paper)
            .navigationTitle("Strong password").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingLength = false }
                }
            }
            .onAppear { generate() }
            .onChange(of: options) { _, _ in generate() }
            .onChange(of: lengthText) { _, value in
                if let length = Int(value), PasswordOptions.lengthRange.contains(length) {
                    options.length = length
                }
                generate()
            }
            .onDisappear { password = "" }
        }
        .presentationDetents([.large])
    }

    private func generate() {
        guard let length = Int(lengthText), PasswordOptions.lengthRange.contains(length) else {
            password = ""
            error = L("Enter a length between 8 and 4096.")
            return
        }
        do { password = try PasswordGenerator.generate(options: options); error = nil }
        catch { password = ""; self.error = error.localizedDescription }
    }
}

#Preview("Password generator") {
    PasswordGeneratorView { _ in true }
        .tint(Palette.accent)
}

#Preview("Password generator · Dark") {
    PasswordGeneratorView { _ in true }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
}
