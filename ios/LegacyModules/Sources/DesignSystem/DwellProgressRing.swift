import SwiftUI

#if os(iOS)
/// Circular progress for dwell-required unlock — turns waiting into a ritual.
public struct DwellProgressRing: View {
    public let remainingSeconds: Int
    public let totalSeconds: Int

    public init(remainingSeconds: Int, totalSeconds: Int = 20) {
        self.remainingSeconds = max(remainingSeconds, 0)
        self.totalSeconds = max(totalSeconds, 1)
    }

    private var progress: Double {
        1 - Double(remainingSeconds) / Double(totalSeconds)
    }

    public var body: some View {
        VStack(spacing: LegacySpacing.sm) {
            ZStack {
                Circle()
                    .stroke(LegacyColor.separator, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(LegacyColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(LegacyMotion.animation(.easeInOut(duration: 0.35)), value: progress)
                Text("\(remainingSeconds)")
                    .font(LegacyFont.title2)
                    .foregroundStyle(LegacyColor.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 72, height: 72)

            Text("Stay close — memory unlocking…")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stay close. About \(remainingSeconds) seconds remaining.")
    }
}
#endif
