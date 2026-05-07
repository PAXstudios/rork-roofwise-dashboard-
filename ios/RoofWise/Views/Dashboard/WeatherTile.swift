import SwiftUI
import CoreLocation

struct WeatherTile: View {
    var coord: CLLocationCoordinate2D = .planoTX
    var locationLabel: String = "Plano, TX"

    @State private var snapshot: WeatherSnapshot? = nil
    @State private var loading: Bool = true
    @State private var loadError: Bool = false
    @State private var showSheet: Bool = false

    private let service: WeatherServicing = WeatherServiceFactory.shared

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSheet = true
        } label: {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: 18, radius: 22)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .task { await load() }
        .sheet(isPresented: $showSheet) {
            WeatherDetailSheet(coord: coord, locationLabel: locationLabel)
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 16) {
            symbolBadge
            VStack(alignment: .leading, spacing: 4) {
                if let snap = snapshot {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(snap.temperatureF)")
                            .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                        Text("°")
                            .font(.system(size: Theme.TypeRamp.titleSm, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .baselineOffset(8)
                    }
                    Text("\(locationLabel) · \(APIKeys.modeLabel)")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                } else if loadError {
                    Text("—")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                    Text("Weather unavailable")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Text("—°")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                    Text("Loading…")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(snapshot?.condition ?? "—")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Image(systemName: "wind")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                        .foregroundStyle(Theme.sky)
                    Text("\(snapshot?.windMph ?? 0) mph")
                        .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }
                Text(updatedLabel)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var symbolBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Theme.skySoft)
            Image(systemName: weatherSymbol(for: snapshot?.condition))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.sky)
        }
        .frame(width: 56, height: 56)
    }

    private var updatedLabel: String {
        guard let snap = snapshot else { return " " }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Updated \(f.localizedString(for: snap.updatedAt, relativeTo: .now))"
    }

    private func load() async {
        loading = true
        loadError = false
        do {
            let snap = try await service.currentConditions(at: coord)
            await MainActor.run {
                self.snapshot = snap
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = true
                self.loading = false
            }
        }
    }
}

func weatherSymbol(for condition: String?) -> String {
    guard let c = condition?.lowercased() else { return "cloud.sun.fill" }
    if c.contains("storm") || c.contains("thunder") { return "cloud.bolt.rain.fill" }
    if c.contains("hail")                          { return "cloud.hail.fill" }
    if c.contains("rain") || c.contains("drizzle") { return "cloud.rain.fill" }
    if c.contains("snow")                          { return "snowflake" }
    if c.contains("wind")                          { return "wind" }
    if c.contains("haz") || c.contains("fog")      { return "cloud.fog.fill" }
    if c.contains("partly") || c.contains("mostly cloudy") { return "cloud.sun.fill" }
    if c.contains("cloud")                         { return "cloud.fill" }
    if c.contains("sun") || c.contains("clear")    { return "sun.max.fill" }
    return "cloud.sun.fill"
}
