import SwiftUI

struct StormHistoryMapCard: View {
    @State private var selectedYear: Int = 2026
    @State private var selectedTypes: Set<StormType> = [.hail, .wind]

    private let years = [2023, 2024, 2025, 2026]

    private var visibleStorms: [StormEvent] {
        MockData.storms.filter {
            $0.year == selectedYear && selectedTypes.contains($0.type)
        }
    }

    private var summary: (hailEvents: Int, maxHail: Double, windEvents: Int, maxWind: Int) {
        let yearStorms = MockData.storms.filter { $0.year == selectedYear }
        let hails = yearStorms.filter { $0.type == .hail }
        let winds = yearStorms.filter { $0.type == .wind }
        return (
            hails.count,
            hails.compactMap { $0.sizeInches }.max() ?? 0,
            winds.count,
            winds.compactMap { $0.windMPH }.max() ?? 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.bolt.rain.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ember)
                        Text("4-Year Storm Intel")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Text("Hail & Wind History")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Plano · Collin County")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button {} label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvas, in: .circle)
                }
                .buttonStyle(.plain)
            }

            // Type chips
            HStack(spacing: 8) {
                ForEach(StormType.allCases) { type in
                    StormTypeChip(
                        type: type,
                        active: selectedTypes.contains(type)
                    ) {
                        if selectedTypes.contains(type) {
                            if selectedTypes.count > 1 { selectedTypes.remove(type) }
                        } else {
                            selectedTypes.insert(type)
                        }
                    }
                }
                Spacer()
            }

            // Map
            GeometryReader { geo in
                ZStack {
                    StormMapBackground()
                    ForEach(visibleStorms) { storm in
                        StormBurst(storm: storm, size: geo.size)
                    }
                    ForEach(visibleStorms) { storm in
                        StormPin(storm: storm)
                            .position(x: storm.x * geo.size.width,
                                      y: storm.y * geo.size.height)
                    }
                    // legend
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 10) {
                                LegendDot(color: Theme.sky, label: "Hail")
                                LegendDot(color: Theme.ember, label: "Wind")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(10)
                        }
                    }
                }
            }
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))

            // Year scrubber
            HStack(spacing: 8) {
                ForEach(years, id: \.self) { y in
                    Button {
                        withAnimation(.spring(duration: 0.35)) { selectedYear = y }
                    } label: {
                        Text(String(y))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(selectedYear == y ? .white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedYear == y
                                ? AnyShapeStyle(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Theme.canvas)
                            )
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Summary stats
            HStack(spacing: 10) {
                StormStat(icon: "cloud.hail.fill", tint: Theme.sky,
                          value: "\(summary.hailEvents)",
                          label: "Hail events",
                          sub: summary.maxHail > 0 ? String(format: "max %.2f″", summary.maxHail) : "—")
                StormStat(icon: "wind", tint: Theme.ember,
                          value: "\(summary.windEvents)",
                          label: "Wind events",
                          sub: summary.maxWind > 0 ? "max \(summary.maxWind) mph" : "—")
                StormStat(icon: "house.fill", tint: Theme.mint,
                          value: "126",
                          label: "Properties",
                          sub: "in your book")
            }
        }
        .cardStyle(padding: 18, radius: 24)
        .padding(.horizontal, 20)
    }
}

private struct StormTypeChip: View {
    let type: StormType
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(type.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? type.color : Theme.canvas, in: .capsule)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: active ? 0 : 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct StormBurst: View {
    let storm: StormEvent
    let size: CGSize

    var body: some View {
        let r = storm.radius * min(size.width, size.height)
        Circle()
            .fill(
                RadialGradient(colors: [
                    storm.type.color.opacity(0.35 * storm.intensity),
                    storm.type.color.opacity(0.10 * storm.intensity),
                    storm.type.color.opacity(0.0)
                ], center: .center, startRadius: 0, endRadius: r)
            )
            .frame(width: r * 2, height: r * 2)
            .position(x: storm.x * size.width, y: storm.y * size.height)
            .blendMode(.multiply)
    }
}

private struct StormPin: View {
    let storm: StormEvent
    var body: some View {
        ZStack {
            Circle().fill(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Circle().fill(storm.type.color).frame(width: 18, height: 18)
            Image(systemName: storm.type.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }
}

private struct StormStat: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(sub)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Stylized map terrain

struct StormMapBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.mapLand

                // City blocks (grid)
                Canvas { ctx, size in
                    let cols = 7, rows = 5
                    let cw = size.width / CGFloat(cols)
                    let rh = size.height / CGFloat(rows)
                    for r in 0..<rows {
                        for c in 0..<cols {
                            let x = CGFloat(c) * cw + 4
                            let y = CGFloat(r) * rh + 4
                            let block = CGRect(x: x, y: y, width: cw - 8, height: rh - 8)
                            ctx.fill(Path(roundedRect: block, cornerRadius: 3),
                                     with: .color(Theme.mapBlock))
                        }
                    }
                }

                // Park
                Path { p in
                    p.addRoundedRect(in: CGRect(x: w * 0.08, y: h * 0.55, width: w * 0.20, height: h * 0.20),
                                     cornerSize: .init(width: 8, height: 8))
                }
                .fill(Theme.mapPark)

                // Water
                Path { p in
                    p.move(to: CGPoint(x: w * 0.85, y: 0))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.6),
                                   control: CGPoint(x: w * 1.05, y: h * 0.3))
                    p.addLine(to: CGPoint(x: w, y: 0))
                    p.closeSubpath()
                }
                .fill(Theme.mapWater)

                // Roads (grid)
                Canvas { ctx, size in
                    let road = GraphicsContext.Shading.color(Theme.mapRoad)
                    for x in stride(from: CGFloat(0), through: size.width, by: size.width / 7) {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: road, lineWidth: 4)
                    }
                    for y in stride(from: CGFloat(0), through: size.height, by: size.height / 5) {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: road, lineWidth: 4)
                    }
                }

                // Highway diagonal
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.20))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.85),
                                   control: CGPoint(x: w * 0.45, y: h * 0.30))
                }
                .stroke(Theme.mapHighway, style: .init(lineWidth: 8, lineCap: .round))
                .overlay(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.20))
                        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.85),
                                       control: CGPoint(x: w * 0.45, y: h * 0.30))
                    }
                    .stroke(.white, style: .init(lineWidth: 1.2, dash: [6, 6]))
                )
            }
        }
    }
}
