import SwiftUI

struct MapHubView: View {
    @State private var showLeads = true
    @State private var showJobs = true
    @State private var showStorms = true

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed map
            GeometryReader { geo in
                ZStack {
                    StormMapBackground()
                    ForEach(MockData.mapPins) { pin in
                        if shouldShow(pin) {
                            MapPinView(pin: pin)
                                .position(x: pin.x * geo.size.width,
                                          y: pin.y * geo.size.height)
                        }
                    }
                    // storm halo overlays
                    if showStorms {
                        ForEach(MockData.storms.filter { $0.year == 2026 }) { storm in
                            Circle()
                                .fill(
                                    RadialGradient(colors: [
                                        Theme.ember.opacity(0.30),
                                        Theme.ember.opacity(0.05),
                                        .clear
                                    ], center: .center, startRadius: 0,
                                       endRadius: storm.radius * geo.size.width)
                                )
                                .frame(width: storm.radius * geo.size.width * 2,
                                       height: storm.radius * geo.size.width * 2)
                                .position(x: storm.x * geo.size.width,
                                          y: storm.y * geo.size.height)
                                .blendMode(.multiply)
                        }
                    }
                }
            }
            .ignoresSafeArea()

            // Top control bar
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                        Text("Search the field")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkFaint)
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))

                    Button {} label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.ink, in: .rect(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    MapToggle(label: "Leads", icon: "person.fill", color: Theme.sky, on: $showLeads)
                    MapToggle(label: "Jobs", icon: "hammer.fill", color: Theme.mint, on: $showJobs)
                    MapToggle(label: "Storms", icon: "bolt.fill", color: Theme.ember, on: $showStorms)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)

            // Bottom info card
            VStack {
                Spacer()
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.ember)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hail core overlap detected")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("12 leads + 3 active jobs sit inside the Apr 18 swath. Build a 1.75″ canvas list?")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
                .padding(14)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
                .shadow(color: Theme.ink.opacity(0.10), radius: 14, y: 4)
                .padding(.horizontal, 16)
            }
        }
    }

    private func shouldShow(_ pin: MapPin) -> Bool {
        switch pin.kind {
        case .lead: return showLeads
        case .job: return showJobs
        case .storm: return showStorms
        }
    }
}

private struct MapToggle: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var on: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { on.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? .white : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                on ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThinMaterial),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MapPinView: View {
    let pin: MapPin
    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle().fill(pin.kind.color).frame(width: 24, height: 24)
            Image(systemName: pin.kind.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
