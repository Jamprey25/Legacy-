import DesignSystem
import SwiftUI

#if os(iOS)

/// First-run intro shown once before the welcome screen. Sets expectations and
/// primes the user for the location/notification permission prompts that the
/// app requests later in the normal flow (it does NOT trigger system prompts
/// itself — priming first measurably improves grant rates).
public struct OnboardingView: View {
    private let onComplete: () -> Void
    @State private var page = 0

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            kind: .icon("mappin.and.ellipse"),
            title: "Leave memories where they happened",
            body: "Drop a photo or a note at a real place. It stays there, waiting."
        ),
        OnboardingPage(
            kind: .liveDemo,
            title: "Rediscover them by being there",
            body: "Memories unlock when you return to the spot you left them — yours and ones shared with you."
        ),
        OnboardingPage(
            kind: .icon("bell.badge"),
            title: "Works quietly in the background",
            body: "With your permission, Legacy uses your location to nudge you when a memory is nearby. You're always in control in Settings."
        ),
    ]

    public var body: some View {
        ZStack {
            LegacyColor.background.ignoresSafeArea()

            VStack(spacing: LegacySpacing.xl) {
                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                            .padding(.horizontal, LegacySpacing.xl)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(isLastPage ? "Get started" : "Next") {
                    if isLastPage {
                        onComplete()
                    } else {
                        withAnimation(LegacyMotion.animation(.default)) { page += 1 }
                    }
                }
                .buttonStyle(.legacyPrimary)
                .padding(.horizontal, LegacySpacing.xl)

                Button("Skip") { onComplete() }
                    .font(LegacyFont.callout)
                    .foregroundStyle(LegacyColor.textSecondary)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }
            .padding(.vertical, LegacySpacing.xxl)
        }
    }

    private var isLastPage: Bool { page == Self.pages.count - 1 }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let kind: OnboardingVisualKind
    let title: String
    let body: String
}

private enum OnboardingVisualKind {
    case icon(String)
    case liveDemo
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: LegacySpacing.xl) {
            Spacer()

            visual

            VStack(spacing: LegacySpacing.md) {
                Text(page.title)
                    .font(LegacyFont.title)
                    .foregroundStyle(LegacyColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(LegacyFont.body)
                    .foregroundStyle(LegacyColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch page.kind {
        case .icon(let icon):
            Image(systemName: icon)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(LegacyColor.accent)
                .accessibilityHidden(true)
        case .liveDemo:
            OnboardingDiscoveryDemo()
                .frame(height: 220)
                .accessibilityHidden(true)
        }
    }
}

private struct OnboardingDiscoveryDemo: View {
    @State private var pinVisible = false
    @State private var warmth = 0.15
    @State private var reveal = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LegacyColor.surface, LegacyColor.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                        .stroke(LegacyColor.separator, lineWidth: 1)
                }

            WarmthCueOverlay(intensity: warmth)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous))

            VStack(spacing: LegacySpacing.sm) {
                ZStack {
                    Circle()
                        .fill(LegacyColor.accent.opacity(0.22))
                        .frame(width: 48, height: 48)
                        .scaleEffect(pinVisible ? 1 : 0.2)
                        .opacity(pinVisible ? 1 : 0)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(LegacyColor.accent)
                        .scaleEffect(pinVisible ? 1 : 0.2)
                        .offset(y: pinVisible ? 0 : -22)
                        .opacity(pinVisible ? 1 : 0)
                }
                .animation(LegacyMotion.animation(.spring(response: 0.42, dampingFraction: 0.7)), value: pinVisible)

                RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
                    .fill(LegacyColor.surface.opacity(0.92))
                    .frame(width: 150, height: 94)
                    .overlay {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.75), Color.white.opacity(0.38)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blur(radius: reveal ? 0 : 8)
                            .scaleEffect(reveal ? 1 : 0.92)
                            .opacity(reveal ? 1 : 0.58)
                            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous))
                            .padding(8)
                    }
                    .scaleEffect(reveal ? 1 : 0.95)
                    .animation(LegacyMotion.animation(.easeOut(duration: 0.55)), value: reveal)
            }
        }
        .onAppear {
            runDemo()
        }
    }

    private func runDemo() {
        guard !LegacyMotion.isReduced else {
            pinVisible = true
            warmth = 0.85
            reveal = true
            return
        }
        pinVisible = false
        warmth = 0.2
        reveal = false
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            pinVisible = true
            try? await Task.sleep(for: .milliseconds(600))
            warmth = 0.85
            try? await Task.sleep(for: .milliseconds(450))
            reveal = true
        }
    }
}

#endif
