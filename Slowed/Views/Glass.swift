import SwiftUI

/// Liquid Glass on iOS 26+ (when built with the iOS 26 SDK), materials on iOS 16-25.
enum GlassShape {
    case rounded(CGFloat)
    case capsule
    case circle

    var shape: AnyShape {
        switch self {
        case .rounded(let r): return AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        }
    }
}

struct GlassCard: ViewModifier {
    var shape: GlassShape
    var tint: Color? = nil
    var interactive: Bool = false
    /// Draw a material/tint background on older iOS versions.
    var fallback: Bool = true

    init(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false, fallback: Bool = true) {
        self.shape = .rounded(cornerRadius)
        self.tint = tint
        self.interactive = interactive
        self.fallback = fallback
    }

    init(shape: GlassShape, tint: Color? = nil, interactive: Bool = false, fallback: Bool = true) {
        self.shape = shape
        self.tint = tint
        self.interactive = interactive
        self.fallback = fallback
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape.shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    @ViewBuilder
    private func legacy(_ content: Content) -> some View {
        if fallback {
            if let tint = tint {
                content
                    .background(tint.opacity(0.9))
                    .clipShape(shape.shape)
            } else {
                content
                    .background(.ultraThinMaterial)
                    .clipShape(shape.shape)
            }
        } else {
            content
        }
    }
}

/// .buttonStyle(.glass) / .glassProminent on iOS 26+, bordered capsule elsewhere.
struct GlassButtonStyleModifier: ViewModifier {
    var prominent: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(Theme.accent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    @ViewBuilder
    private func legacy(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.accent)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// GlassEffectContainer on iOS 26+ so neighbouring glass shapes blend; passthrough elsewhere.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

var isGlassAvailable: Bool {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) { return true }
    #endif
    return false
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false, fallback: Bool = true) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint, interactive: interactive, fallback: fallback))
    }

    func glassCard(shape: GlassShape, tint: Color? = nil, interactive: Bool = false, fallback: Bool = true) -> some View {
        modifier(GlassCard(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }

    func glassButton(prominent: Bool = false) -> some View {
        modifier(GlassButtonStyleModifier(prominent: prominent))
    }
}
