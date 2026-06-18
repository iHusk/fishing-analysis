import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` so the export CSV/track files can be
/// AirDropped / emailed / saved from a SwiftUI sheet. Used by ContentView's
/// Export button with `store.exportURLs`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No dynamic updates needed; the item set is fixed for the presentation.
    }
}
