import SwiftUI
import MapKit
import CoreLocation

#if canImport(GoogleMaps)
import GoogleMaps
#endif

// MARK: - Lightweight on-map pin payload

struct MapEntityPin: Identifiable, Hashable {
    enum Kind: Hashable { case lead, job }
    let id: UUID = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var color: Color { kind == .lead ? Theme.sky : Theme.ember }
    var icon: String  { kind == .lead ? "person.fill" : "hammer.fill" }
}

// MARK: - Hub view

struct MapHubView: View {
    /// Optional inspection context. When set, the storm detail sheet exposes
    /// the "Use as evidence for current job" CTA, and an initial focus pin
    /// is selected on appear.
    var currentReportId: String? = nil
    var focusedStorm: StormPinEvent? = nil
    /// When set together with `focusedStorm`, applies a radius filter on appear
    /// so only impacted leads/jobs show alongside the storm itself.
    var initialRadiusFilterMiles: Double? = nil
    /// When set, the map recenters on this address on appear.
    var focusedAddress: String? = nil
    /// When set, draws each detected slope as a color-coded MKPolygon around
    /// the focused address (one quad per slope, sized by area, oriented by azimuth).
    var focusedRoof: RoofMeasurements? = nil

    // Layer toggles
    @State private var showLeads  = true
    @State private var showJobs   = true
    @State private var showStorms = true
    @State private var showKnocks = true

    // Storms date-range scrubber (months back).
    @State private var stormMonthsBack: Int = 24

