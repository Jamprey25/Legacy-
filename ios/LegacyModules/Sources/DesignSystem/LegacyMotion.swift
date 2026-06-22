import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Central accessibility gate for non-essential motion. Honours the system
/// "Reduce Motion" setting so spring/stagger flourishes degrade to instant
/// state changes for users who opt out of motion.
///
/// We read `UIAccessibility.isReduceMotionEnabled` (a process-wide UIKit flag)
/// rather than `@Environment(\.accessibilityReduceMotion)` so the same gate
/// works from coordinators and imperative `withAnimation` call sites, not just
/// SwiftUI view bodies.
public enum LegacyMotion {
    /// True when the user has asked the system to minimise motion.
    public static var isReduced: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    /// The supplied animation, or `nil` (instant) when Reduce Motion is on.
    /// Pass the result straight into `withAnimation(_:)` or `.animation(_:value:)`.
    public static func animation(_ animation: Animation?) -> Animation? {
        isReduced ? nil : animation
    }

    /// Per-step stagger delay, collapsed to `0` under Reduce Motion so batched
    /// reveals appear at once instead of cascading.
    public static func staggerDelay(_ seconds: Double) -> Double {
        isReduced ? 0 : seconds
    }
}
