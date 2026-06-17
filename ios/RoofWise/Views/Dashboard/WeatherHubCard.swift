import SwiftUI
import CoreLocation

/// Always-on weather hero that sits at the very top of the dashboard. It shows
/// live conditions over an animated atmospheric sky, a one-glance "Roof Work
/// Window" verdict (is it safe to be on the roof right now?), and quick wind /
/// hail / rain metrics. Tapping opens the full `WeatherHubView`.
struct WeatherHubCard: View {
    /// Optional explicit coordinate. When nil, follows the user's live location
    /// (falling back to Plano, TX until the first fix arrives).
    var coord: CLLocationCoordinate2D? = nil
    var locationLabel: String? = nil

    @State private var snapshot: WeatherSnapshot? = nil
    @State private var loadError = false
    @State private var showHub = false
    @State private var location = LocationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let service: WeatherServicing = WeatherServiceFactory.shared

    private var activeCoord: CLLocationCoordinate2D {
        coord ?? location.coordinate ?? .planoTX
    }
    private var activeLabel: String {
        locationLabel ?? location.placeLabel ?? "Locating…"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showHub = true
        } label: {
            card
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .task {
            location.start()
            await load()
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            Task { await load() }
        }
        .fullScreenCover(isPresented: $showHub) {
            WeatherHubView(coord: coord, locationLabel: locationLabel)
        }
    }

    private var card: some View {
        let mood = WeatherSkyMood.from(snapshot?.condition ?? "", hailRisk: snapshot?.hailRiskPct ?? 0)
        return ZStack {
            WeatherSkyBackground(mood: mood,
                                 showRain: (mood == .rain || mood == .storm) && !reduceMotion,
                                 intense: mood == .storm,
                                 paused: reduceMotion)
            content
        }
        .frame(height: 188)
        .clipShape(.rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: Theme.ink.opacity(0.20), radius: 16, x: 0, y: 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .heavy))
                    Text(activeLabel)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text("Weather")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: weatherSymbol(for: snapshot?.condition))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(snapshot.map { "\($0.temperatureF)" } ?? "—")
                            .font(.system(size: 52, weight: .heavy))
                            .monospacedDigit()
                        Text("°")
                            .font(.system(size: 26, weight: .heavy))
                            .baselineOffset(14)
                    }
                    .foregroundStyle(.white)
                    Text(snapshot?.condition ?? (loadError ? "Weather unavailable" : "Loading…"))
                        .font(.system(size: Theme.TypeRamp.bodyTight, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                roofWindowBadge
            }

            Spacer(minLength: 0)

            metricsRow
        }
        .padding(18)
    }

    @ViewBuilder
    private var roofWindowBadge: some View {
        if let snap = snapshot {
            let w = RoofWorkWindow.assess(snap)
            VStack(spacing: 4) {
                Image(systemName: w.icon)
                    .font(.system(size: 16, weight: .heavy))
                Text(w.shortLabel)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(width: 76, height: 64)
            .background(w.color.opacity(0.92), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metricChip(icon: "wind", text: "\(snapshot?.windMph ?? 0) mph")
            metricChip(icon: "cloud.hail.fill", text: "\(snapshot?.hailRiskPct ?? 0)% hail")
            metricChip(icon: "cloud.rain.fill",
                       text: "\(snapshot?.precipProbabilityPct ?? snapshot?.hailRiskPct ?? 0)% rain")
            Spacer(minLength: 0)
        }
    }

    private func metricChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(text)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.16), in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6))
    }

    private func load() async {
        loadError = false
        do {
            let snap = try await service.currentConditions(at: activeCoord)
            await MainActor.run { self.snapshot = snap }
        } catch {
            await MainActor.run { self.loadError = true }
        }
    }
}
