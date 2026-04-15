import SwiftUI

// MARK: - Spacing System (4pt grid)

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
    static let xxl: CGFloat = 22
}

// MARK: - Gradient Tokens

enum GradientTokens {
    static let accent = LinearGradient(
        colors: [.blue, .purple.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warm = LinearGradient(
        colors: [.orange, .pink.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cool = LinearGradient(
        colors: [.cyan, .blue.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtle = LinearGradient(
        colors: [Color.accentColor.opacity(0.15), Color.purple.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Animation Constants

enum FoundryAnimation {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.85)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.75)
    static let micro = Animation.easeInOut(duration: 0.15)
}

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var shadow: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .light ? 0.08 : 0.06),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: shadow ? Color.black.opacity(colorScheme == .light ? 0.06 : 0.15) : .clear,
                radius: shadow ? 8 : 0,
                y: shadow ? 2 : 0
            )
    }
}

// MARK: - Glass Card Modifier (Elevated)

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .light ? 0.1 : 0.08),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.08 : 0.2),
                radius: 12,
                y: 4
            )
    }
}

// MARK: - Glass Panel Modifier (Sidebar/Sections)

struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .light ? 0.03 : 0.02))
            )
    }
}

// MARK: - Hover Lift Effect

struct HoverLift: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.08 : 0),
                radius: isHovered ? 8 : 0,
                y: isHovered ? 3 : 0
            )
            .animation(FoundryAnimation.snappy, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Floating Header (Panel Headers)

struct FloatingHeader: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.06)),
                alignment: .bottom
            )
    }
}

// MARK: - Glow Effect (for active/running states)

struct GlowEffect: ViewModifier {
    let color: Color
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(0.4) : .clear,
                radius: isActive ? 6 : 0
            )
    }
}

// MARK: - View Extensions

extension View {
    func glassBackground(cornerRadius: CGFloat = CornerRadius.lg, shadow: Bool = true) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, shadow: shadow))
    }

    func glassCard(cornerRadius: CGFloat = CornerRadius.lg) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glassPanel() -> some View {
        modifier(GlassPanel())
    }

    func hoverLift() -> some View {
        modifier(HoverLift())
    }

    func floatingHeader() -> some View {
        modifier(FloatingHeader())
    }

    func glowEffect(color: Color, isActive: Bool) -> some View {
        modifier(GlowEffect(color: color, isActive: isActive))
    }
}
