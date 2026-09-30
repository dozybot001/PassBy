import SwiftUI

enum Palette {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let secondary = Color("Secondary")
    static let accent = Color("AccentColor")
    static let rule = Color("Rule")
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

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 17))
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
