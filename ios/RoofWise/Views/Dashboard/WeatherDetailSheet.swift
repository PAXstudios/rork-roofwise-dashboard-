import SwiftUI
import CoreLocation

struct WeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let coord: CLLocationCoordinate2D
    var locationLabel: String = "Plano, TX"

    @State private var snapshot: WeatherSnapshot? = nil
    @State private var hourly: [WeatherHourlySample] = []
    @State private var loading: Bool = true

    private let service: WeatherServicing = WeatherServiceFactory.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    statsCard
                    hourlyCard
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                Button {
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
            .navigationTitle("Site Weather")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: weatherSymbol(for: snapshot?.condition))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Theme.sky)
                    .frame(width: 64, height: 64)
                    .background(Theme.skySoft, in: .rect(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(locationLabel)
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(snapshot?.condition ?? "—")
                        .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(snapshot?.temperatureF ?? 0)")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Text("°")
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .baselineOffset(8)
                }
            }

            HStack(spacing: 8) {
                tag(text: APIKeys.modeLabel,
                    icon: "antenna.radiowaves.left.and.right",
                    tint: APIKeys.USE_MOCKS ? Theme.inkSoft : Theme.mint)
                if let snap = snapshot {
                    let f = RelativeDateTimeFormatter()
                    let _ = (f.unitsStyle = .short)
                    tag(text: f.localizedString(for: snap.updatedAt, relativeTo: .now),
                        icon: "clock.fill",
                        tint: Theme.ember)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 22)
    }

    private var statsCard: some View {
        HStack(spacing: 10) {
            stat(label: "Wind",
                 value: "\(snapshot?.windMph ?? 0)",
                 unit: "mph",
                 icon: "wind",
                 tint: Theme.sky)
            stat(label: "Hail Risk",
                 value: "\(snapshot?.hailRiskPct ?? 0)",
                 unit: "%",
                 icon: "cloud.hail.fill",
                 tint: (snapshot?.hailRiskPct ?? 0) > 50 ? Theme.crimson : Theme.amber)
            stat(label: "Feels",
                 value: "\(snapshot?.temperatureF ?? 0)",
                 unit: "°F",
                 icon: "thermometer.medium",
                 tint: Theme.ember)
        }
    }

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT 24 HOURS")
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(hourly) { sample in
                        hourCell(sample)
                    }
                    if hourly.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in
                            hourPlaceholder
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 4)
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
            Text("\(s.precipPct)%")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                .foregroundStyle(s.precipPct > 50 ? Theme.crimson : Theme.inkFaint)
                .monospacedDigit()
        }
        .frame(width: 60)
        .padding(.vertical, 10)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private var hourPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.canvas)
            .frame(width: 60, height: 100)
            .overlay(
                ProgressView()
            )
    }

    private func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f.string(from: date).lowercased()
    }

    private func stat(label: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func tag(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
            Text(text)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .capsule)
    }

    private func load() async {
        loading = true
        async let snapTask = try? service.currentConditions(at: coord)
        async let hourlyTask = try? service.hourlyForecast(at: coord)
        let snap = await snapTask
        let hrs = await hourlyTask
        await MainActor.run {
            self.snapshot = snap
            self.hourly = hrs ?? []
            self.loading = false
        }
    }
}
