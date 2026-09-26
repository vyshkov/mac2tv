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
    public var isBuffering: Bool = false

    public init(isProminent: Bool = false, tint: Color = .accentColor, isBuffering: Bool = false) {
        self.isProminent = isProminent
        self.tint = tint
        self.isBuffering = isBuffering
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if isProminent {
                        if isBuffering {
                            // Busy / Buffering State (Frosted Graphite Glass with soft cyan inner pulse)
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)

                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.16, green: 0.18, blue: 0.24).opacity(0.92),
                                                Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.96)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.cyan.opacity(0.12), Color.blue.opacity(0.04)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        } else {
                            // Normal Prominent Active State (Vibrant Cyan-Blue Gradient)
                            ZStack {
                                LinearGradient(
                                    colors: [Color(red: 0.12, green: 0.58, blue: 1.0), Color(red: 0.35, green: 0.32, blue: 0.96)],
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isBuffering ?
                                [Color.cyan.opacity(0.40), Color.white.opacity(0.10)] :
                                (isProminent ?
                                    [Color.white.opacity(0.60), Color.white.opacity(0.20)] :
                                    [Color.white.opacity(0.40), Color.white.opacity(0.10)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isBuffering ? Color.black.opacity(0.25) : (isProminent ? tint.opacity(0.35) : Color.black.opacity(0.06)),
                radius: isBuffering ? 6 : (configuration.isPressed ? 4 : 10),
                x: 0,
                y: isBuffering ? 2 : (configuration.isPressed ? 1 : 4)
            )
            .scaleEffect(isBuffering ? 0.995 : (configuration.isPressed ? 0.985 : 1.0))
            .animation(.easeInOut(duration: 0.25), value: isBuffering)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Native AppKit Operation Not Allowed Cursor
final class OperationNotAllowedCursorView: NSView {
    var isActive: Bool = false {
        didSet {
            if oldValue != isActive {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isActive {
            addCursorRect(bounds, cursor: .operationNotAllowed)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return isActive ? self : nil
    }
}

struct OperationNotAllowedCursorRepresentable: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> OperationNotAllowedCursorView {
        let view = OperationNotAllowedCursorView()
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: OperationNotAllowedCursorView, context: Context) {
        nsView.isActive = isActive
    }
}

public extension View {
    func operationNotAllowedCursor(isActive: Bool) -> some View {
        self.overlay(
            OperationNotAllowedCursorRepresentable(isActive: isActive)
        )
    }
}

// MARK: - Buffering Shimmer Animation Modifier
public struct BufferingShimmerModifier: ViewModifier {
    public var isActive: Bool

    public init(isActive: Bool) {
        self.isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if isActive {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                            let t = timeline.date.timeIntervalSinceReferenceDate
                            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.3) / 1.3)

                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.38), location: 0.5),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: max(geo.size.width * 0.5, 40))
                            .offset(x: -geo.size.width * 0.5 + (geo.size.width * 1.5) * phase)
                            .blendMode(.screen)
                        }
                    }
                }
                .mask(content)
            )
    }
}

public extension View {
    func bufferingShimmer(isActive: Bool) -> some View {
        self.modifier(BufferingShimmerModifier(isActive: isActive))
    }
}
