import SwiftUI
import MapKit
import CoreLocation

// MARK: - Sky mood + atmospheric background
//
// Shared by WeatherHubCard (home hero) and WeatherHubView (full screen).
// Picks a legible dark-enough gradient by condition so white text always
// reads, and animates drifting clouds / rain / a flickering bolt with a
// cheap Canvas. Honors reduce-motion via `paused`.

enum WeatherSkyMood: Equatable {
    case clear, cloudy, rain, storm

    static func from(_ condition: String, hailRisk: Int) -> WeatherSkyMood {
        let c = condition.lowercased()
        if c.contains("storm") || c.contains("thunder") || c.contains("hail")
            || c.contains("tornado") || hailRisk >= 60 { return .storm }
        if c.contains("rain") || c.contains("drizzle") || c.contains("shower")
            || hailRisk >= 35 { return .rain }
        if c.contains("cloud") || c.contains("overcast") || c.contains("fog")
            || c.contains("haze") || c.contains("mist") { return .cloudy }
        return .clear
    }

    var gradient: [Color] {
        switch self {
        case .clear:
            return [Color(red: 0.15, green: 0.40, blue: 0.76),
                    Color(red: 0.21, green: 0.53, blue: 0.89),
                    Color(red: 0.36, green: 0.66, blue: 0.96)]
        case .cloudy:
            return [Color(red: 0.28, green: 0.34, blue: 0.45),
                    Color(red: 0.40, green: 0.46, blue: 0.55),
                    Color(red: 0.50, green: 0.55, blue: 0.62)]
        case .rain:
            return [Color(red: 0.12, green: 0.19, blue: 0.32),
                    Color(red: 0.19, green: 0.28, blue: 0.42),
                    Color(red: 0.27, green: 0.36, blue: 0.50)]
        case .storm:
            return [Color(red: 0.05, green: 0.08, blue: 0.19),
                    Color(red: 0.10, green: 0.15, blue: 0.29),
                    Color(red: 0.17, green: 0.22, blue: 0.38)]
        }
    }
}

