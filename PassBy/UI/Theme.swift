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

struct NotebookTitle: View {
    var body: some View {
        Text("PassBy").font(.largeTitle.weight(.semibold)).tracking(-0.7)
            .accessibilityAddTraits(.isHeader)
    }
}

struct NotebookHeader: View {
    let search: () -> Void
    let generator: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            NotebookTitle()
            Spacer(minLength: 12)
            Button(action: search) { Image(systemName: "magnifyingglass") }
                .buttonStyle(IconButton()).accessibilityLabel("Search passwords")
            Button(action: generator) { Image(systemName: "dice") }
                .buttonStyle(IconButton()).accessibilityLabel("Generate strong password")
            Button(action: settings) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(IconButton()).accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28).padding(.trailing, 20)
        .padding(.top, 32).padding(.bottom, 12)
    }
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

enum ControlMetrics {
    static let height: CGFloat = 44
}

struct PrimaryButton: PrimitiveButtonStyle {
    @ScaledMetric(relativeTo: .body) private var height = ControlMetrics.height
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .font(.body.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: height)
                .foregroundStyle(Palette.paper)
                .contentShape(Capsule())
        }
        .buttonStyle(ControlPressFeedback())
        .modifier(ControlSurface(prominent: true))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct SecondaryButton: PrimitiveButtonStyle {
    var selected = false
    @ScaledMetric(relativeTo: .body) private var height = ControlMetrics.height
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .font(.body.weight(.medium))
                .padding(.horizontal, 18)
                .frame(minHeight: height)
                .foregroundStyle(selected ? Palette.paper : Palette.ink)
                .contentShape(Capsule())
        }
        .buttonStyle(ControlPressFeedback())
        .modifier(ControlSurface(prominent: selected))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct IconButton: PrimitiveButtonStyle {
    @ScaledMetric(relativeTo: .body) private var diameter = ControlMetrics.height
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .font(.body.weight(.medium))
                .frame(width: diameter, height: diameter)
                .foregroundStyle(Palette.ink)
                .contentShape(Circle())
        }
        .buttonStyle(ControlPressFeedback())
        .modifier(ControlSurface(circle: true))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct ControlPressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
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

struct ControlSurface: ViewModifier {
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

#Preview("Unified buttons") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 12) {
            Button {} label: { Image(systemName: "eye") }.buttonStyle(IconButton())
            Button {} label: { Image(systemName: "doc.on.doc") }.buttonStyle(IconButton())
            Button {} label: { Image(systemName: "die.face.5") }.buttonStyle(IconButton())
        }
        HStack(spacing: 12) {
            Button("All") {}.buttonStyle(SecondaryButton(selected: true))
            Button("Unfiled") {}.buttonStyle(SecondaryButton())
        }
        Button {} label: { Label("Unlock with Face ID", systemImage: "faceid") }
            .buttonStyle(PrimaryButton())
    }
    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.paper).preferredColorScheme(.dark)
}
