import SwiftUI
import MapKit
import CoreLocation

/// Full-screen detail for a single logged mileage trip. Shows the recorded
/// route, key stats, classification, locations, linked job, and notes — with
/// inline editing and deletion. Reads live from `MileageStore` so any edit is
/// reflected immediately without re-presenting.
struct TripDetailView: View {
    let tripID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var store = MileageStore.shared
    @State private var showEdit: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var trip: MileageTrip? {
        store.trips.first { $0.id == tripID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if let trip {
                    ScrollView {
                        VStack(spacing: 16) {
                            routeMap(trip)
                            heroCard(trip)
                            purposeRow(trip)
                            routeCard(trip)
                            metaCard(trip)
                            if let notes = trip.notes, !notes.isEmpty {
                                notesCard(notes)
                            }
                            deleteButton
                            Color.clear.frame(height: 8)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    missingState
                }
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if trip != nil {
                        Button {
                            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                            showEdit = true
                        } label: {
                            Text("Edit")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.ember)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let trip {
                    ManualTripSheet(existing: trip) { updated in
                        store.update(updated)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .confirmationDialog("Delete this trip?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete Trip", role: .destructive) {
                    if let trip { store.delete(trip) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the trip and its logged mileage.")
            }
        }
    }

    // MARK: route map

    @ViewBuilder
    private func routeMap(_ trip: MileageTrip) -> some View {
        let coords = trip.path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        ZStack(alignment: .topLeading) {
            if coords.count >= 2 {
                Map(initialPosition: .region(region(for: coords))) {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.ember, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let first = coords.first {
                        Annotation("Start", coordinate: first) {
                            endpointDot(color: Theme.mint, system: "flag.fill")
                        }
                    }
                    if let last = coords.last {
                        Annotation("End", coordinate: last) {
                            endpointDot(color: Theme.crimson, system: "flag.checkered")
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))

                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 9, weight: .heavy))
                    Text("RECORDED ROUTE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.ink.opacity(0.78), in: .capsule)
                .padding(10)
            } else {
                noRouteCard(trip)
            }
        }
    }

    private func endpointDot(color: Color, system: String) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.22)).frame(width: 30, height: 30)
            Circle().fill(color).frame(width: 18, height: 18)
                .overlay(Image(systemName: system)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white))
        }
    }

    private func noRouteCard(_ trip: MileageTrip) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(trip.purpose.tint.opacity(0.15))
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(trip.purpose.tint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("No GPS route")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("This trip was logged manually, so there's no recorded map path.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: hero stats

    private func heroCard(_ trip: MileageTrip) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(String(format: "%.1f", trip.miles))
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text("MILES DRIVEN")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkFaint)
            }

            HStack(spacing: 10) {
                statChip(label: "Duration",
                         value: trip.durationString,
                         icon: "clock.fill",
                         tint: Theme.sky)
                statChip(label: trip.purpose.isDeductible ? "Reimbursable" : "Personal",
                         value: trip.purpose.isDeductible
                            ? currency(trip.reimbursement(rate: store.ratePerMile))
                            : "—",
                         icon: "dollarsign.circle.fill",
                         tint: trip.purpose.isDeductible ? Theme.mint : Theme.inkFaint)
                statChip(label: "Avg Speed",
                         value: avgSpeedString(trip),
                         icon: "speedometer",
                         tint: Theme.ember)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.card)
                LinearGradient(colors: [trip.purpose.tint.opacity(0.10), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(.rect(cornerRadius: 22))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.05), radius: 14, y: 6)
    }

    private func statChip(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
    }

    // MARK: purpose

    private func purposeRow(_ trip: MileageTrip) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(trip.purpose.tint.opacity(0.15))
                Image(systemName: trip.purpose.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(trip.purpose.tint)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trip Type")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkFaint)
                Text(trip.purpose.rawValue)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Text(trip.purpose.isDeductible ? "Deductible" : "Personal")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background((trip.purpose.isDeductible ? Theme.mint : Theme.inkFaint).opacity(0.16),
                            in: .capsule)
                .foregroundStyle(trip.purpose.isDeductible ? Theme.mint : Theme.inkSoft)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: route from/to

    private func routeCard(_ trip: MileageTrip) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Route", icon: "arrow.triangle.swap")
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Circle().fill(Theme.mint).frame(width: 11, height: 11)
                    Rectangle().fill(Theme.hairline).frame(width: 2, height: 34)
                    Circle().fill(Theme.crimson).frame(width: 11, height: 11)
                }
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    endpoint(title: "FROM", value: trip.startLabel, time: timeString(trip.startedAt))
                    Spacer().frame(height: 18)
                    endpoint(title: "TO", value: trip.endLabel, time: timeString(trip.endedAt))
                }
                Spacer()
            }
            .padding(14)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func endpoint(title: String, value: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Theme.inkFaint)
                Text(time)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: meta (date + job)

    private func metaCard(_ trip: MileageTrip) -> some View {
        VStack(spacing: 0) {
            infoRow(icon: "calendar", tint: Theme.sky,
                    label: "Date", value: fullDateString(trip.startedAt))
            Divider().overlay(Theme.hairline).padding(.leading, 50)
            infoRow(icon: "clock.arrow.circlepath", tint: Theme.amber,
                    label: "Time", value: "\(timeString(trip.startedAt)) – \(timeString(trip.endedAt))")
            if let job = trip.jobName, !job.isEmpty {
                Divider().overlay(Theme.hairline).padding(.leading, 50)
                infoRow(icon: "briefcase.fill", tint: Theme.ember,
                        label: "Linked Job", value: job)
            }
        }
        .padding(.vertical, 4)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func infoRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: notes

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader("Notes", icon: "note.text")
            Text(notes)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: delete

    private var deleteButton: some View {
        Button {
            let g = UIImpactFeedbackGenerator(style: .rigid); g.impactOccurred()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("Delete Trip")
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(Theme.crimson)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.crimson.opacity(0.10), in: .capsule)
            .overlay(Capsule().stroke(Theme.crimson.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var missingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.side.air.fresh")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text("Trip not found")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("This trip may have been deleted.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(40)
    }

    // MARK: helpers

    private func cardHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 14)
    }

    private func avgSpeedString(_ trip: MileageTrip) -> String {
        let hours = trip.durationSeconds / 3600
        guard hours > 0.001 else { return "—" }
        let mph = trip.miles / hours
        return String(format: "%.0f mph", mph)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func fullDateString(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            return "Today"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: date)
    }
}
