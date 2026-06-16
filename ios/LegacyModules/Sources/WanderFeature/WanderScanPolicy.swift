import APIClient
import DesignSystem

/// Pure scan-result helpers — testable without location hardware.
enum WanderScanPolicy {
    /// Highest warmth band among teasers drives the non-directional cue (DEC-15).
    static func maxWarmthLevel(from teasers: [Teaser]) -> WarmthLevel {
        teasers
            .map { WarmthLevel(contractValue: $0.warmth) }
            .max(by: { $0.intensity < $1.intensity }) ?? .none
    }
}
