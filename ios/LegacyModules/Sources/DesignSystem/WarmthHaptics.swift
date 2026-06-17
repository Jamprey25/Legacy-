import Foundation

/// Non-directional haptic feedback on warmth band transitions (DEC-15).
/// Intensity maps to band depth — never encodes bearing or distance.
public protocol WarmthHapticFeedback: Sendable {
    func playTransition(to level: WarmthLevel)
}

public struct NoOpWarmthHaptics: WarmthHapticFeedback {
    public init() {}
    public func playTransition(to level: WarmthLevel) {}
}

public enum WarmthHaptics {
    public static var platformDefault: WarmthHapticFeedback {
        #if os(iOS)
        return UIWarmthHaptics()
        #else
        return NoOpWarmthHaptics()
        #endif
    }
}

#if os(iOS)
import UIKit

public struct UIWarmthHaptics: WarmthHapticFeedback {
    private let generator: UIImpactFeedbackGenerator

    public init(style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        self.generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
    }

    public func playTransition(to level: WarmthLevel) {
        switch level {
        case .none:
            break
        case .coarse:
            generator.impactOccurred(intensity: 0.35)
        case .approaching:
            generator.impactOccurred(intensity: 0.65)
        case .inBubble:
            generator.impactOccurred(intensity: 1.0)
        }
    }
}
#endif