struct WeatherSkyBackground: View {
    let mood: WeatherSkyMood
    var showRain: Bool = false
    var intense: Bool = false
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { timeline in
            let t = paused ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: mood.gradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { ctx, size in
                    draw(&ctx, size: size, t: t)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        // Sun glow (clear days)
        if mood == .clear {
            let cx = size.width * 0.82
            let cy = size.height * 0.22
            let r = max(size.width, size.height) * 0.45
            let circle = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.fill(circle, with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 2, endRadius: r))
        }

        // Drifting cloud blobs
        let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat, op: Double, speed: Double)] = [
            (0.22, 0.30, 64, 0.10, 7),
            (0.55, 0.18, 88, 0.12, 11),
            (0.84, 0.52, 92, 0.08, 9),
            (0.34, 0.74, 70, 0.07, 13)
        ]
        for b in blobs {
            let span = size.width + 260
            let dx = CGFloat((t / b.speed).truncatingRemainder(dividingBy: 1.0)) * span - 130
            let x = b.x * size.width + dx
            let rect = CGRect(x: x - b.r, y: b.y * size.height - b.r, width: b.r * 2, height: b.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(b.op)))
        }

        // Rain streaks
        if showRain {
            let count = intense ? 42 : 24
            let speed = intense ? 1.7 : 1.15
            for i in 0..<count {
                let phase = (t * speed + Double(i) * 0.137).truncatingRemainder(dividingBy: 1.0)
                let x = CGFloat(i) / CGFloat(count) * size.width + CGFloat((i % 4) * 5)
                let y = CGFloat(phase) * (size.height + 36) - 18
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x - 6, y: y + 16))
                ctx.stroke(p, with: .color(.white.opacity(0.20)), lineWidth: 1)
            }
        }

        // Flickering lightning (storm)
        if mood == .storm {
            let flick = sin(t * 5.0) > 0.78 ? 0.85 : 0.0
            if flick > 0 {
                var bolt = Path()
                bolt.move(to: CGPoint(x: size.width * 0.74, y: size.height * 0.08))
                bolt.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.46))
                bolt.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.48))
                bolt.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.90))
                ctx.stroke(bolt, with: .color(Theme.amber.opacity(flick)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Roof Work Window
//
// Deterministic, on-brand read for a roofer: is it safe to be on the roof
// right now? Derived from the live snapshot (wind / gusts / precip /
// lightning / temp / condition). No new service — pure function.

enum RoofWorkWindow {
    case good, caution, hold

    var title: String {
        switch self {
        case .good:    return "Good to climb"
        case .caution: return "Climb with caution"
        case .hold:    return "Hold off — unsafe"
        }
    }

    var shortLabel: String {
        switch self {
        case .good:    return "GOOD"
        case .caution: return "CAUTION"
        case .hold:    return "HOLD"
        }
    }

    var icon: String {
        switch self {
        case .good:    return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .hold:    return "hand.raised.fill"
        }
    }

    var color: Color {
        switch self {
        case .good:    return Theme.mint
        case .caution: return Theme.amber
        case .hold:    return Theme.crimson
        }
    }

    static func assess(_ s: WeatherSnapshot) -> RoofWorkWindow {
        let gust = max(s.windMph, s.windGustMph ?? 0)
        let precip = s.precipProbabilityPct ?? 0
        let lightning = s.lightningProbabilityPct ?? 0
        let temp = s.temperatureF
        let c = s.condition.lowercased()
        let stormy = c.contains("storm") || c.contains("thunder")
            || c.contains("hail") || c.contains("tornado")
        if s.windMph > 25 || gust > 32 || precip >= 60 || lightning >= 30
            || temp < 32 || stormy { return .hold }
        if s.windMph >= 15 || gust >= 24 || precip >= 30 || lightning >= 10
            || temp <= 40 || temp > 95 || c.contains("rain") { return .caution }
        return .good
    }

    static func reasons(_ s: WeatherSnapshot) -> [String] {
        var out: [String] = []
        let gust = max(s.windMph, s.windGustMph ?? 0)
        let precip = s.precipProbabilityPct ?? 0
        let lightning = s.lightningProbabilityPct ?? 0
        if s.windMph >= 15 {
            out.append("Wind \(s.windMph) mph" + (gust > s.windMph ? " · gusts \(gust) mph" : ""))
        }
        if precip >= 30 { out.append("Rain chance \(precip)%") }
        if lightning >= 10 { out.append("Lightning risk \(lightning)%") }
        if s.temperatureF < 40 { out.append("Cold \(s.temperatureF)°F — shingles brittle") }
        if s.temperatureF > 95 { out.append("Heat \(s.temperatureF)°F — asphalt soft underfoot") }
        let c = s.condition.lowercased()
        if c.contains("hail") { out.append("Active hail — stay off the roof") }
        if out.isEmpty { out.append("Calm winds, dry deck, mild temps — clear to work") }
        return out
    }
}

// MARK: - Navigation routes

enum WeatherHubRoute: Hashable {
    case stormMap
    case focusedStorm(StormPinEvent)
}

// MARK: - Weather Hub (full screen)

struct WeatherHubView: View {
    var coord: CLLocationCoordinate2D? = nil
    var locationLabel: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: WeatherSnapshot? = nil
    @State private var hourly: [WeatherHourlySample] = []
    @State private var loadError = false
    @State private var path: [WeatherHubRoute] = []
    @State private var mapCam: MapCameraPosition = .region(
        MKCoordinateRegion(center: .planoTX,
                           span: .init(latitudeDelta: 0.12, longitudeDelta: 0.12))
    )
    @State private var location = LocationService.shared
    @State private var alertStore = StormAlertStore.shared

    private let service: WeatherServicing = WeatherServiceFactory.shared

    private var activeCoord: CLLocationCoordinate2D {
        coord ?? location.coordinate ?? .planoTX
    }
    private var activeLabel: String {
        locationLabel ?? location.placeLabel ?? "Locating…"
    }
    private var activeAlerts: [StormAlert] {
        alertStore.alerts.filter { $0.isActive }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    heroHeader
                    if let snap = snapshot {
                        roofWindowCard(snap)
                        riskGauges(snap)
                    }
                    mapCard
                    hourlyCard
                    if !activeAlerts.isEmpty { alertsCard(activeAlerts) }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Theme.canvas)
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WeatherHubRoute.self) { route in
                switch route {
                case .stormMap:
                    MapHubView()
                case .focusedStorm(let pin):
                    MapHubView(focusedStorm: pin, initialRadiusFilterMiles: 5)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                        .shadow(color: Theme.ink.opacity(0.25), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.canvas)
            }
        }
        .task {
            location.start()
            recenterMap()
            await load()
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            recenterMap()
            Task { await load() }
        }
    }

    // MARK: Hero

    private var heroHeader: some View {
        let mood = WeatherSkyMood.from(snapshot?.condition ?? "", hailRisk: snapshot?.hailRiskPct ?? 0)
        return ZStack(alignment: .topLeading) {
            WeatherSkyBackground(mood: mood,
                                 showRain: (mood == .rain || mood == .storm) && !reduceMotion,
                                 intense: mood == .storm,
                                 paused: reduceMotion)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text(activeLabel)
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text(updatedLabel)
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: weatherSymbol(for: snapshot?.condition))
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(snapshot.map { "\($0.temperatureF)" } ?? "—")
                                .font(.system(size: 60, weight: .heavy))
                                .monospacedDigit()
                            Text("°")
                                .font(.system(size: 30, weight: .heavy))
                                .baselineOffset(16)
                        }
                        .foregroundStyle(.white)
                        Text(snapshot?.condition ?? (loadError ? "Weather unavailable" : "Loading…"))
                            .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
        }
        .frame(height: 226)
        .clipShape(.rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: Theme.ink.opacity(0.22), radius: 18, x: 0, y: 8)
    }

    private var updatedLabel: String {
        guard let snap = snapshot else { return APIKeys.modeLabel }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Updated \(f.localizedString(for: snap.updatedAt, relativeTo: .now))"
    }

    // MARK: Roof Work Window

    private func roofWindowCard(_ snap: WeatherSnapshot) -> some View {
        let w = RoofWorkWindow.assess(snap)
        return HStack(spacing: 0) {
            Rectangle().fill(w.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(w.color.opacity(0.15))
                        Image(systemName: w.icon)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(w.color)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ROOF WORK WINDOW")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Theme.inkSoft)
                        Text(w.title)
                            .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(RoofWorkWindow.reasons(snap), id: \.self) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(w.color).frame(width: 5, height: 5)
                            Text(r)
                                .font(.system(size: Theme.TypeRamp.meta, weight: .medium))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: Theme.ink.opacity(0.04), radius: 14, x: 0, y: 6)
    }

    // MARK: Risk gauges

    private func riskGauges(_ snap: WeatherSnapshot) -> some View {
        HStack(spacing: 10) {
            WeatherRiskRing(label: "Hail Risk",
                            display: "\(snap.hailRiskPct)%",
                            tint: snap.hailRiskPct > 50 ? Theme.crimson : Theme.amber,
                            icon: "cloud.hail.fill",
                            fraction: Double(snap.hailRiskPct) / 100)
            WeatherRiskRing(label: "Wind",
                            display: "\(snap.windMph)",
                            tint: Theme.sky,
                            icon: "wind",
                            fraction: min(1, Double(snap.windMph) / 40))
            WeatherRiskRing(label: "Rain",
                            display: "\(snap.precipProbabilityPct ?? snap.hailRiskPct)%",
                            tint: Theme.sky,
                            icon: "cloud.rain.fill",
                            fraction: Double(snap.precipProbabilityPct ?? 0) / 100)
        }
        .cardStyle(padding: 16, radius: 22)
    }

    // MARK: Map

    private var mapCard: some View {
        let coord = activeCoord
        let risk = snapshot?.hailRiskPct ?? 0
        let riskColor: Color = risk > 50 ? Theme.crimson : (risk > 20 ? Theme.amber : Theme.sky)
        let radius = 1500.0 + Double(risk) * 55.0
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Map(position: $mapCam, interactionModes: []) {
                    Annotation("", coordinate: coord) {
                        ZStack {
                            Circle().fill(.white)
                            Circle().fill(Theme.ember).padding(3)
                            Image(systemName: "house.fill")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                    MapCircle(center: coord, radius: radius)
                        .foregroundStyle(riskColor.opacity(0.16))
                        .stroke(riskColor.opacity(0.7), lineWidth: 1.5)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 200)
                .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .heavy))
                    Text("HAIL-RISK RADIUS")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.95), in: .capsule)
                .shadow(color: Theme.ink.opacity(0.12), radius: 6, y: 2)
                .padding(12)
            }
            .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                path.append(.stormMap)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Open Storm Map")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.04), radius: 14, x: 0, y: 6)
    }

    // MARK: Hourly

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NEXT 24 HOURS", icon: "clock.fill", tint: Theme.sky)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if hourly.isEmpty {
                        ForEach(0..<8, id: \.self) { _ in hourPlaceholder }
                    } else {
                        ForEach(hourly) { s in hourCell(s) }
                    }
                }
            }
            .contentMargins(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 22)
    }

    private func hourCell(_ s: WeatherHourlySample) -> some View {
        VStack(spacing: 8) {
            Text(hourLabel(s.date))
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Image(systemName: s.symbolName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.sky)
                .frame(height: 28)
            Text("\(s.temperatureF)°")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(s.precipPct)%")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(s.precipPct > 50 ? Theme.crimson : Theme.inkFaint)
        }
        .frame(width: 60)
        .padding(.vertical, 10)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private var hourPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.canvas)
            .frame(width: 60, height: 104)
            .overlay(ProgressView())
    }

    // MARK: Storm alerts

    private func alertsCard(_ alerts: [StormAlert]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("STORM ALERTS", icon: "exclamationmark.triangle.fill", tint: Theme.ember)
            VStack(spacing: 10) {
                ForEach(alerts.prefix(4)) { a in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        path.append(.focusedStorm(a.asPinEvent))
                    } label: {
                        alertRow(a)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 22)
    }

    private func alertRow(_ a: StormAlert) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.emberSoft)
                Image(systemName: stormIcon(a.eventType))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.headline)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(String(format: "%.1f", a.distanceMi)) mi · \(a.eventDate.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 16))
    }

    private func stormIcon(_ kind: StormEventType) -> String {
        switch kind {
        case .hail: return "cloud.hail.fill"
        case .wind: return "wind"
        case .tornado: return "tornado"
        }
    }

    // MARK: Shared bits

    private func sectionLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f.string(from: date).lowercased()
    }

    private func recenterMap() {
        mapCam = .region(MKCoordinateRegion(
            center: activeCoord,
            span: .init(latitudeDelta: 0.12, longitudeDelta: 0.12)))
    }

    private func load() async {
        loadError = false
        async let snapTask = try? service.currentConditions(at: activeCoord)
        async let hourlyTask = try? service.hourlyForecast(at: activeCoord)
        let snap = await snapTask
        let hrs = await hourlyTask
        await MainActor.run {
            if let snap { self.snapshot = snap } else { self.loadError = true }
            self.hourly = hrs ?? []
        }
    }
}

// MARK: - Risk ring

private struct WeatherRiskRing: View {
    let label: String
    let display: String
    let tint: Color
    let icon: String
    let fraction: Double

    @State private var animated = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: animated ? max(0.02, min(1, fraction)) : 0)
                    .stroke(LinearGradient(colors: [tint.opacity(0.7), tint],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(tint)
                    Text(display)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }
            .frame(width: 80, height: 80)
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(Theme.Motion.entrance.delay(0.12)) { animated = true }
        }
    }
}
