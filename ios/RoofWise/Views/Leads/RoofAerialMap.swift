import SwiftUI
import MapKit
import CoreLocation

/// Interactive aerial map of a property roof for the Cost Estimator.
///
/// Shows the property centered in the frame with a translucent colored polygon
/// laid over the roof footprint (sized from the measured area). The rep can pan
/// and zoom, and toggle between a photographic **Satellite** view and a labeled
/// **Map** view.
struct RoofAerialMap: View {
    let coord: CLLocationCoordinate2D
    /// Measured roof area (drives the size of the overlay footprint).
    let areaSqFt: Double
    let address: String

    @State private var satellite: Bool = true
    @State private var camera: MapCameraPosition
    @State private var showOverlay: Bool = true

    init(coord: CLLocationCoordinate2D, areaSqFt: Double, address: String) {
        self.coord = coord
        self.areaSqFt = areaSqFt
        self.address = address
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coord,
                               latitudinalMeters: 90,
                               longitudinalMeters: 90)
        ))
    }

    /// Square footprint corners derived from the roof area (footprint ≈ 88% of
    /// the sloped roof area), centered on the property.
    private var footprint: [CLLocationCoordinate2D] {
        let footprintM2 = max(40.0, (areaSqFt / 10.7639) * 0.88)
        let side = sqrt(footprintM2)                  // meters per side
        let half = side / 2.0
        let dLat = half / 111_320.0
        let dLon = half / (111_320.0 * cos(coord.latitude * .pi / 180.0))
        return [
            .init(latitude: coord.latitude + dLat, longitude: coord.longitude - dLon),
            .init(latitude: coord.latitude + dLat, longitude: coord.longitude + dLon),
            .init(latitude: coord.latitude - dLat, longitude: coord.longitude + dLon),
            .init(latitude: coord.latitude - dLat, longitude: coord.longitude - dLon)
        ]
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
            if showOverlay {
                MapPolygon(coordinates: footprint)
                    .foregroundStyle(Theme.ember.opacity(0.32))
                    .stroke(Theme.ember, lineWidth: 2.5)
            }
            Annotation("", coordinate: coord) {
                ZStack {
                    Circle().fill(.white).frame(width: 14, height: 14)
                    Circle().fill(Theme.ember).frame(width: 8, height: 8)
                }
                .shadow(color: .black.opacity(0.4), radius: 2)
            }
        }
        .mapStyle(satellite
                  ? .hybrid(elevation: .flat)
                  : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(alignment: .topTrailing) { mapToggle }
        .overlay(alignment: .topLeading) { overlayToggle }
        .overlay(alignment: .bottomLeading) {
            Text(address)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.55), in: .capsule)
                .padding(10)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Controls

    private var mapToggle: some View {
        HStack(spacing: 0) {
            toggleButton(label: "Satellite", symbol: "globe.americas.fill", active: satellite) {
                satellite = true
            }
            toggleButton(label: "Map", symbol: "map.fill", active: !satellite) {
                satellite = false
            }
        }
        .padding(3)
        .background(.black.opacity(0.55), in: .capsule)
        .padding(10)
    }

    private func toggleButton(label: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(active ? Theme.ink : .white)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(active ? Color.white : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var overlayToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showOverlay ? "square.dashed.inset.filled" : "square.dashed")
                    .font(.system(size: 10, weight: .heavy))
                Text(showOverlay ? "Roof" : "Roof")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(showOverlay ? .white : .white.opacity(0.7))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(showOverlay ? Theme.ember.opacity(0.9) : .black.opacity(0.55), in: .capsule)
            .padding(10)
        }
        .buttonStyle(.plain)
    }
}
