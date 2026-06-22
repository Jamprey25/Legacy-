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
            icon: "mappin.and.ellipse",
            title: "Leave memories where they happened",
            body: "Drop a photo or a note at a real place. It stays there, waiting."
        ),
        OnboardingPage(
            icon: "map",
            title: "Rediscover them by being there",
            body: "Memories unlock when you return to the spot you left them — yours and ones shared with you."
        ),
        OnboardingPage(
            icon: "bell.badge",
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
    let icon: String
    let title: String
    let body: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: LegacySpacing.xl) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(LegacyColor.accent)
                .accessibilityHidden(true)

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
}

#endif
