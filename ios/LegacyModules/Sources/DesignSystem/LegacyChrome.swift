import SwiftUI

/// Shared atmospheric chrome used to make feature tabs feel more "Legacy" and
/// less stock iOS.
public struct LegacyFeatureBackground: ViewModifier {
    let glow: Color

    public init(glow: Color = LegacyColor.accent) {
        self.glow = glow
    }

    public func body(content: Content) -> some View {
        content.background {
            ZStack {
                LinearGradient(
                    colors: [
                        LegacyColor.background,
                        LegacyColor.background,
                        LegacyColor.surface.opacity(0.65),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [glow.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 340
                )

                RadialGradient(
                    colors: [glow.opacity(0.12), .clear],
                    center: .bottomLeading,
                    startRadius: 30,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        }
    }
}

public extension View {
    func legacyFeatureBackground(glow: Color = LegacyColor.accent) -> some View {
        modifier(LegacyFeatureBackground(glow: glow))
    }
}

public struct LegacyChromeCard<Content: View>: View {
    @ViewBuilder private let content: Content
    private let glow: Color

    public init(glow: Color = LegacyColor.accent, @ViewBuilder content: () -> Content) {
        self.glow = glow
        self.content = content()
    }

    public var body: some View {
        content
            .padding(LegacySpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LegacyColor.surface.opacity(0.96),
                                LegacyColor.background.opacity(0.90),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [glow.opacity(0.55), LegacyColor.separator],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: glow.opacity(0.15), radius: 14, y: 6)
    }
}
