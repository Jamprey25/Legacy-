import SwiftUI

/// A transient confirmation message that floats in from the bottom and auto-dismisses.
/// Drive it with an optional-String binding: set the string to show, it clears itself.
public struct LegacyToast: Equatable {
    public enum Style: Equatable {
        case success
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return LegacyColor.accent
            case .error: return LegacyColor.danger
            }
        }
    }

    public let message: String
    public let style: Style

    public init(message: String, style: Style = .success) {
        self.message = message
        self.style = style
    }
}

private struct LegacyToastModifier: ViewModifier {
    @Binding var toast: LegacyToast?
    var duration: Double = 2.2

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                toastView(toast)
                    .padding(.horizontal, LegacySpacing.xl)
                    .padding(.bottom, LegacySpacing.xxl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.message) {
                        // Auto-dismiss. task(id:) restarts the timer if a new toast
                        // replaces the current one before it expires.
                        try? await Task.sleep(for: .seconds(duration))
                        guard !Task.isCancelled else { return }
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }

    private func toastView(_ toast: LegacyToast) -> some View {
        HStack(spacing: LegacySpacing.sm) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, LegacySpacing.lg)
        .padding(.vertical, LegacySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                .fill(LegacyColor.surface)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                .stroke(LegacyColor.separator, lineWidth: 1)
        )
    }
}

public extension View {
    /// Presents a transient toast anchored to the bottom of this view.
    func legacyToast(_ toast: Binding<LegacyToast?>, duration: Double = 2.2) -> some View {
        modifier(LegacyToastModifier(toast: toast, duration: duration))
    }
}
