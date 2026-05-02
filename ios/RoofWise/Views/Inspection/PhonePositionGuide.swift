import SwiftUI

/// Live phone-position HUD that helps the inspector frame the roof correctly.
/// Shows a bubble level (roll), a pitch tilt bar (green / yellow / red zones)
/// with a moving marker, and a contextual text hint.
struct PhonePositionGuide: View {
    let pitchDegrees: Double
    let rollDegrees: Double
    let quality: MotionElevationService.TiltQuality
    let hint: String

    var body: some View {
        VStack(spacing: 10) {
            bubbleLevel
            tiltBar
            hintPill
        }
        .padding(10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    // MARK: Bubble level (roll)

    private var bubbleLevel: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 1)
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 0.6)
                .scaleEffect(0.55)
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 36, height: 0.6)
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 0.6, height: 36)

            // Bubble dot (offset by roll).
            let offset = CGFloat(max(-1, min(1, rollDegrees / 18.0))) * 14
            Circle()
                .fill(rollColor)
                .frame(width: 10, height: 10)
                .shadow(color: rollColor.opacity(0.7), radius: 4)
                .offset(x: offset)
                .animation(.easeOut(duration: 0.18), value: rollDegrees)
        }
        .frame(width: 44, height: 44)
    }

    private var rollColor: Color {
        let mag = abs(rollDegrees)
        if mag < 4 { return Theme.mint }
        if mag < 12 { return Theme.amber }
        return Theme.crimson
    }

    // MARK: Tilt bar (pitch)

    private var tiltBar: some View {
        VStack(spacing: 4) {
            Text("TILT")
                .font(.system(size: 7, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            GeometryReader { geo in
                let h = geo.size.height
                let acceptable = MotionElevationService.acceptablePitchRange
                let optimal = MotionElevationService.optimalPitchRange
                let totalRange: ClosedRange<Double> = 0...80

                ZStack(alignment: .bottom) {
                    // Background gradient zones (red -> yellow -> green -> yellow -> red, from bottom).
                    LinearGradient(stops: [
                        .init(color: Theme.crimson.opacity(0.55), location: 0),
                        .init(color: Theme.amber.opacity(0.55),
                              location: yLoc(acceptable.lowerBound, in: totalRange)),
                        .init(color: Theme.mint.opacity(0.7),
                              location: yLoc(optimal.lowerBound, in: totalRange)),
                        .init(color: Theme.mint.opacity(0.7),
                              location: yLoc(optimal.upperBound, in: totalRange)),
                        .init(color: Theme.amber.opacity(0.55),
                              location: yLoc(acceptable.upperBound, in: totalRange)),
                        .init(color: Theme.crimson.opacity(0.55), location: 1)
                    ], startPoint: .bottom, endPoint: .top)
                    .clipShape(.rect(cornerRadius: 4))

                    // Optimal zone outline.
                    let optTop = h * (1 - yLoc(optimal.upperBound, in: totalRange))
                    let optBottom = h * (1 - yLoc(optimal.lowerBound, in: totalRange))
                    Rectangle()
                        .stroke(Theme.mint.opacity(0.9), lineWidth: 0.8)
                        .frame(height: optBottom - optTop)
                        .offset(y: -optTop)

                }
                .overlay(alignment: .topLeading) {
                    let markerY = h * (1 - yLoc(pitchDegrees, in: totalRange))
                    HStack(spacing: 2) {
                        Triangle()
                            .fill(qualityColor)
                            .frame(width: 6, height: 8)
                        Rectangle()
                            .fill(qualityColor)
                            .frame(height: 1.5)
                    }
                    .shadow(color: qualityColor.opacity(0.7), radius: 3)
                    .position(x: 8, y: markerY)
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: pitchDegrees)
                }
            }
            .frame(width: 16, height: 90)

            Text("\(Int(pitchDegrees))°")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(qualityColor)
                .monospacedDigit()
        }
    }

    private func yLoc(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return max(0, min(1, (value - range.lowerBound) / span))
    }

    private var qualityColor: Color {
        switch quality {
        case .optimal:    return Theme.mint
        case .acceptable: return Theme.amber
        case .tooLow, .tooHigh: return Theme.crimson
        }
    }

    // MARK: Hint

    private var hintPill: some View {
        HStack(spacing: 4) {
            Image(systemName: hintIcon)
                .font(.system(size: 8, weight: .heavy))
            Text(hint)
                .font(.system(size: 9, weight: .heavy))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(qualityColor)
        .frame(maxWidth: 90)
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(qualityColor.opacity(0.18), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(qualityColor.opacity(0.45), lineWidth: 0.6))
        .contentTransition(.opacity)
        .id(hint)
    }

    private var hintIcon: String {
        switch quality {
        case .optimal:    return "checkmark.seal.fill"
        case .acceptable: return "arrow.up.and.down"
        case .tooLow:     return "arrow.up"
        case .tooHigh:    return "arrow.down"
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
