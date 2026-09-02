import SwiftUI

/// In-place callout anchored to a selected detection box. Shows type, estimated
/// size, severity, and confidence without covering the photo in a sheet.
struct DetectionBoxCallout: View {
    let marker: DamageMarker
    let sizeLabel: String
    var pointerOnTop: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if pointerOnTop { pointer.rotationEffect(.degrees(180)) }
            bubble
            if !pointerOnTop { pointer }
        }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: marker.type.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(marker.type.color)
                    .frame(width: 26, height: 26)
                    .background(marker.type.color.opacity(0.22), in: .circle)
                Text(marker.type.display)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(marker.severity.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(marker.severity.color, in: .capsule)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EST. SIZE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.55))
                Text(sizeLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                if marker.confidence > 0 {
                    Label("\(marker.confidence)%", systemImage: "checkmark.seal.fill")
                }
                if !marker.note.isEmpty {
                    Text(marker.note)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [marker.type.color.opacity(0.85), .white.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(marker.type.color)
            .frame(width: 3)
        }
        .environment(\.colorScheme, .dark)
    }

    private var pointer: some View {
        CalloutPointer()
            .fill(Color.black.opacity(0.55))
            .overlay(CalloutPointer().stroke(.white.opacity(0.18), lineWidth: 0.6))
            .frame(width: 16, height: 8)
            .offset(y: pointerOnTop ? 1 : -1)
    }

    private var accessibilityText: String {
        var parts = [marker.type.display, "estimated size \(sizeLabel)", marker.severity.rawValue]
        if marker.confidence > 0 { parts.append("\(marker.confidence) percent confidence") }
        if !marker.note.isEmpty { parts.append(marker.note) }
        return parts.joined(separator: ", ")
    }
}

private struct CalloutPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
