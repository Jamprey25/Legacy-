import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Deep-links to this app's page in the system Settings app. Use on denied-permission
/// states (location off, photos off) so the user can recover without hunting through Settings.
public struct OpenSettingsButton: View {
    private let title: String

    public init(_ title: String = "Open Settings") {
        self.title = title
    }

    public var body: some View {
        Button(title) {
            #if os(iOS)
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
            #endif
        }
        .buttonStyle(.legacySecondary)
    }
}
