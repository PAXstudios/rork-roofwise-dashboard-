import SwiftUI

// MARK: - Storm pin (Step 1)
//
// Hail = severity-coloured circle with a white "H". Wind = severity-coloured
// circle with an up-chevron + white "W". Diameter scales with intensity, and a
// recency pill ("12d", green ≤30d / amber 31–90d / gray >90d) rides the corner.

struct StormPinView: View {
    let event: StormPinEvent

    private var diameter: CGFloat { event.glyphDiameter }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: diameter + 8, height: diameter + 8)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            Circle()
                .fill(event.severityColor)
                .frame(width: diameter, height: diameter)
            glyph
        }
        .overlay(alignment: .topTrailing) { recencyBadge }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.severity.label) \(event.magnitudeText), \(event.daysSince) days ago")
    }

    @ViewBuilder
    private var glyph: some View {
        if event.isHail {
            Text("H")
                .font(.system(size: diameter * 0.46, weight: .black))
                .foregroundStyle(.white)
        } else {
            VStack(spacing: -diameter * 0.08) {
                Image(systemName: "chevron.up")
                    .font(.system(size: diameter * 0.26, weight: .black))
                Text("W")
                    .font(.system(size: diameter * 0.40, weight: .black))
            }
            .foregroundStyle(.white)
        }
    }

    private var recencyBadge: some View {
        Text(event.daysSinceBadge)
            .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(event.recencyColor, in: .capsule)
            .overlay(Capsule().stroke(.white, lineWidth: 1))
            .offset(x: 8, y: -6)
            .fixedSize()
    }
}

// MARK: - Cluster pill (Step 8)

struct StormClusterView: View {
    let count: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            Circle()
                .fill(color)
                .frame(width: 42, height: 42)
            Circle()
                .stroke(.white.opacity(0.85), lineWidth: 2)
                .frame(width: 42, height: 42)
            Text("\(count)")
                .font(.system(size: count > 99 ? Theme.TypeRamp.metaSm : Theme.TypeRamp.subhead, weight: .black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .accessibilityLabel("\(count) storms")
    }
}

// MARK: - Footprint pin (Step 4)

struct FootprintPinView: View {
    let kind: FootprintPin.Kind

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            if kind.isFilled {
                Circle().fill(kind.color).frame(width: 20, height: 20)
                Image(systemName: kind.icon)
                    .font(.system(size: Theme.TypeRamp.microSm, weight: .black))
                    .foregroundStyle(.white)
            } else {
                Circle().stroke(kind.color, lineWidth: 3).frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(kind.label)
    }
}

// MARK: - Numbered route stop pin (Step 7)

struct RouteStopPinView: View {
    let order: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            Circle().fill(Theme.ink).frame(width: 24, height: 24)
            Text("\(order)")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Stop \(order)")
    }
}