    // Camera
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 33.05, longitude: -96.75),
                           span: .init(latitudeDelta: 0.45, longitudeDelta: 0.45))
    )
    @State private var lastRegion = MKCoordinateRegion(
        center: .init(latitude: 33.05, longitude: -96.75),
        span: .init(latitudeDelta: 0.45, longitudeDelta: 0.45)
    )

    // Data
    @State private var storms: [StormPinEvent] = []
    @State private var stormEvents: [NoaaStormEvent] = []
    @State private var radiusFilterMiles: Double? = nil
    @State private var radiusFilterCenter: CLLocationCoordinate2D? = nil

    // Sheets / selection
    @State private var selectedStorm: StormPinEvent?
    @State private var showAddressPicker = false
    @State private var pickedAddress: AddressSuggestion?

    // Knock state (preserved)
    @State private var knockStore = KnockStore()
    @State private var isKnockMode = false
    @State private var editingHouse: KnockedHouse?
    @State private var showFloatingScript = false
    @State private var floatingScriptOutcome: KnockOutcome = .interested

    // Services injected from APIKeys flag
    private let mapsService: MapsService = MapsServiceFactory.make()
    private let stormService: StormEventsServicing = StormEventsServiceFactory.shared
    private let geocoder: GeocodingService = GeocodingServiceFactory.shared

    // Pre-computed entity pins (mock-derived from existing stores).
    private var leadPins: [MapEntityPin] { Self.mockLeadPins }
    /// Lead pins narrowed to the active radius filter (if any).
    private var visibleLeadPins: [MapEntityPin] {
        guard let center = radiusFilterCenter, let miles = radiusFilterMiles else {
            return leadPins
        }
        return leadPins.filter { pin in
            CLLocation(latitude: pin.latitude, longitude: pin.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                / 1609.344 <= miles
        }
    }

    /// Job pins narrowed to the active radius filter (if any).
    private var visibleJobPins: [MapEntityPin] {
        guard let center = radiusFilterCenter, let miles = radiusFilterMiles else {
            return jobPins
        }
        return jobPins.filter { pin in
            CLLocation(latitude: pin.latitude, longitude: pin.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                / 1609.344 <= miles
        }
    }

    private var jobPins: [MapEntityPin] {
        let jobs = InspectionStore.shared.inspections.compactMap { insp -> MapEntityPin? in
            let addr = insp.job.propertyAddress.isEmpty
                ? insp.job.clientName
                : insp.job.propertyAddress
            guard !addr.isEmpty else { return nil }
            let c = Self.stableCoord(for: addr)
            return MapEntityPin(
                kind: .job,
                title: insp.job.clientName.isEmpty ? "Job" : insp.job.clientName,
                subtitle: addr,
                latitude: c.latitude,
                longitude: c.longitude
            )
        }
        return jobs.isEmpty ? Self.mockJobPins : jobs
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapCanvas
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if !isKnockMode {
                    standardTopBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)

            if isKnockMode {
                KnockModeHUD(store: knockStore,
                             isOn: $isKnockMode,
                             showScriptAssistant: $showFloatingScript)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if isKnockMode && showFloatingScript {
                VStack {
                    Spacer()
                    FloatingScriptCard(outcome: $floatingScriptOutcome)
                        .padding(.bottom, 140)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(.keyboard)
            }

            if !isKnockMode {
                VStack {
                    Spacer()
                    if let r = radiusFilterMiles {
                        radiusFilterChrome(miles: r)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    startKnockingCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            // Right-edge zoom + status overlay
            if !isKnockMode {
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer().frame(height: 120)
                    statusPill
                    Spacer()
                    zoomColumn
                }
                .padding(.trailing, 14)
                .padding(.bottom, 220)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(true)
            }
        }
        .task { await loadStorms() }
        .onAppear {
            presentFocusedStormIfNeeded()
            presentFocusedRoofIfNeeded()
        }
        .onChange(of: stormMonthsBack) { _, _ in
            Task { await loadStorms() }
        }
        .sheet(item: $editingHouse) { h in
            KnockOutcomeSheet(store: knockStore, houseID: h.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStorm) { storm in
            StormPinDetailSheet(
                event: storm,
                centerCoord: lastRegion.center,
                currentReportId: currentReportId,
                onFindNearby: { miles in
                    selectedStorm = nil
                    applyRadiusFilter(center: storm.coordinate, miles: miles)
                },
                onUseAsEvidence: currentReportId.map { rid in
                    {
                        applyEvidence(storm: storm, reportId: rid)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddressPicker) {
            AddressPickerSheet(service: mapsService) { picked in
                pickedAddress = picked
                let region = MKCoordinateRegion(
                    center: picked.coordinate,
                    span: .init(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
                lastRegion = region
                withAnimation(.easeInOut(duration: 0.4)) {
                    camera = .region(region)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isKnockMode)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showFloatingScript)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: radiusFilterMiles)
    }

    // MARK: - Map canvas

    @ViewBuilder
    private var mapCanvas: some View {
        #if canImport(GoogleMaps)
        if APIKeys.isLiveGoogleMaps {
            GoogleMapsCanvas(
                region: $lastRegion,
                stormPins: visibleStorms,
                leadPins: showLeads ? leadPins : [],
                jobPins: showJobs ? jobPins : [],
                knockHouses: showKnocks ? knockStore.houses : [],
                isKnockMode: isKnockMode,
                onSelectStorm: { selectedStorm = $0 },
                onSelectKnock: { editingHouse = $0 },
                onPlaceKnock: { coord in placeKnock(at: coord) }
            )
        } else {
            mapKitCanvas
        }
        #else
        mapKitCanvas
        #endif
    }

    private var mapKitCanvas: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if showStorms {
                    ForEach(visibleStorms) { sp in
                        Annotation(sp.headline, coordinate: sp.coordinate) {
                            Button { selectedStorm = sp } label: { stormGlyph(sp) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Storm: \(sp.headline)")
                        }
                    }
                }
                if showLeads {
                    ForEach(visibleLeadPins) { p in
                        Annotation(p.title, coordinate: p.coordinate) {
                            entityGlyph(p)
                        }
                    }
                }
                if showJobs {
                    ForEach(visibleJobPins) { p in
                        Annotation(p.title, coordinate: p.coordinate) {
                            entityGlyph(p)
                        }
                    }
                }
                ForEach(roofPolygons) { poly in
                    MapPolygon(coordinates: poly.coordinates)
                        .foregroundStyle(poly.color.opacity(0.45))
                        .stroke(poly.color, lineWidth: 2)
                }
                if showKnocks {
                    ForEach(knockStore.houses) { h in
                        if let lat = h.latitude, let lng = h.longitude {
                            Annotation(h.outcome.rawValue,
                                       coordinate: .init(latitude: lat, longitude: lng)) {
                                Button { editingHouse = h } label: { knockGlyph(h.outcome) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { ctx in
                lastRegion = ctx.region
            }
            .overlay {
                if isKnockMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            if let coord = proxy.convert(location, from: .local) {
                                placeKnock(at: coord)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Top bar

    private var standardTopBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { showAddressPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                        Text(pickedAddress?.title ?? "Search the field")
                            .font(.system(size: Theme.TypeRamp.metaSm))
                            .foregroundStyle(pickedAddress == nil ? Theme.inkFaint : Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        if pickedAddress != nil {
                            Button {
                                pickedAddress = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: Theme.TypeRamp.meta, weight: .bold))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(label: "Leads",  icon: "person.fill",   color: Theme.sky,   on: $showLeads)
                    chip(label: "Jobs",   icon: "hammer.fill",   color: Theme.ember, on: $showJobs)
                    chip(label: "Storms", icon: "bolt.fill",     color: Theme.crimson, on: $showStorms)
                    chip(label: "Knocks", icon: "hand.tap.fill", color: Theme.amber, on: $showKnocks)
                }
                .padding(.horizontal, 16)
            }

            if showStorms {
                stormDateScrubber
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showStorms)
    }

    private var stormDateScrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach([3, 6, 12, 24], id: \.self) { m in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        stormMonthsBack = m
                    } label: {
                        Text("\(m)m")
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                            .foregroundStyle(stormMonthsBack == m ? .white : Theme.ink)
                            .frame(minWidth: 64, minHeight: 56)
                            .padding(.horizontal, 14)
                            .background(
                                stormMonthsBack == m
                                    ? AnyShapeStyle(Theme.crimson)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: .capsule
                            )
                            .overlay(Capsule()
                                .stroke(stormMonthsBack == m ? .clear : Theme.hairline,
                                        lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // 64pt+ tap target chip per glove rules.
    private func chip(label: String, icon: String, color: Color, on: Binding<Bool>) -> some View {
        Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            withAnimation(.spring(duration: 0.25)) { on.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                Text(label)
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
            }
            .foregroundStyle(on.wrappedValue ? .white : Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(
                on.wrappedValue ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThinMaterial),
                in: .capsule
            )
            .overlay(Capsule().stroke(on.wrappedValue ? .clear : Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right column overlays

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mapsService.isLive ? Theme.mint : Theme.inkFaint)
                .frame(width: 8, height: 8)
            Text(APIKeys.modeLabel)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var zoomColumn: some View {
        VStack(spacing: 8) {
            zoomButton(symbol: "plus") { zoom(by: 0.5) }
            zoomButton(symbol: "minus") { zoom(by: 2.0) }
        }
    }

    private func zoomButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func zoom(by factor: Double) {
        var span = lastRegion.span
        span.latitudeDelta  = max(0.002, min(2.0, span.latitudeDelta  * factor))
        span.longitudeDelta = max(0.002, min(2.0, span.longitudeDelta * factor))
        let newRegion = MKCoordinateRegion(center: lastRegion.center, span: span)
        lastRegion = newRegion
        withAnimation(.easeInOut(duration: 0.25)) { camera = .region(newRegion) }
    }

    // MARK: - Radius filter chrome

    private func radiusFilterChrome(miles: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text("FILTERED · \(Int(miles)) mi RADIUS")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ember)
                Text("Showing leads & jobs near the storm")
                    .font(.system(size: Theme.TypeRamp.caption))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                radiusFilterMiles = nil
                radiusFilterCenter = nil
            } label: {
                Text("Clear")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.ember, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Theme.ember.opacity(0.3), lineWidth: 1))
    }

    private func applyRadiusFilter(center: CLLocationCoordinate2D, miles: Double) {
        radiusFilterCenter = center
        radiusFilterMiles = miles
        // Re-center map on storm
        let region = MKCoordinateRegion(
            center: center,
            span: .init(latitudeDelta: max(0.04, miles / 35), longitudeDelta: max(0.04, miles / 35))
        )
        lastRegion = region
        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
    }

    // Filtered visible storms. Radius filter doesn't hide storms themselves —
    // only Leads/Jobs are narrowed; the radius chrome still tells the story.
    private var visibleStorms: [StormPinEvent] {
        showStorms ? storms : []
    }

    // MARK: - Knock CTA card

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
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Door Knocking Mode")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(knockStore.houses.count)")
                            .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.ember, in: .capsule)
                    }
                    Text("Tap houses on the map to log outcomes. GPS-stamped, color-coded pins, with built-in script assistant.")
                        .font(.system(size: Theme.TypeRamp.captionSm))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .lineLimit(3)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                    .foregroundStyle(Theme.ember)
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
            .shadow(color: Theme.ink.opacity(0.10), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glyphs

    private func stormGlyph(_ sp: StormPinEvent) -> some View {
        ZStack {
            Circle().fill(.white)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle()
                .fill(sp.isHail ? Theme.sky : Theme.ember)
                .frame(width: 28, height: 28)
            Image(systemName: sp.isHail ? "cloud.hail.fill" : "wind")
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private func entityGlyph(_ p: MapEntityPin) -> some View {
        ZStack {
            Circle().fill(.white)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
            Circle().fill(p.color).frame(width: 22, height: 22)
            Image(systemName: p.icon)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private func knockGlyph(_ outcome: KnockOutcome) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Circle().fill(outcome.color).frame(width: 20, height: 20)
            Image(systemName: outcome.icon)
                .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Knock placement

    private func placeKnock(at coord: CLLocationCoordinate2D) {
        knockStore.lastLocation = coord
        let house = knockStore.add(coord: coord)
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
        editingHouse = house
    }

    // MARK: - Data

    private func loadStorms() async {
        // Use NOAA-backed storm events. Region is the current camera center,
        // padded so the user always sees a reasonable spread when zoomed in.
        let center = lastRegion.center
        let radius = max(50.0, Double(lastRegion.span.latitudeDelta) * 70.0)
        let fresh = (try? await stormService.events(
            near: center, radiusMi: radius, sinceMonthsBack: stormMonthsBack
        )) ?? []
        await MainActor.run {
            self.stormEvents = fresh
            self.storms = fresh.map { $0.asPin }
        }
    }

    private struct RoofPolygon: Identifiable, Hashable {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let color: Color

        static func == (lhs: RoofPolygon, rhs: RoofPolygon) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private func presentFocusedRoofIfNeeded() {
        guard let address = focusedAddress, !address.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            let coord = ((try? await geocoder.geocode(address)) ?? nil)
                ?? GeocodingServiceFactory.eagerCoord(forAddress: address)
            let region = MKCoordinateRegion(
                center: coord,
                span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )
            self.lastRegion = region
            withAnimation(.easeInOut(duration: 0.4)) { self.camera = .region(region) }
        }
    }

    /// Synthesised polygons — we don't have real roof footprint coords, so
    /// each slope renders as a small quad fanned out around the focused
    /// address, sized by squares and rotated by azimuth.
    private var roofPolygons: [RoofPolygon] {
        guard let address = focusedAddress,
              let roof = focusedRoof,
              !address.isEmpty else { return [] }
        let center = GeocodingServiceFactory.eagerCoord(forAddress: address)
        return roof.segments.enumerated().map { idx, seg in
            RoofPolygon(
                id: "roof-\(idx)-\(seg.id)",
                coordinates: Self.quad(around: center,
                                       azimuthDegrees: seg.azimuthDegrees,
                                       squares: seg.areaSquares),
                color: orientationColor(seg.orientation)
            )
        }
    }

    private func orientationColor(_ o: String) -> Color {
        switch o.uppercased().first {
        case "N": return Theme.sky
        case "E": return Theme.amber
        case "S": return Theme.crimson
        case "W": return Theme.mint
        default:  return Theme.ember
        }
    }

    /// Build a 4-coord quad anchored at `center`, fanned out by `azimuth`,
    /// with side length proportional to √(squares).
    private static func quad(around center: CLLocationCoordinate2D,
                             azimuthDegrees: Double,
                             squares: Double) -> [CLLocationCoordinate2D] {
        let baseSide = max(0.00006, sqrt(max(squares, 1.0)) * 0.00018) // deg-ish
        let rad = azimuthDegrees * .pi / 180.0
        let outOffset = baseSide * 1.1
        let cx = center.latitude  + cos(rad) * outOffset
        let cy = center.longitude + sin(rad) * outOffset
        let half = baseSide
        let perp = rad + .pi / 2
        let dxA = cos(rad) * half
        let dyA = sin(rad) * half
        let dxB = cos(perp) * half
        let dyB = sin(perp) * half
        return [
            .init(latitude: cx - dxA - dxB, longitude: cy - dyA - dyB),
            .init(latitude: cx + dxA - dxB, longitude: cy + dyA - dyB),
            .init(latitude: cx + dxA + dxB, longitude: cy + dyA + dyB),
            .init(latitude: cx - dxA + dxB, longitude: cy - dyA + dyB)
        ]
    }

    private func presentFocusedStormIfNeeded() {
        guard let pin = focusedStorm else { return }
        // Recenter and pop the detail sheet on the next runloop so the map is
        // mounted before we mutate camera state.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if let miles = initialRadiusFilterMiles {
                // Apply radius filter (also recenters camera) — this satisfies
                // "only impacted Leads/Jobs and the storm itself show".
                applyRadiusFilter(center: pin.coordinate, miles: miles)
            } else {
                let region = MKCoordinateRegion(
                    center: pin.coordinate,
                    span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
                self.lastRegion = region
                withAnimation(.easeInOut(duration: 0.4)) { self.camera = .region(region) }
            }
            if !self.storms.contains(where: { $0.id == pin.id }) {
                self.storms.append(pin)
            }
            self.selectedStorm = pin
        }
    }

    private func applyEvidence(storm: StormPinEvent, reportId: String) {
        // Convert the on-map StormPinEvent into the canonical StormEvent that
        // InspectionStore knows how to apply.
        let kind: StormEventType = storm.isHail ? .hail
            : (storm.windGustMph != nil ? .wind : .hail)
        let evt = NoaaStormEvent(
            id: storm.id.uuidString,
            eventDate: storm.date,
            eventType: kind,
            magnitudeIn: storm.hailSizeIn,
            windMph: storm.windGustMph,
            latitude: storm.latitude,
            longitude: storm.longitude,
            source: storm.source
        )
        _ = InspectionStore.shared.applyStormMatch(evt, to: reportId, overwrite: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedStorm = nil
    }

    // MARK: - Mock geo helpers

    private static let mockLeadPins: [MapEntityPin] = [
        .init(kind: .lead, title: "Adams Residence",   subtitle: "Plano, TX",
              latitude: 33.0421, longitude: -96.7012),
        .init(kind: .lead, title: "Brooks Residence",  subtitle: "Frisco, TX",
              latitude: 33.1602, longitude: -96.8101),
        .init(kind: .lead, title: "Carter Residence",  subtitle: "Allen, TX",
              latitude: 33.0985, longitude: -96.6612),
        .init(kind: .lead, title: "Diaz Residence",    subtitle: "McKinney, TX",
              latitude: 33.1865, longitude: -96.6504),
        .init(kind: .lead, title: "Evans Residence",   subtitle: "Plano, TX",
              latitude: 33.0712, longitude: -96.7388)
    ]

    private static let mockJobPins: [MapEntityPin] = [
        .init(kind: .job, title: "Coleman Residence",  subtitle: "Plano, TX",
              latitude: 33.0653, longitude: -96.7493),
        .init(kind: .job, title: "Smith Residence",    subtitle: "Frisco, TX",
              latitude: 33.1507, longitude: -96.8236),
        .init(kind: .job, title: "Hawthorn Estate",    subtitle: "McKinney, TX",
              latitude: 33.1972, longitude: -96.6398),
        .init(kind: .job, title: "Patel Custom Build", subtitle: "Frisco, TX",
              latitude: 33.1389, longitude: -96.7712)
    ]

    /// FNV-1a stable hash so a propertyAddress maps to the same DFW lat/lng
    /// across launches (Swift's `Hasher` randomizes its seed).
    private static func stableCoord(for s: String) -> CLLocationCoordinate2D {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let lat = 32.85 + Double(h % 400) / 1000.0          // 32.850 .. 33.250
        let lng = -96.92 + Double((h / 400) % 480) / 1000.0  // -96.920 .. -96.440
        return .init(latitude: lat, longitude: lng)
    }
}

// MARK: - Google Maps wrapper (active only when SDK is linked)

#if canImport(GoogleMaps)
private struct GoogleMapsCanvas: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let stormPins: [StormPinEvent]
    let leadPins: [MapEntityPin]
    let jobPins: [MapEntityPin]
    let knockHouses: [KnockedHouse]
    let isKnockMode: Bool
    let onSelectStorm: (StormPinEvent) -> Void
    let onSelectKnock: (KnockedHouse) -> Void
    let onPlaceKnock: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let opts = GMSMapViewOptions()
        opts.camera = GMSCameraPosition(latitude: region.center.latitude,
                                        longitude: region.center.longitude,
                                        zoom: 11)
        let mv = GMSMapView(options: opts)
        mv.delegate = context.coordinator
        mv.settings.compassButton = true
        mv.settings.zoomGestures = true
        context.coordinator.parent = self
        applyMarkers(to: mv, coord: context.coordinator)
        return mv
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        applyMarkers(to: uiView, coord: context.coordinator)
    }

    private func applyMarkers(to mv: GMSMapView, coord: Coordinator) {
        mv.clear()
        coord.stormByMarker.removeAll()
        coord.knockByMarker.removeAll()
        for sp in stormPins {
            let m = GMSMarker(position: sp.coordinate)
            m.title = sp.headline
            m.icon = GMSMarker.markerImage(with: sp.isHail ? .systemBlue : .systemOrange)
            m.map = mv
            coord.stormByMarker[ObjectIdentifier(m)] = sp
        }
        for p in leadPins {
            let m = GMSMarker(position: p.coordinate)
            m.title = p.title
            m.icon = GMSMarker.markerImage(with: UIColor(Theme.sky))
            m.map = mv
        }
        for p in jobPins {
            let m = GMSMarker(position: p.coordinate)
            m.title = p.title
            m.icon = GMSMarker.markerImage(with: UIColor(Theme.ember))
            m.map = mv
        }
        for h in knockHouses {
            guard let lat = h.latitude, let lng = h.longitude else { continue }
            let m = GMSMarker(position: .init(latitude: lat, longitude: lng))
            m.title = h.outcome.rawValue
            m.icon = GMSMarker.markerImage(with: UIColor(h.outcome.color))
            m.map = mv
            coord.knockByMarker[ObjectIdentifier(m)] = h
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapsCanvas
        var stormByMarker: [ObjectIdentifier: StormPinEvent] = [:]
        var knockByMarker: [ObjectIdentifier: KnockedHouse] = [:]

        init(parent: GoogleMapsCanvas) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            let id = ObjectIdentifier(marker)
            if let s = stormByMarker[id] { parent.onSelectStorm(s); return true }
            if let h = knockByMarker[id] { parent.onSelectKnock(h); return true }
            return false
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            guard parent.isKnockMode else { return }
            parent.onPlaceKnock(coordinate)
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            // Reflect google camera back into MK region so zoom buttons keep
            // working on the SwiftUI side if the user toggles modes.
            let visible = mapView.projection.visibleRegion()
            let north = visible.farLeft.latitude
            let south = visible.nearLeft.latitude
            let east  = visible.farRight.longitude
            let west  = visible.farLeft.longitude
            parent.region = MKCoordinateRegion(
                center: position.target,
                span: .init(latitudeDelta: max(0.002, abs(north - south)),
                            longitudeDelta: max(0.002, abs(east - west)))
            )
        }
    }
}
#endif

#Preview { MapHubView() }
