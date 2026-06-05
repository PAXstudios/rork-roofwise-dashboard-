import SwiftUI

/// Compact, friendly inline empty-state used inside dashboard cards.
/// Keeps the "boots to empty, never fake data" rule readable instead of blank.
struct EmptyHint: View {
    let icon: String
    let text: String
    var minHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.slate.opacity(0.7))
            Text(text)
                .font(.system(size: Theme.TypeRamp.bodySm, weight: .regular))
                .foregroundStyle(Theme.slate)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}
