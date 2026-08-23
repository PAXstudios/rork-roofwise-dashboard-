import SwiftUI

/// Subtle fade + scale when an AI detection box first appears after analysis.
struct DetectionBoxAppearModifier: ViewModifier {
    var delay: Double = 0
    @State private var isVisible: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.92)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                    isVisible = true
                }
            }
    }

    /// Stagger so a cluster of hail boxes eases in instead of popping at once.
    static func delay(for index: Int) -> Double {
        min(Double(index) * 0.035, 0.42)
    }
}

extension View {
    func detectionBoxAppear(delay: Double = 0) -> some View {
        modifier(DetectionBoxAppearModifier(delay: delay))
    }

    func detectionBoxAppear(index: Int) -> some View {
        modifier(DetectionBoxAppearModifier(delay: DetectionBoxAppearModifier.delay(for: index)))
    }
}
