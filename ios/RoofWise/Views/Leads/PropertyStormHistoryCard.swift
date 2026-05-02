import SwiftUI

struct PropertyStormHistoryCard: View {
    let customer: Customer

    private var hits: [PropertyStormService.PropertyHit] {
        PropertyStormService.hits(for: customer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.bolt.rain.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 22, height: 22)
                    .background(Theme.emberSoft, in: .rect(cornerRadius: 7))
                Text("Storm Intel · This Property")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(hits.count) hits")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.canvas, in: .capsule)
            }

            if let top = hits.first {
                topHero(top)
            }

            VStack(spacing: 8) {
                ForEach(hits) { hit in
                    row(hit)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
                Text("Sourced from regional NEXRAD + carrier loss data")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func topHero(_ hit: PropertyStormService.PropertyHit) -> some View {
        let storm = hit.storm
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [storm.band.color, storm.band.color.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Subtle rain streaks
            Canvas { ctx, size in
                for i in 0..<22 {
                    let x = CGFloat(i) / 22 * size.width + .random(in: -6...6)
                    let y = CGFloat.random(in: 0...size.height)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - 5, y: y + 14))
                    ctx.stroke(p, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: storm.type.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.22), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MOST IMPACTFUL EVENT")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("\(storm.type.rawValue) · \(storm.date)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(hit.coverageLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: .capsule)
                }

                HStack(spacing: 14) {
                    if let size = storm.sizeInches {
                        statChip(label: "Hail", value: String(format: "%.2f″", size))
                    }
                    if let mph = storm.windMPH {
                        statChip(label: "Wind", value: "\(mph) mph")
                    }
                    statChip(label: "Coverage", value: "\(Int(hit.coverage * 100))%")
                }
            }
            .padding(14)
        }
        .frame(height: 130)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private func row(_ hit: PropertyStormService.PropertyHit) -> some View {
        let storm = hit.storm
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(storm.band.color.opacity(0.18))
                Image(systemName: storm.type.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(storm.band.color)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(storm.type.rawValue) · \(storm.date)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    if let s = storm.sizeInches {
                        Text(String(format: "%.2f″", s))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if let m = storm.windMPH {
                        Text("\(m) mph")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Text("·").foregroundStyle(Theme.inkFaint).font(.system(size: 10))
                    Text(hit.coverageLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hit.coverageColor)
                }
            }

            Spacer()

            // Coverage gauge
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.canvas).frame(width: 56, height: 6)
                Capsule().fill(hit.coverageColor)
                    .frame(width: max(6, CGFloat(hit.coverage) * 56), height: 6)
            }
        }
        .padding(10)
        .background(Theme.canvas, in: .rect(cornerRadius: 12))
    }
}
