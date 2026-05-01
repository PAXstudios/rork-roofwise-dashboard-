import SwiftUI

struct StormHistoryMapCard: View {
    @State private var selectedYear: Int? = nil   // nil == All
    @State private var selectedTypes: Set<StormType> = [.hail, .wind]
    @State private var detailStorm: StormEvent?

    private let years: [Int] = [2022, 2023, 2024, 2025]

    private var visibleStorms: [StormEvent] {
        MockData.storms.filter {
            (selectedYear == nil || $0.year == selectedYear!) &&
            selectedTypes.contains($0.type)
        }
    }

    private var summary: (hailEvents: Int, maxHail: Double, windEvents: Int, maxWind: Int, properties: Int) {
        let scoped = MockData.storms.filter { selectedYear == nil || $0.year == selectedYear! }
        let hails = scoped.filter { $0.type == .hail }
        let winds = scoped.filter { $0.type == .wind }
        return (
            hails.count,
            hails.compactMap { $0.sizeInches }.max() ?? 0,
            winds.count,
            winds.compactMap { $0.windMPH }.max() ?? 0,
            scoped.reduce(0) { $0 + $1.propertiesAffected }
        )
    }

    private var typeMode: TypeMode {
        if selectedTypes.count == 2 { return .both }
        return selectedTypes.contains(.hail) ? .hail : .wind
    }

    enum TypeMode: String, CaseIterable, Identifiable {
        case hail = "Hail", wind = "Wind", both = "Both"
        var id: String { rawValue }
        var icon: String {
            switch self { case .hail: "cloud.hail.fill"; case .wind: "wind"; case .both: "cloud.bolt.rain.fill" }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            typeToggle
            mapView
            yearScrubber
            statsBar
            intensityLegend
        }
        .cardStyle(padding: 18, radius: 24)
        .padding(.horizontal, 20)
        .sheet(item: $detailStorm) { storm in
            StormDetailSheet(storm: storm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.bolt.rain.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ember)
                    Text("4-YEAR STORM INTEL")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text("Hail & Wind History")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Plano · Frisco · McKinney · Collin Co.")
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
    }

    private var typeToggle: some View {
        HStack(spacing: 8) {
            ForEach(TypeMode.allCases) { mode in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        switch mode {
                        case .hail: selectedTypes = [.hail]
                        case .wind: selectedTypes = [.wind]
                        case .both: selectedTypes = [.hail, .wind]
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(typeMode == mode ? .white : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(typeMode == mode ? Theme.ink : Theme.canvas, in: .capsule)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: typeMode == mode ? 0 : 0.6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var mapView: some View {
        GeometryReader { geo in
            ZStack {
                StormMapBackground()
                ForEach(visibleStorms) { storm in
                    StormBurst(storm: storm, size: geo.size)
                }
                ForEach(visibleStorms) { storm in
                    Button {
                        let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
                        detailStorm = storm
                    } label: {
                        StormPin(storm: storm)
                    }
                    .buttonStyle(.plain)
                    .position(x: storm.x * geo.size.width,
                              y: storm.y * geo.size.height)
                }
                // Year stamp
                VStack {
                    HStack {
                        Text(selectedYear.map(String.init) ?? "All Years")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var yearScrubber: some View {
        HStack(spacing: 8) {
            ForEach(years, id: \.self) { y in
                yearChip(label: String(y), active: selectedYear == y) {
                    withAnimation(.spring(duration: 0.35)) { selectedYear = y }
                }
            }
            yearChip(label: "All", active: selectedYear == nil) {
                withAnimation(.spring(duration: 0.35)) { selectedYear = nil }
            }
        }
    }

    private func yearChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    active
                    ? AnyShapeStyle(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Theme.canvas)
                )
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var statsBar: some View {
        HStack(spacing: 10) {
            StormStat(icon: "cloud.hail.fill", tint: Theme.sky,
                      value: "\(summary.hailEvents)",
                      label: "Hail",
                      sub: summary.maxHail > 0 ? String(format: "max %.2f″", summary.maxHail) : "—")
            StormStat(icon: "wind", tint: Theme.ember,
                      value: "\(summary.windEvents)",
                      label: "Wind",
                      sub: summary.maxWind > 0 ? "max \(summary.maxWind) mph" : "—")
            StormStat(icon: "house.fill", tint: Theme.mint,
                      value: "\(summary.properties)",
                      label: "Properties",
                      sub: "affected")
        }
    }

    private var intensityLegend: some View {
        HStack(spacing: 14) {
            IntensityDot(band: .light)
            IntensityDot(band: .moderate)
            IntensityDot(band: .severe)
            Spacer()
            Text("Tap a pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.top, 2)
    }
}

private struct IntensityDot: View {
    let band: StormEvent.IntensityBand
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(band.color.opacity(0.25)).frame(width: 14, height: 14)
                Circle().fill(band.color).frame(width: 8, height: 8)
            }
            Text(band.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
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
                    storm.band.color.opacity(0.45),
                    storm.band.color.opacity(0.18),
                    storm.band.color.opacity(0.0)
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
            Circle()
                .stroke(storm.band.color.opacity(0.35), lineWidth: 6)
                .frame(width: 38, height: 38)
            Circle().fill(.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle().fill(storm.band.color).frame(width: 22, height: 22)
            Image(systemName: storm.type.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
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
        VStack(alignment: .leading, spacing: 6) {
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
                .monospacedDigit()
            Text(sub)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Detail sheet

private struct StormDetailSheet: View {
    let storm: StormEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(.white.opacity(0.25))
                            Image(systemName: storm.type.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(storm.type.rawValue + " Storm")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(storm.date)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Text(storm.band.label.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.22), in: .capsule)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [storm.band.color, storm.band.color.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 20)
                )

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    DetailStat(icon: "calendar", label: "Date", value: storm.date)
                    DetailStat(icon: storm.type.icon, label: "Storm Type", value: storm.type.rawValue)
                    if let size = storm.sizeInches {
                        DetailStat(icon: "cloud.hail.fill", label: "Max Hail Size", value: String(format: "%.2f″", size))
                    } else {
                        DetailStat(icon: "cloud.hail.fill", label: "Max Hail Size", value: "—")
                    }
                    if let mph = storm.windMPH {
                        DetailStat(icon: "wind", label: "Max Wind", value: "\(mph) mph")
                    } else {
                        DetailStat(icon: "wind", label: "Max Wind", value: "—")
                    }
                    DetailStat(icon: "house.fill", label: "Properties Affected", value: "\(storm.propertiesAffected)")
                    DetailStat(icon: "gauge.with.needle.fill", label: "Intensity", value: "\(Int(storm.intensity * 100))%")
                }

                // Action
                Button {} label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait")
                        Text("View affected properties")
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

private struct DetailStat: View {
    let icon: String
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ember)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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
