import SwiftUI

struct StormAlertCard: View {
    var embedded: Bool = false
    @State private var alertStore = StormAlertStore.shared

    private var alert: StormAlert? { alertStore.latestActiveAlert }

    var body: some View {
        ZStack {
            // Sky atmospherics
            LinearGradient(colors: [
                Color(red: 0.10, green: 0.12, blue: 0.22),
                Color(red: 0.20, green: 0.25, blue: 0.40),
                Color(red: 0.32, green: 0.34, blue: 0.46)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)

            // Cloud blobs
            Canvas { ctx, size in
                let blobs: [(CGFloat, CGFloat, CGFloat, Double)] = [
                    (size.width * 0.20, size.height * 0.30, 70, 0.10),
                    (size.width * 0.55, size.height * 0.20, 90, 0.13),
                    (size.width * 0.85, size.height * 0.55, 100, 0.08),
                    (size.width * 0.30, size.height * 0.75, 80, 0.07)
                ]
                for b in blobs {
                    let rect = CGRect(x: b.0 - b.2, y: b.1 - b.2, width: b.2 * 2, height: b.2 * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(b.3)))
                }
            }

            // Rain streaks
            Canvas { ctx, size in
                for i in 0..<26 {
                    let x = CGFloat(i) / 26 * size.width + .random(in: -8...8)
                    let y = CGFloat.random(in: 0...size.height)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - 6, y: y + 18))
                    ctx.stroke(p, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
                }
            }

            // Lightning
            Path { p in
                p.move(to: CGPoint(x: 0.78, y: 0.10))
                p.addLine(to: CGPoint(x: 0.72, y: 0.40))
                p.addLine(to: CGPoint(x: 0.78, y: 0.42))
                p.addLine(to: CGPoint(x: 0.70, y: 0.78))
            }
            .applying(CGAffineTransform(scaleX: 220, y: 200))
            .stroke(Theme.amber.opacity(0.85), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .blur(radius: 0.4)
            .shadow(color: Theme.amber.opacity(0.7), radius: 8)
            .offset(x: 80, y: -10)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: alert == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(alert == nil ? "STORM WATCH" : "STORM ALERT")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(alert == nil ? Theme.slate : Theme.ember, in: .rect(cornerRadius: 8))

                    Spacer()

                    if let alert {
                        VStack(alignment: .trailing, spacing: 0) {
                            HStack(spacing: 2) {
                                Text(String(format: "%.0f", alert.magnitudeValue))
                                    .font(.system(size: 28, weight: .heavy))
                                Text(alert.magnitudeUnit)
                                    .font(.system(size: 14, weight: .bold))
                                    .baselineOffset(6)
                            }
                            Text(alert.eventType.rawValue.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .opacity(0.85)
                        }
                        .foregroundStyle(.white)
                    }
                }

                if let alert {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.headline)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("\(alert.areaLabel) · \(alert.propertyCount) propert\(alert.propertyCount == 1 ? "y" : "ies") in the impact zone · \(String(format: "%.1f", alert.distanceMi)) mi away.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                    }

                    Button {} label: {
                        HStack {
                            Text("View Impacted Properties")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(.white, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("All clear")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("No active storm alerts in your service area. We'll notify you the moment hail or damaging wind is detected nearby.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 24))
        .padding(.horizontal, embedded ? 0 : 20)
        .shadow(color: Theme.ink.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}
