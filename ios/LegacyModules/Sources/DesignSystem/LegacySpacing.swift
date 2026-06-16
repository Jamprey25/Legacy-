import CoreGraphics

/// 4pt-based spacing scale. Use tokens, not raw numbers, at call sites.
public enum LegacySpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

/// Corner radii.
public enum LegacyRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 20
    /// Fully rounded (pill) — use with a large value capped by frame height.
    public static let pill: CGFloat = 999
}
