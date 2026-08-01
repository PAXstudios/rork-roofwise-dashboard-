import SwiftUI
import CoreLocation

/// Compact storm-intel card. Pulls live NOAA events for the user's area —
/// never invents storms.
struct StormHistoryMapCard: View {
    var embedded: Bool = false
    @State private var alertStore = StormAlertStore.shared
    @State private var events: [StormPinEvent] = []
    @State private var isLoading = false
    @State private var selectedTypes: Set<StormEventType> = [.hail, .wind, .tornado]
    @State private var showMap = false
    @State private var loadError: String?

    private var visible: [StormPinEvent] {
        events.filter { selectedTypes.contains($0.eventType) }
    }

    private var summary: (hail: Int, wind: Int, tornado: Int, maxHail: Double, maxWind: Int) {
        let hail = events.filter { $0.eventType == .hail }
        let wind = events.filter { $0.eventType == .wind }
        let tornado = events.filter { $0.eventType == .tornado }
        return (
            hail.count,
            wind.count,
            tornado.count,
            hail.compactMap(\.hailSizeIn).max() ?? 0,
            wind.compactMap(\.windGustMph).max() ?? 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            typeToggle
            mapPreview
            statsBar
            cta
        }
        .cardStyle(padding: 18, radius: 22)
        .padding(.horizontal, embedded ? 0 : 20)
        .task { await load() }
        .fullScreenCover(isPresented: $showMap) {
            NavigationStack {
                MapHubView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showMap = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.bolt.rain.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ember)
                    Text("STORM INTEL")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text("Hail · Wind · Tornado")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(areaLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var areaLabel: String {
        let areas = ServiceAreaStore.shared.areas
        if areas.isEmpty { return "Set a service area to load history" }
        return areas.prefix(3).map(\.label).joined(separator: " · ")
    }

    private var typeToggle: some View {
        HStack(spacing: 8) {
            typeChip("Hail", type: .hail, icon: "cloud.hail.fill")
            typeChip("Wind", type: .wind, icon: "wind")
            typeChip("Tornado", type: .tornado, icon: "tornado")
            Spacer()
        }
    }

    private func typeChip(_ label: String, type: StormEventType, icon: String) -> some View {
        let on = selectedTypes.contains(type)
        return Button {
            withAnimation(.spring(duration: 0.25)) {
                if on, selectedTypes.count > 1 { selectedTypes.remove(type) }
                else { selectedTypes.insert(type) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundStyle(on ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(on ? Theme.ink : Theme.canvas, in: .capsule)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: on ? 0 : 0.6))
        }
        .buttonStyle(.plain)
    }

    private var mapPreview: some View {
        ZStack {
            Theme.mapLand
            GeometryReader { geo in
                let pts = normalizedPoints(in: visible)
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(color(for: p.event).opacity(0.55))
                        .frame(width: 14, height: 14)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            }
            if visible.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.slash")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    Text(loadError ?? "No storm events in range yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var statsBar: some View {
        HStack(spacing: 10) {
            stat(icon: "cloud.hail.fill", tint: Theme.sky,
                 value: "\(summary.hail)",
                 label: "Hail",
                 sub: summary.maxHail > 0 ? String(format: "max %.2f″", summary.maxHail) : "—")
            stat(icon: "wind", tint: Theme.ember,
                 value: "\(summary.wind)",
                 label: "Wind",
                 sub: summary.maxWind > 0 ? "max \(summary.maxWind) mph" : "—")
            stat(icon: "tornado", tint: Theme.crimson,
                 value: "\(summary.tornado)",
                 label: "Tornado",
                 sub: "events")
        }
    }

    private func stat(icon: String, tint: Color, value: String, label: String, sub: String) -> some View {
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

    private var cta: some View {
        Button {
            showMap = true
        } label: {
            HStack {
                Image(systemName: "map.fill")
                Text("Open storm map")
            }
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let fromAlerts = alertStore.alerts.map(\.asPinEvent)
        if !fromAlerts.isEmpty {
            events = Array(fromAlerts.prefix(40))
        }

        let areas = ServiceAreaStore.shared.areas
        if areas.isEmpty, events.isEmpty {
            loadError = "Add a service-area ZIP to load history"
            return
        }

        let center: CLLocationCoordinate2D = {
            if let a = alertStore.alerts.first {
                return CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
            }
            if let loc = LocationService.shared.coordinate {
                return loc
            }
            // Continental US fallback only when nothing else is known so the
            // request still returns nearby events for first-run demos.
            return CLLocationCoordinate2D(latitude: 33.0198, longitude: -96.6989)
        }()

        do {
            let fetched = try await StormEventsServiceFactory.shared.events(
                near: center,
                radiusMi: 75,
                sinceMonthsBack: 37
            )
            if !fetched.isEmpty {
                events = fetched.prefix(60).map { e in
                    StormPinEvent(
                        date: e.eventDate,
                        hailSizeIn: e.magnitudeIn,
                        windGustMph: e.windMph,
                        latitude: e.latitude,
                        longitude: e.longitude,
                        source: e.source,
                        eventType: e.eventType
                    )
                }
            }
        } catch {
            if events.isEmpty {
                loadError = "Couldn't reach storm history right now"
            }
        }
    }

    private struct Pt {
        let event: StormPinEvent
        let x: CGFloat
        let y: CGFloat
    }

    private func normalizedPoints(in list: [StormPinEvent]) -> [Pt] {
        guard !list.isEmpty else { return [] }
        let lats = list.map(\.latitude)
        let lons = list.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 1
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 1
        let dLat = max(0.01, maxLat - minLat)
        let dLon = max(0.01, maxLon - minLon)
        return list.map { e in
            let x = CGFloat((e.longitude - minLon) / dLon) * 0.8 + 0.1
            let y = CGFloat(1 - (e.latitude - minLat) / dLat) * 0.8 + 0.1
            return Pt(event: e, x: x, y: y)
        }
    }

    private func color(for e: StormPinEvent) -> Color {
        switch e.eventType {
        case .hail: return Theme.sky
        case .wind: return Theme.ember
        case .tornado: return Theme.crimson
        }
    }
}
