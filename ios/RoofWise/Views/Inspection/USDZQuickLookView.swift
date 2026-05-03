import SwiftUI
import QuickLook
import UIKit

/// Presents a `.usdz` file in iOS QuickLook AR. Wraps `QLPreviewController`
/// so callers can drop it into a SwiftUI `.fullScreenCover` / `.sheet`.
struct USDZQuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let onDismiss: () -> Void
        init(url: URL, onDismiss: @escaping () -> Void) {
            self.url = url
            self.onDismiss = onDismiss
        }

        nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        nonisolated func previewController(_ controller: QLPreviewController,
                                           previewItemAt index: Int) -> QLPreviewItem {
            // QLPreviewItem requires NSURL; safe to vend off-actor since URL is value type.
            url as NSURL
        }
        nonisolated func previewControllerDidDismiss(_ controller: QLPreviewController) {
            Task { @MainActor in self.onDismiss() }
        }
    }
}
