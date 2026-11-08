import SwiftUI

// MARK: - Glass surfaces
//
// Every translucent surface in the island goes through here. The look is drawn explicitly
// (frosted fill, specular top edge, hairline) so it renders identically in layer snapshots and
// on macOS 14/15; on macOS 26+ the real Liquid Glass material is layered underneath for live
// lensing and highlights.

struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var strength: Double = 1          // 1 = card, ~0.6 = quiet strip, 1.3 = hero sheet
    var interactive = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.white.opacity(0.075 * strength))
                    if let tint { shape.fill(tint.opacity(0.12 * strength)) }
                    shape.fill(LinearGradient(colors: [.white.opacity(0.11 * strength), .clear], startPoint: .top, endPoint: .center))
                }
                .modifier(SystemGlass(shape: shape, tint: tint, interactive: interactive))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.26 * strength), .white.opacity(0.06 * strength)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

private struct SystemGlass<S: InsettableShape>: ViewModifier {
    var shape: S; var tint: Color?; var interactive: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
        }
    }
    @available(macOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Frosted glass card/strip. `strength` scales how visible the surface is on the black island.
    func glass<S: InsettableShape>(_ shape: S, tint: Color? = nil, strength: Double = 1, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, strength: strength, interactive: interactive))
    }
    func glassCard(cornerRadius: CGFloat = 14, tint: Color? = nil, strength: Double = 1) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, strength: strength)
    }
}

// MARK: - Buttons

/// The island's three button looks: glass capsule, tinted prominent capsule, and quiet text.
/// Honours `.controlSize` and the island tint; replaces `.bordered` / `.borderedProminent`.
struct LoftButtonStyle: ButtonStyle {
    enum Kind { case glass, prominent, quiet }
    var kind: Kind = .glass
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        LoftButtonBody(kind: kind, tint: tint, configuration: configuration)
    }

    private struct LoftButtonBody: View {
        let kind: Kind
        let tint: Color?
        let configuration: Configuration
        @Environment(\.controlSize) private var controlSize
        @Environment(\.islandTint) private var islandTint
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let height: CGFloat = switch controlSize { case .mini: 20; case .small: 24; case .large, .extraLarge: 36; default: 30 }
            let size: CGFloat = switch controlSize { case .mini: 10.5; case .small: 11.5; case .large, .extraLarge: 14; default: 12.5 }
            let accent = tint ?? islandTint
            let prominent = kind == .prominent
            configuration.label
                .font(.system(size: size, weight: prominent ? .semibold : .medium))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(prominent ? Color.black.opacity(0.9) : .white.opacity(kind == .quiet ? (hover ? 0.95 : 0.7) : 0.94))
                .padding(.horizontal, height * 0.42)
                .frame(minHeight: height)
                .background {
                    switch kind {
                    case .prominent:
                        Capsule().fill(accent)
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                        Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                        if hover { Capsule().fill(.white.opacity(0.08)) }
                    case .glass:
                        Color.clear.glass(Capsule(), strength: hover ? 1.35 : 1, interactive: true)
                    case .quiet:
                        if hover { Capsule().fill(.white.opacity(0.08)) }
                    }
                }
                .contentShape(Capsule())
                .shadow(color: prominent ? accent.opacity(0.35) : .clear, radius: 8, y: 2)
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.smooth(duration: 0.15), value: configuration.isPressed)
                .animation(.smooth(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}

extension ButtonStyle where Self == LoftButtonStyle {
    static var loftGlass: LoftButtonStyle { .init() }
    static var loftQuiet: LoftButtonStyle { .init(kind: .quiet) }
    static func loftProminent(_ tint: Color? = nil) -> LoftButtonStyle { .init(kind: .prominent, tint: tint) }
}
