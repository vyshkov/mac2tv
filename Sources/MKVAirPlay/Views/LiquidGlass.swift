import SwiftUI
import AppKit

// MARK: - Native macOS Visual Effect Vibrancy
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.autoresizingMask = [.width, .height]
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Liquid Glass Card Modifier
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    public var padding: CGFloat = 14
    public var glowColor: Color = .clear

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Ultra thin frosted material base
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Refractive specular gradient wash
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Optional ambient chromatic tint
                    if glowColor != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(glowColor.opacity(0.06))
                    }
                }
            )
            .overlay(
                // Liquid glass specular rim highlight
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.45), location: 0.0),
                                .init(color: Color.white.opacity(0.18), location: 0.35),
                                .init(color: Color.white.opacity(0.06), location: 0.70),
                                .init(color: Color.white.opacity(0.22), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 14, glow: Color = .clear) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, padding: padding, glowColor: glow))
    }
}

// MARK: - Liquid Glass Pill Badge
public struct LiquidGlassPill: View {
    public let text: String
    public var systemImage: String? = nil
    public var tint: Color = .accentColor

    public init(_ text: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(tint)
        .background(
            Capsule()
                .fill(tint.opacity(0.14))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.45), tint.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }
}

// MARK: - Liquid Glass Button Style
public struct LiquidGlassButtonStyle: ButtonStyle {
    public var isProminent: Bool = false
    public var tint: Color = .accentColor

    public init(isProminent: Bool = false, tint: Color = .accentColor) {
        self.isProminent = isProminent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if isProminent {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.58, blue: 1.0),
                                    Color(red: 0.35, green: 0.32, blue: 0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            // Specular top light reflex
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    } else {
                        ZStack {
                            Color.primary.opacity(configuration.isPressed ? 0.10 : 0.05)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isProminent ?
                                [.white.opacity(0.60), .white.opacity(0.20)] :
                                [.white.opacity(0.40), .white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isProminent ? tint.opacity(0.35) : Color.black.opacity(0.06),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
