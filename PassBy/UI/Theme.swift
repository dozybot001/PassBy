import SwiftUI

enum Palette {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let secondary = Color("Secondary")
    static let accent = Color("AccentColor")
    static let rule = Color("Rule")
    // Keep the white system switch thumb distinct in both appearances.
    static let control = Color(white: 0.4)
}

struct NotebookMark: View {
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Palette.accent.opacity(0.10))
            HStack(spacing: size * 0.09) {
                RoundedRectangle(cornerRadius: size * 0.035)
                    .fill(Palette.accent).frame(width: size * 0.065, height: size * 0.46)
                VStack(alignment: .leading, spacing: size * 0.07) {
                    Capsule().fill(Palette.accent).frame(width: size * 0.28, height: size * 0.065)
                    Capsule().fill(Palette.accent).frame(width: size * 0.22, height: size * 0.065)
                    Capsule().fill(Palette.accent.opacity(0.4)).frame(width: size * 0.15, height: size * 0.065)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PrimaryButton: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26, *) {
                button(configuration).buttonStyle(.glassProminent)
            } else {
                button(configuration).buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(Palette.accent)
    }

    private func button(_ configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 24)
                .foregroundStyle(Palette.paper)
        }
    }
}

struct SecondaryButton: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26, *) {
                button(configuration).buttonStyle(.glass)
            } else {
                button(configuration).buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(Palette.ink)
    }

    private func button(_ configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .font(.body.weight(.medium))
                .frame(minHeight: 24)
                .foregroundStyle(Palette.ink)
        }
    }
}

struct InlineError: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                NotebookMark()
                Text("PassBy").font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                Image(systemName: "lock.fill").foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct StatusToast: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 18)
            .allowsHitTesting(false)
    }
}
