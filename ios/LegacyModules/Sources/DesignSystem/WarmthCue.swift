import SwiftUI

/// Proximity warmth, mirroring the API contract's `warmth` field.
///
/// CRITICAL (DEC-15): this is the ONLY proximity signal the UI may render, and it is
/// **non-directional**. There is intentionally no bearing/heading/distance. A directional
/// cue would let a user triangulate a memory's location without a server proximity check.
public enum WarmthLevel: String, Sendable, CaseIterable {
    case none
    case coarse
    case approaching
    case inBubble = "in_bubble"

    /// Ambient gradient intensity 0…1. Monotonic with closeness — magnitude only.
    public var intensity: Double {
        switch self {
        case .none: return 0
        case .coarse: return 0.25
        case .approaching: return 0.55
        case .inBubble: return 0.9
        }
    }

    /// Parses the contract string; unknown values degrade to `.none`.
    public init(contractValue: String?) {
        switch contractValue {
        case "coarse": self = .coarse
        case "approaching": self = .approaching
        case "in_bubble": self = .inBubble
        default: self = .none
        }
    }

    /// Maps a stored intensity back to the nearest warmth band (for UI badges).
    public init(intensity: Double) {
        switch intensity {
        case ..<0.01: self = .none
        case ..<0.4: self = .coarse
        case ..<0.75: self = .approaching
        default: self = .inBubble
        }
    }
}

/// Non-directional, screen-edge ambient gradient. Radial-from-edges so no single
/// side reads as "the direction." Intensity is the only variable.
public struct WarmthCueOverlay: View {
    private let intensity: Double

    public init(intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    public init(level: WarmthLevel) {
        self.init(intensity: level.intensity)
    }

    public var body: some View {
        GeometryReader { proxy in
            let maxDimension = max(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [.clear, LegacyColor.accent.opacity(intensity * 0.45)],
                center: .center,
                startRadius: maxDimension * 0.35,
                endRadius: maxDimension * 0.85
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.6), value: intensity)
    }
}
