import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Full-screen door-knocking workspace. Owns its own MapKit canvas, location
/// manager, and presents `LogKnockSheet` and `EndRouteSummarySheet`. Glove-
/// friendly: tap targets ≥56pt, body text ≥15pt, primary CTA 64pt.
struct DoorKnockingModeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional storm-alert id when the route was launched from the storm
    /// hero CTA or push notification path.
    var routeStormAlertId: String? = nil

    /// Optional pre-built canvassing route (Step 7). When non-empty, the route
    /// renders as a connecting polyline with numbered stops. Purely additive —
    /// existing callers that omit it are byte-identical in behaviour.
    var plannedRoute: [StormRouteStop] = []

    @State private var sessionId: UUID? = nil
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 33.05, longitude: -96.75),
                           span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02))
    )
    @State private var lastRegion = MKCoordinateRegion(
        center: .init(latitude: 33.05, longitude: -96.75),
        span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var currentCoord: CLLocationCoordinate2D? = nil
    @State private var authStatus: CLAuthorizationStatus = .notDetermined
    @State private var showLogSheet = false
    @State private var showEndConfirm = false
    @State private var showSummary = false
    @State private var elapsedTick: Date = .now

    private let store = KnockSessionStore.shared
    private let locationProvider = KnockLocationProvider()
    private let elapsedTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var session: KnockSession? {
        guard let id = sessionId else { return nil }
        return store.session(with: id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapCanvas
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                statTiles
                    .padding(.horizontal, 16)
            }

            VStack {
                Spacer()
                bottomBar
            }

            if authStatus == .denied || authStatus == .restricted {
                locationPermissionOverlay
            }
        }
        .onAppear {
            if sessionId == nil {
                sessionId = store.startSession(stormAlertId: routeStormAlertId).id
            }
            locationProvider.start(
                onUpdate: { coord in
                    currentCoord = coord
                    let region = MKCoordinateRegion(
                        center: coord,
                        span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    lastRegion = region
                    withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
                },
                onAuth: { status in authStatus = status }
            )
        }
        .onDisappear { locationProvider.stop() }
        .onReceive(elapsedTimer) { now in elapsedTick = now }
        .sheet(isPresented: $showLogSheet) {
            if let coord = currentCoord ?? lastRegion.center.asValid,
               let sid = sessionId {
                LogKnockSheet(coord: coord, sessionId: sid) { _ in
                    // Knock saved — refresh camera to show new pin.
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("End route?",
                            isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("End Route", role: .destructive) {
                if let sid = sessionId {
                    store.endSession(id: sid)
                }
                showSummary = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wrap this route and see your summary.")
        }
        .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
            if let sid = sessionId {
                EndRouteSummarySheet(sessionId: sid) {
                    // Done CTA dismisses parent on next runloop.
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Map

    private var mapCanvas: some View {
        Map(position: $camera) {
            UserAnnotation()
            if !plannedRoute.isEmpty {
                MapPolyline(coordinates: plannedRoute.map(\.coordinate))
                    .stroke(Theme.ember, lineWidth: 4)
                ForEach(plannedRoute) { stop in
                    Annotation(stop.title, coordinate: stop.coordinate) {
                        RouteStopPinView(order: stop.order)
                    }
                }
            }
            ForEach(allKnocks) { k in
                Annotation(k.outcome.label,
                           coordinate: .init(latitude: k.lat, longitude: k.lng)) {
                    knockGlyph(k.outcome)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { ctx in
            lastRegion = ctx.region
        }
    }

    private func knockGlyph(_ o: KnockSessionOutcome) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Circle().fill(color(for: o)).frame(width: 24, height: 24)
            Image(systemName: o.icon)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private func color(for o: KnockSessionOutcome) -> Color {
        switch o {
        case .interested: return Theme.mint
        case .inspection_scheduled: return Theme.ink
        case .not_home: return Theme.inkFaint
        case .not_interested: return Theme.ember
        case .follow_up: return Theme.amber
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                showEndConfirm = true
            } label: {
                Text("Wrap Route")
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .background(Theme.ember, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(value: "\(allKnocks.count)",
                     valueSize: Theme.TypeRamp.display,
                     label: "Knocks")
            statTile(value: interestedPct,
                     valueSize: Theme.TypeRamp.body,
                     label: "Interested")
            statTile(value: elapsedLabel,
                     valueSize: Theme.TypeRamp.subhead,
                     label: "Elapsed")
        }
    }

    private func statTile(value: String, valueSize: CGFloat, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: valueSize, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 56)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: - Bottom CTA

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                showLogSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    Text("Log Knock at My Location")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(currentCoord == nil && !lastRegion.center.isValidCoord)
            .opacity((currentCoord == nil && !lastRegion.center.isValidCoord) ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(minHeight: 88)
        .background(.ultraThinMaterial)
    }

    // MARK: - Derived

    private var allKnocks: [Knock] {
        session?.knocks ?? []
    }

    private var interestedPct: String {
        let total = allKnocks.count
        guard total > 0 else { return "0%" }
        let interested = allKnocks.filter {
            $0.outcome == .interested || $0.outcome == .inspection_scheduled
        }.count
        return "\(Int((Double(interested) / Double(total)) * 100))%"
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
            Text("Door-knock pins are GPS-stamped. Enable Location Services to log knocks at your real position.")
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
        .frame(maxWidth: 420)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var elapsedLabel: String {
        _ = elapsedTick
        guard let s = session else { return "—" }
        let interval = Date().timeIntervalSince(s.started_at)
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Lightweight CLLocation provider

@MainActor
private final class KnockLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onUpdate: ((CLLocationCoordinate2D) -> Void)?
    private var onAuth: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start(onUpdate: @escaping (CLLocationCoordinate2D) -> Void,
               onAuth: ((CLAuthorizationStatus) -> Void)? = nil) {
        self.onUpdate = onUpdate
        self.onAuth = onAuth
        let status = manager.authorizationStatus
        onAuth?(status)
        switch status {
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
            self.onAuth?(status)
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in self.onUpdate?(coord) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Silent — non-critical.
    }
}

private extension CLLocationCoordinate2D {
    var isValidCoord: Bool {
        latitude != 0 || longitude != 0
    }
    var asValid: CLLocationCoordinate2D? {
        isValidCoord ? self : nil
    }
}

#Preview {
    DoorKnockingModeView()
}
