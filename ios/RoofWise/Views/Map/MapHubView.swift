import SwiftUI
import MapKit
import CoreLocation

#if canImport(GoogleMaps)
import GoogleMaps
#endif

// MARK: - Lightweight on-map pin payload (Google fallback path)

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
    /// When set, passed through to DoorKnockingModeView so the route is tagged
    /// with the originating StormAlert (Phase 6E).
    var focusedStormAlertId: String? = nil
    /// When set, the map recenters on this address on appear.
    var focusedAddress: String? = nil
    /// When set, draws each detected slope as a color-coded MKPolygon around
    /// the focused address (one quad per slope, sized by area, oriented by azimuth).
    var focusedRoof: RoofMeasurements? = nil

    /// Leads store (injected from RootView). Optional so previews don't trap.
    @Environment(CustomerStore.self) private var customerStore: CustomerStore?

    // Layer toggles (Step 9)
    @State private var showStorms = true
    @State private var showImpactRadius = true
    @State private var showServiceArea = true
    @State private var showFootprint = true
    @State private var showHeat = false
    @State private var showLayerPopover = false

    // Filters (Step 5)
    @State private var kindFilter: StormKindFilter = .both
    @State private var hailSizeMin: Double = 0.5     // applied
    @State private var windMphMin: Double = 40       // applied
    @State private var hailSizeMinRaw: Double = 0.5
    @State private var windMphMinRaw: Double = 40
    @State private var dateRange: StormDateRange = .last90
    @State private var showDateSheet = false
    @State private var filterDebounce: Task<Void, Never>? = nil

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
    @State private var eventByPinId: [UUID: NoaaStormEvent] = [:]
    @State private var radiusFilterMiles: Double? = nil
    @State private var radiusFilterCenter: CLLocationCoordinate2D? = nil

    // Sheets / selection
    @State private var selectedStorm: StormPinEvent?
    @State private var addToLeadStorm: StormPinEvent?
    @State private var showAddressPicker = false
    @State private var pickedAddress: AddressSuggestion?
    @State private var shareText: String?
    @State private var showShare = false

    // Knock state (preserved)
    @State private var knockStore = KnockStore()
    @State private var isKnockMode = false
    @State private var editingHouse: KnockedHouse?
    @State private var showFloatingScript = false
    @State private var floatingScriptOutcome: KnockOutcome = .interested
    @State private var showDoorKnockingMode = false
    @State private var plannedRoute: [StormRouteStop] = []

    // Stores / services
    @State private var serviceAreaStore = ServiceAreaStore.shared
    private let mapsService: MapsService = MapsServiceFactory.make()
    private let stormService: StormEventsServicing = StormEventsServiceFactory.shared
    private let geocoder: GeocodingService = GeocodingServiceFactory.shared

    // Live location state
    @State private var locationProvider = MapLocationProvider()
    @State private var didCenterOnUser = false

    // MARK: Derived data

    /// Storms passing the active type / magnitude / date filters.
    private var filteredStorms: [StormPinEvent] {
        guard showStorms else { return [] }
        return storms.filter { s in
            switch kindFilter {
            case .hail: if !s.isHail { return false }
            case .wind: if s.isHail { return false }
            case .both: break
            }
            if s.isHail {
                if (s.hailSizeIn ?? 0) < hailSizeMin { return false }
            } else {
                if Double(s.windGustMph ?? 0) < windMphMin { return false }
            }
            return dateRange.contains(s.date)
        }
    }

    private var isClusterZoom: Bool { lastRegion.span.latitudeDelta > 0.14 }

    private var stormClusters: [StormCluster] {
        StormClustering.clusters(filteredStorms, spanLatDelta: lastRegion.span.latitudeDelta)
    }

    private var heatCells: [HeatCell] { StormHeatGrid.cells(storms: filteredStorms) }
    private var heatMax: Int { heatCells.map(\.count).max() ?? 1 }

    /// Real footprint pins built from the user's own leads + jobs (deterministic
    /// placement by address — we don't store geocoded coords). Inspections not
    /// represented by a linked customer are added as scheduled-inspection pins.
    private var footprintPins: [FootprintPin] {
        var pins: [FootprintPin] = []
        var linkedReportIds = Set<String>()

        if let store = customerStore {
            for c in store.customers where !c.isUnassignedDraft {
                let addr = c.address.trimmingCharacters(in: .whitespaces)
                guard !addr.isEmpty, !addr.hasPrefix("Add property") else { continue }
                let coord = Self.stableCoord(for: addr)
                let kind: FootprintPin.Kind
                if c.stage.kind == .job {
                    kind = .signedJob
                } else if c.stage == .inspectionScheduled || c.stage == .inspectionComplete {
                    kind = .scheduledInspection
                } else {
                    kind = .lead
                }
                pins.append(FootprintPin(kind: kind, title: c.ownerName, subtitle: addr,
                                         latitude: coord.latitude, longitude: coord.longitude))
                if let rid = c.linkedReportId { linkedReportIds.insert(rid) }
            }
        }

        for insp in InspectionStore.shared.inspections {
            guard !linkedReportIds.contains(insp.job.reportId) else { continue }
            let addr = insp.job.propertyAddress.isEmpty ? insp.job.clientName : insp.job.propertyAddress
            guard !addr.isEmpty else { continue }
            let coord = Self.stableCoord(for: addr)
            pins.append(FootprintPin(kind: .scheduledInspection,
                                     title: insp.job.clientName.isEmpty ? "Job" : insp.job.clientName,
                                     subtitle: addr, latitude: coord.latitude, longitude: coord.longitude))
        }
        return pins
    }

    /// Footprint narrowed to the active radius filter (if any).
    private var visibleFootprintPins: [FootprintPin] {
        guard let center = radiusFilterCenter, let miles = radiusFilterMiles else {
            return footprintPins
        }
        return footprintPins.filter { $0.distanceMiles(from: center) <= miles }
    }

    // Google fallback path pins (kept intact; only used when the SDK is linked).
    private var leadPins: [MapEntityPin] { [] }
    private var jobPins: [MapEntityPin] {
        InspectionStore.shared.inspections.compactMap { insp -> MapEntityPin? in
            let addr = insp.job.propertyAddress.isEmpty ? insp.job.clientName : insp.job.propertyAddress
            guard !addr.isEmpty else { return nil }
            let c = Self.stableCoord(for: addr)
            return MapEntityPin(kind: .job,
                                title: insp.job.clientName.isEmpty ? "Job" : insp.job.clientName,
                                subtitle: addr, latitude: c.latitude, longitude: c.longitude)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapCanvas
                .ignoresSafeArea()

            if !isKnockMode {
                standardTopBar
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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

            // Right-edge status + FAB column (Step 9)
            if !isKnockMode {
                VStack(alignment: .trailing, spacing: 0) {
                    Spacer().frame(height: 250)
                    statusPill
                    Spacer()
                    fabColumn
                    Spacer().frame(height: 180)
                }
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(true)
            }
        }
        .task { await loadStorms() }
        .onAppear {
            presentFocusedStormIfNeeded()
            presentFocusedRoofIfNeeded()
            startLocationIfNeeded()
        }
        .onDisappear { locationProvider.stop() }
        .overlay {
            if locationProvider.isDeniedOrRestricted && focusedAddress == nil && focusedStorm == nil {
                locationPermissionOverlay
            }
        }
        .onChange(of: dateRange) { _, _ in
            Task { await loadStorms() }
        }
        .onChange(of: hailSizeMinRaw) { _, _ in scheduleFilterDebounce() }
        .onChange(of: windMphMinRaw) { _, _ in scheduleFilterDebounce() }
        .sheet(item: $editingHouse) { h in
            KnockOutcomeSheet(store: knockStore, houseID: h.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStorm) { storm in
            StormImpactDetailSheet(
                event: storm,
                noaaEventId: eventByPinId[storm.id]?.id,
                centerCoord: lastRegion.center,
                affectedAreas: affectedAreas(for: storm),
                leadsInRadius: leadsCount(in: storm),
                jobsInRadius: jobsCount(in: storm),
                currentReportId: currentReportId,
                onDoorKnock: { startDoorKnock(for: storm) },
                onAddToLeadList: { presentAddToLead(storm) },
                onShare: { shareStorm(storm) },
                onFindNearby: { miles in
                    selectedStorm = nil
                    applyRadiusFilter(center: storm.coordinate, miles: miles)
                },
                onUseAsEvidence: currentReportId.map { rid in
                    { applyEvidence(storm: storm, reportId: rid) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $addToLeadStorm) { storm in
            AddToLeadListSheet(
                service: mapsService,
                stormHeadline: storm.headline,
                onAdd: { addresses in handleAddLeads(addresses, storm: storm) }
            )
            .presentationDetents([.large])
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
                withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLayerPopover) {
            StormLayerPopover(
                showStorms: $showStorms,
                showImpactRadius: $showImpactRadius,
                showServiceArea: $showServiceArea,
                showFootprint: $showFootprint,
                showHeat: $showHeat
            )
            .presentationDetents([.height(460), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDateSheet) {
            StormDateRangeSheet(range: $dateRange)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShare) {
            if let text = shareText {
                ActivityShareView(items: [text])
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isKnockMode)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showFloatingScript)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: radiusFilterMiles)
        .fullScreenCover(isPresented: $showDoorKnockingMode) {
            DoorKnockingModeView(routeStormAlertId: focusedStormAlertId, plannedRoute: plannedRoute)
        }
    }

    // MARK: - Map canvas

    @ViewBuilder
    private var mapCanvas: some View {
        #if canImport(GoogleMaps)
        if APIKeys.isLiveGoogleMaps {
            GoogleMapsCanvas(
                region: $lastRegion,
                stormPins: filteredStorms,
                leadPins: showFootprint ? leadPins : [],
                jobPins: showFootprint ? jobPins : [],
                knockHouses: showFootprint ? knockStore.houses : [],
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
                UserAnnotation()
                heatOverlay
                serviceAreaOverlay
                impactOverlay
                roofOverlay
                footprintOverlay
                stormOverlay
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

    // MARK: - Map content builders (split to keep the type-checker fast)

    @MapContentBuilder private var heatOverlay: some MapContent {
        if showHeat {
            ForEach(heatCells) { cell in
                MapPolygon(coordinates: cell.coordinates)
                    .foregroundStyle(cell.fillColor(maxCount: heatMax))
            }
        }
    }

    @MapContentBuilder private var serviceAreaOverlay: some MapContent {
        if showServiceArea {
            ForEach(serviceAreaStore.areas) { area in
                if let lat = area.centerLat, let lng = area.centerLng {
                    MapPolygon(coordinates: ServiceAreaGeometry.boundingBox(
                        center: .init(latitude: lat, longitude: lng), radiusMiles: 5))
                        .foregroundStyle(Theme.ink.opacity(0.12))
                        .stroke(Theme.ink, lineWidth: 1.5)
                }
            }
        }
    }

    @MapContentBuilder private var impactOverlay: some MapContent {
        if showImpactRadius && !isClusterZoom {
            ForEach(filteredStorms) { s in
                MapCircle(center: s.coordinate, radius: s.impactRadiusMeters)
                    .foregroundStyle(Theme.ember.opacity(0.12))
                    .stroke(Theme.ember.opacity(0.35), lineWidth: 1)
            }
        }
    }

    @MapContentBuilder private var roofOverlay: some MapContent {
        ForEach(roofPolygons) { poly in
            MapPolygon(coordinates: poly.coordinates)
                .foregroundStyle(poly.color.opacity(0.45))
                .stroke(poly.color, lineWidth: 2)
        }
    }

    @MapContentBuilder private var footprintOverlay: some MapContent {
        if showFootprint {
            ForEach(visibleFootprintPins) { p in
                Annotation(p.title, coordinate: p.coordinate) {
                    FootprintPinView(kind: p.kind)
                }
            }
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

    @MapContentBuilder private var stormOverlay: some MapContent {
        if showStorms {
            ForEach(stormClusters) { cluster in
                Annotation(cluster.single?.headline ?? "\(cluster.count) storms",
                           coordinate: cluster.coordinate) {
                    stormClusterButton(cluster)
                }
            }
        }
    }

    @ViewBuilder
    private func stormClusterButton(_ cluster: StormCluster) -> some View {
        if let s = cluster.single {
            Button { selectedStorm = s } label: { StormPinView(event: s) }
                .buttonStyle(.plain)
                .accessibilityLabel("Storm: \(s.headline)")
        } else {
            Button { zoomToCluster(cluster) } label: {
                StormClusterView(count: cluster.count,
                                 color: cluster.worst?.severityColor ?? Theme.inkFaint)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Top bar

    private var standardTopBar: some View {
        VStack(spacing: 10) {
            searchRow
                .padding(.horizontal, 16)
            StormFilterBar(
                kindFilter: $kindFilter,
                hailSizeMin: $hailSizeMinRaw,
                windMphMin: $windMphMinRaw,
                dateRangeLabel: dateRange.label,
                onDatePill: { showDateSheet = true }
            )
            .padding(.horizontal, 16)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: kindFilter)
    }

    private var searchRow: some View {
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
                    Button { pickedAddress = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: Theme.TypeRamp.meta, weight: .bold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(minHeight: 56)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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

    private var fabColumn: some View {
        VStack(spacing: 10) {
            MapFAB(symbol: "square.3.layers.3d", tint: Theme.ink) { showLayerPopover = true }
            MapFAB(symbol: "location.fill", tint: Theme.sky) { recenterOnUser() }
            zoomButton(symbol: "plus") { zoom(by: 0.5) }
            zoomButton(symbol: "minus") { zoom(by: 2.0) }
        }
    }

    private func zoomButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func zoomToCluster(_ cluster: StormCluster) {
        let span = max(0.04, lastRegion.span.latitudeDelta / 3)
        let region = MKCoordinateRegion(center: cluster.coordinate,
                                        span: .init(latitudeDelta: span, longitudeDelta: span))
        lastRegion = region
        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
    }

    private func recenterOnUser() {
        let apply: (CLLocationCoordinate2D) -> Void = { coord in
            let region = MKCoordinateRegion(center: coord,
                                            span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05))
            lastRegion = region
            withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
        }
        if let coord = locationProvider.lastCoord {
            apply(coord)
        } else {
            locationProvider.start { coord in apply(coord) }
        }
    }

    // MARK: - Filter debounce (Step 5)

    private func scheduleFilterDebounce() {
        filterDebounce?.cancel()
        filterDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hailSizeMin = hailSizeMinRaw
            windMphMin = windMphMinRaw
        }
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
        let region = MKCoordinateRegion(
            center: center,
            span: .init(latitudeDelta: max(0.04, miles / 35), longitudeDelta: max(0.04, miles / 35))
        )
        lastRegion = region
        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
    }

    // MARK: - Affected areas + counts (Step 6)

    private func affectedAreas(for storm: StormPinEvent) -> [ServiceArea] {
        serviceAreaStore.areas.filter { area in
            guard let lat = area.centerLat, let lng = area.centerLng else { return false }
            let d = CLLocation(latitude: lat, longitude: lng)
                .distance(from: CLLocation(latitude: storm.latitude, longitude: storm.longitude)) / 1609.344
            return d <= storm.impactRadiusMiles + 3
        }
    }

    private func leadsCount(in storm: StormPinEvent) -> Int {
        footprintPins.filter {
            $0.kind == .lead && $0.distanceMiles(from: storm.coordinate) <= storm.impactRadiusMiles
        }.count
    }

    private func jobsCount(in storm: StormPinEvent) -> Int {
        footprintPins.filter {
            $0.kind != .lead && $0.distanceMiles(from: storm.coordinate) <= storm.impactRadiusMiles
        }.count
    }

    // MARK: - Door-knock route (Step 7)

    private func startDoorKnock(for storm: StormPinEvent) {
        let visited: [CLLocationCoordinate2D] = knockStore.houses.compactMap { h in
            guard let lat = h.latitude, let lng = h.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        plannedRoute = StormRouteBuilder.build(
            storm: storm,
            userLocation: locationProvider.lastCoord,
            leads: footprintPins,
            visited: visited,
            serviceAreas: serviceAreaStore.areas
        )
        selectedStorm = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showDoorKnockingMode = true
        }
    }

    // MARK: - Add to Lead List (Step 6)

    private func presentAddToLead(_ storm: StormPinEvent) {
        selectedStorm = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            addToLeadStorm = storm
        }
    }

    private func handleAddLeads(_ addresses: [AddressSuggestion], storm: StormPinEvent?) {
        guard let store = customerStore else { return }
        for s in addresses {
            let addr = s.fullAddress.trimmingCharacters(in: .whitespaces)
            guard !addr.isEmpty else { continue }
            var c = Customer(ownerName: "New Lead", address: addr,
                             stage: .knocked, stormTagged: storm != nil)
            c.dateOfLoss = storm?.date
            store.add(c, makeActive: false)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Share storm report (Step 6)

    private func shareStorm(_ storm: StormPinEvent) {
        shareText = shareString(for: storm)
        selectedStorm = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showShare = true }
    }

    private func shareString(for storm: StormPinEvent) -> String {
        let date = storm.date.formatted(date: .abbreviated, time: .omitted)
        let link: String
        if let noaa = eventByPinId[storm.id] {
            link = "https://www.ncdc.noaa.gov/stormevents/eventdetails.jsp?id=\(noaa.id)"
        } else {
            link = "https://www.spc.noaa.gov/climo/reports/"
        }
        return "RoofWise storm report — \(storm.magnitudeText) on \(date). NOAA details: \(link)"
    }

    // Filtered visible storms helper kept for the Google fallback path.
    private var visibleStorms: [StormPinEvent] { filteredStorms }

    // MARK: - Knock CTA card

    private var startKnockingCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            plannedRoute = []
            showDoorKnockingMode = true
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
            .frame(minHeight: 88)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
            .shadow(color: Theme.ink.opacity(0.10), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glyphs

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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        editingHouse = house
    }

    // MARK: - Data

    private func loadStorms() async {
        let center = lastRegion.center
        let radius = max(50.0, Double(lastRegion.span.latitudeDelta) * 70.0)
        let fresh = (try? await stormService.events(
            near: center, radiusMi: radius, sinceMonthsBack: dateRange.monthsBack
        )) ?? []
        await MainActor.run {
            self.stormEvents = fresh
            let pairs = fresh.map { ($0, $0.asPin) }
            self.storms = pairs.map { $0.1 }
            self.eventByPinId = Dictionary(pairs.map { ($0.1.id, $0.0) }, uniquingKeysWith: { a, _ in a })
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
    /// each slope renders as a small quad fanned out around the focused address.
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

    private static func quad(around center: CLLocationCoordinate2D,
                             azimuthDegrees: Double,
                             squares: Double) -> [CLLocationCoordinate2D] {
        let baseSide = max(0.00006, sqrt(max(squares, 1.0)) * 0.00018)
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

    private func startLocationIfNeeded() {
        guard focusedAddress == nil, focusedStorm == nil else { return }
        locationProvider.start { coord in
            if !didCenterOnUser {
                didCenterOnUser = true
                let region = MKCoordinateRegion(
                    center: coord,
                    span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
                lastRegion = region
                withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
            }
        }
    }

    private var locationPermissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.ember)
            Text("Location permission required")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Enable Location Services so the map can center on your live position and log accurate knocks.")
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(minWidth: 220, minHeight: 64)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
    }

    private func presentFocusedStormIfNeeded() {
        guard let pin = focusedStorm else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if let miles = initialRadiusFilterMiles {
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

    // MARK: - Address → coord helper

    /// FNV-1a stable hash so a propertyAddress maps to the same DFW lat/lng
    /// across launches (Swift's `Hasher` randomizes its seed).
    private static func stableCoord(for s: String) -> CLLocationCoordinate2D {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let lat = 32.85 + Double(h % 400) / 1000.0
        let lng = -96.92 + Double((h / 400) % 480) / 1000.0
        return .init(latitude: lat, longitude: lng)
    }
}

// MARK: - System share sheet wrapper

private struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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

// MARK: - File-private CLLocation provider

@MainActor
@Observable
final class MapLocationProvider: NSObject, CLLocationManagerDelegate {
    var lastCoord: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func start(onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onUpdate = onUpdate
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        onUpdate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.lastCoord = coord
            self.onUpdate?(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Non-fatal — caller renders denied-state UI from authorizationStatus.
    }
}

#Preview { MapHubView() }
