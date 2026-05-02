import SwiftUI

struct MapHubView: View {
    @State private var showLeads = true
    @State private var showJobs = true
    @State private var showStorms = true
    @State private var showKnocks = true

    // Door Knocking Mode
    @State private var knockStore = KnockStore()
    @State private var isKnockMode: Bool = false
    @State private var editingHouse: KnockedHouse?
    @State private var showFloatingScript: Bool = false
    @State private var floatingScriptOutcome: KnockOutcome = .interested

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed map
            GeometryReader { geo in
                ZStack {
                    StormMapBackground()

                    // Existing demo pins (leads / jobs / storms)
                    ForEach(MockData.mapPins) { pin in
                        if shouldShow(pin) {
                            MapPinView(pin: pin)
                                .position(x: pin.x * geo.size.width,
                                          y: pin.y * geo.size.height)
                        }
                    }

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

                    // Knock pins (always visible when toggle on)
                    if showKnocks && !isKnockMode {
                        ForEach(knockStore.houses) { h in
                            Button {
                                editingHouse = h
                            } label: {
                                KnockPinView(house: h)
                            }
                            .buttonStyle(.plain)
                            .position(x: h.x * geo.size.width,
                                      y: h.y * geo.size.height)
                        }
                    }
                }
            }
            .ignoresSafeArea()

            // Knock-mode tap overlay sits ABOVE the static demo pins so taps always
            // place new houses in knock mode.
            if isKnockMode {
                KnockModeOverlay(store: knockStore,
                                 editing: $editingHouse,
                                 emphasizedID: nil)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Top control bar
            VStack(spacing: 12) {
                if !isKnockMode {
                    standardTopBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)

            // Knock-mode HUD overlay
            if isKnockMode {
                KnockModeHUD(store: knockStore,
                             isOn: $isKnockMode,
                             showScriptAssistant: $showFloatingScript)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Floating Script Assistant card (when expanded in knock mode)
            if isKnockMode && showFloatingScript {
                VStack {
                    Spacer()
                    FloatingScriptCard(outcome: $floatingScriptOutcome)
                        .padding(.bottom, 140)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(.keyboard)
            }

            // Bottom info card / start-knock CTA — only when not in knock mode
            if !isKnockMode {
                VStack {
                    Spacer()
                    startKnockingCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .sheet(item: $editingHouse) { h in
            KnockOutcomeSheet(store: knockStore, houseID: h.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isKnockMode)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showFloatingScript)
    }

    // MARK: - Standard top bar (non-knock mode)

    private var standardTopBar: some View {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MapToggle(label: "Leads", icon: "person.fill", color: Theme.sky, on: $showLeads)
                    MapToggle(label: "Jobs", icon: "hammer.fill", color: Theme.mint, on: $showJobs)
                    MapToggle(label: "Storms", icon: "bolt.fill", color: Theme.ember, on: $showStorms)
                    MapToggle(label: "Knocks", icon: "hand.tap.fill", color: Theme.amber, on: $showKnocks)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Start knocking CTA card

    private var startKnockingCard: some View {
        Button {
            let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isKnockMode = true
                showKnocks = true
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.ember)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Door Knocking Mode")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(knockStore.houses.count)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.ember, in: .capsule)
                    }
                    Text("Tap houses on the street view to log outcomes. Color-coded pins, GPS-stamped, with built-in script assistant.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .lineLimit(3)
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
        }
        .buttonStyle(.plain)
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
