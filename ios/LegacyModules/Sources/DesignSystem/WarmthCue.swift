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
    @State private var pulsePhase = false

    public init(intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    public init(level: WarmthLevel) {
        self.init(intensity: level.intensity)
    }

    public var body: some View {
        GeometryReader { proxy in
            let maxDimension = max(proxy.size.width, proxy.size.height)
            ZStack {
                RadialGradient(
                    colors: [.clear, LegacyColor.accent.opacity(baseOpacity)],
                    center: .center,
                    startRadius: maxDimension * 0.35,
                    endRadius: maxDimension * 0.85
                )
                RadialGradient(
                    colors: [.clear, LegacyColor.accent.opacity(breathOpacity)],
                    center: .center,
                    startRadius: maxDimension * 0.25,
                    endRadius: maxDimension * 0.92
                )
                .scaleEffect(pulsePhase ? pulseScaleHigh : pulseScaleLow)
                .opacity(intensity > 0.01 ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.6), value: intensity)
        .onAppear {
            guard !LegacyMotion.isReduced else { return }
            pulsePhase = true
        }
        .animation(
            LegacyMotion.animation(
                .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
            ),
            value: pulsePhase
        )
    }

    private var baseOpacity: Double {
        intensity * 0.40
    }

    private var breathOpacity: Double {
        intensity * (pulsePhase ? 0.34 : 0.18)
    }

    private var pulseDuration: Double {
        switch WarmthLevel(intensity: intensity) {
        case .none: return 2.4
        case .coarse: return 1.9
        case .approaching: return 1.3
        case .inBubble: return 0.8
        }
    }

    private var pulseScaleLow: CGFloat { 0.94 }
    private var pulseScaleHigh: CGFloat { 1.04 }
}

public struct LegacyShimmer: ViewModifier {
    @State private var offset: CGFloat = -1.2

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, proxy.size.height)
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.16),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .rotationEffect(.degrees(18))
                    .offset(x: width * offset)
                    .frame(width: width * 0.55)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !LegacyMotion.isReduced else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    offset = 1.2
                }
            }
    }
}

public extension View {
    func legacyShimmer() -> some View {
        modifier(LegacyShimmer())
    }
}
