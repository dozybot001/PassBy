import SwiftUI

struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    let choose: (String) -> Bool
    @State private var options = PasswordOptions()
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Generated password").font(.subheadline).foregroundStyle(Palette.secondary)
                        Text(password.isEmpty ? "—" : password)
                            .font(.system(.title3, design: .monospaced).weight(.medium))
                            .lineSpacing(5).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                            .privacySensitive()
                        Button { generate() } label: { Label("Generate another", systemImage: "arrow.clockwise") }
                            .buttonStyle(SecondaryButton()).disabled(options.alphabets.isEmpty)
                    }
                    Rectangle().fill(Palette.rule).frame(height: 1)
                    VStack(spacing: 18) {
                        HStack {
                            Text("Length").fontWeight(.medium)
                            Spacer()
                            Text("\(options.length)").monospacedDigit().foregroundStyle(Palette.accent)
                        }
                        Slider(value: Binding(get: { Double(options.length) },
                            set: { options.length = Int($0) }), in: 12...64, step: 1)
                            .accessibilityLabel("Password length")
                            .accessibilityValue("\(options.length)")
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
                    Text("Use fills the password field and copies it for 60 seconds. Your draft stays encrypted on this iPhone when you switch apps.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Button {
                        if choose(password) { dismiss() }
                        else { error = VaultError.storageFailed.localizedDescription }
                    } label: { Label("Use this password", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton()).disabled(password.isEmpty)
                        .opacity(password.isEmpty ? 0.5 : 1)
                }
                .padding(24)
            }
            .background(Palette.paper)
            .navigationTitle("Strong password").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { generate() }
            .onChange(of: options) { _, _ in generate() }
            .onDisappear { password = "" }
        }
        .presentationDetents([.large])
    }

    private func generate() {
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
