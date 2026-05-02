import SwiftUI
import MapKit
import CoreLocation

struct MileageTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MileageStore.shared
    @State private var tracker = MileageTrackerService()
    @State private var showStopSheet: Bool = false
    @State private var showRangePicker: Bool = false
    @State private var range: MileageRange = .week
    @State private var showRateSheet: Bool = false
    @State private var editingTrip: MileageTrip?
    @State private var showAddManual: Bool = false
    @State private var showSettings: Bool = false
    @State private var autoTrack = MileageAutoTrackService.shared
    @State private var inbox = AutoTripInbox.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        liveCard
                        statsHeader
                        rangeFilter
                        tripsSection
                        Color.clear.frame(height: 130)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }
                .scrollIndicators(.hidden)

                bottomBar
            }
            .navigationTitle("Mileage Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddManual = true
                        } label: {
                            Label("Add Manual Trip", systemImage: "plus.circle")
                        }
                        Button {
                            showRateSheet = true
                        } label: {
                            Label("Set Mileage Rate", systemImage: "dollarsign.circle")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Auto-Tracking Settings", systemImage: "sensor.tag.radiowaves.forward.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .sheet(isPresented: $showStopSheet) {
                if let pending = pendingTrip {
                    StopTripSheet(draft: pending) { completed in
                        store.add(completed)
                        pendingTrip = nil
                        showStopSheet = false
                    } onDiscard: {
                        pendingTrip = nil
                        showStopSheet = false
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showRateSheet) {
                MileageRateSheet(rate: store.ratePerMile) { newRate in
                    store.setRate(newRate)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAddManual) {
                ManualTripSheet { trip in
                    store.add(trip)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                MileageAutoTrackSettingsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: Binding(get: { inbox.presented }, set: { inbox.presented = $0 })) { trip in
                AutoDetectedTripSheet(trip: trip) { saved in
                    store.add(saved)
                    inbox.remove(id: trip.id)
                    inbox.presented = nil
                } onDiscard: {
                    inbox.remove(id: trip.id)
                    inbox.presented = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingTrip) { trip in
                ManualTripSheet(existing: trip) { updated in
                    store.update(updated)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: live state

    @State private var pendingTrip: PendingTrip?

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: tracker.isTracking
                                             ? [Theme.ember, Theme.emberDeep]
                                             : [Theme.ink, Theme.inkSoft],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: tracker.isTracking ? "location.fill" : "car.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                    if tracker.isTracking, !tracker.isPaused {
                        Circle()
                            .stroke(Theme.ember.opacity(0.4), lineWidth: 2)
                            .scaleEffect(pulseScale)
                            .opacity(2 - pulseScale)
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.isTracking
                         ? (tracker.isPaused ? "Trip Paused" : "Tracking Trip")
                         : "Ready to Track")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(tracker.isTracking
                         ? "GPS · \(String(format: "%.1f", tracker.currentSpeedMph)) mph"
                         : "Tap Start to log your next drive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer()

                if tracker.isTracking {
                    statusPill(text: tracker.isPaused ? "PAUSED" : "LIVE",
                               color: tracker.isPaused ? Theme.amber : Theme.mint)
                }
            }

            HStack(spacing: 10) {
                liveStat(label: "Miles",
                         value: String(format: "%.2f", tracker.currentMiles),
                         tint: Theme.ember)
                liveStat(label: "Time",
                         value: formatDuration(tracker.elapsedSeconds),
                         tint: Theme.sky)
                liveStat(label: "Est. Pay",
                         value: currency(tracker.currentMiles * store.ratePerMile),
                         tint: Theme.mint)
            }

            if tracker.isTracking {
                liveRouteMap
            }

            if tracker.authState == .denied {
                Label(tracker.lastError ?? "Location access required",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.crimson)
            } else if tracker.isTracking {
                Text("Drive normally — RoofWise records distance, route, and reimbursable miles.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
            } else {
                Text("Auto-classifies trips as Inspection, Estimate, Job Site, Supply Run, or Personal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.card)
                if tracker.isTracking {
                    LinearGradient(colors: [Theme.ember.opacity(0.08), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(.rect(cornerRadius: 22))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(tracker.isTracking ? Theme.ember.opacity(0.45) : Theme.hairline,
                        lineWidth: tracker.isTracking ? 1.0 : 0.6)
        )
        .shadow(color: Theme.ink.opacity(0.05), radius: 14, y: 6)
        .onAppear {
            startPulse()
        }
    }

    @State private var pulseScale: CGFloat = 1.0

    // MARK: live route map snippet

    private var liveRouteCoordinates: [CLLocationCoordinate2D] {
        tracker.path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    private var liveRouteRegion: MKCoordinateRegion {
        let coords = liveRouteCoordinates
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        if coords.count == 1 {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min() ?? first.latitude
        let maxLat = lats.max() ?? first.latitude
        let minLon = lons.min() ?? first.longitude
        let maxLon = lons.max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * 1.6, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    @ViewBuilder
    private var liveRouteMap: some View {
        let coords = liveRouteCoordinates
        ZStack(alignment: .topLeading) {
            Map(initialPosition: .region(liveRouteRegion)) {
                if coords.count >= 2 {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.ember, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let last = coords.last {
                    Annotation("You", coordinate: last) {
                        ZStack {
                            Circle().fill(Theme.ember.opacity(0.25)).frame(width: 26, height: 26)
                            Circle().fill(Theme.ember).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .frame(height: 130)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))

            HStack(spacing: 4) {
                Circle().fill(Theme.ember).frame(width: 6, height: 6)
                Text("LIVE ROUTE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.ink.opacity(0.78), in: .capsule)
            .padding(8)

            if coords.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                    Text("Acquiring GPS…")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas.opacity(0.85))
                .clipShape(.rect(cornerRadius: 14))
            }
        }
    }

    private func startPulse() {
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulseScale = 1.7
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12), in: .capsule)
    }

    private func liveStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
    }

    // MARK: stats header

    private var rangedTrips: [MileageTrip] {
        switch range {
        case .week: return store.weekToDate
        case .month: return store.monthToDate
        case .year: return store.yearToDate
        case .all: return store.trips
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 12) {
            statTile(label: "Total Miles",
                     value: String(format: "%.1f", store.totalMiles(rangedTrips)),
                     icon: "speedometer",
                     tint: Theme.ember)
            statTile(label: "Reimbursable",
                     value: currency(store.totalReimbursement(rangedTrips)),
                     icon: "dollarsign.circle.fill",
                     tint: Theme.mint)
            statTile(label: "Trips",
                     value: "\(rangedTrips.count)",
                     icon: "map.fill",
                     tint: Theme.sky)
        }
    }

    private func statTile(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkFaint)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var rangeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MileageRange.allCases) { r in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { range = r }
                    } label: {
                        Text(r.label)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(range == r ? .white : Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background {
                                if range == r {
                                    Capsule().fill(Theme.ink)
                                } else {
                                    Capsule().fill(Theme.card)
                                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var tripsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Trips")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(rangedTrips.count) total")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }

            if rangedTrips.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(rangedTrips) { trip in
                        TripRow(trip: trip, rate: store.ratePerMile)
                            .onTapGesture { editingTrip = trip }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.delete(trip)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.side.air.fresh")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text("No trips yet")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Hit Start Trip and we'll log every mile.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        VStack {
            HStack(spacing: 10) {
                if tracker.isTracking {
                    Button {
                        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                        if tracker.isPaused { tracker.resume() } else { tracker.pause() }
                    } label: {
                        Image(systemName: tracker.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 60, height: 60)
                            .background(Theme.card, in: .circle)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
                        if let res = tracker.stop() {
                            pendingTrip = PendingTrip(miles: res.miles,
                                                      startedAt: res.startedAt,
                                                      endedAt: res.endedAt,
                                                      path: res.path)
                            showStopSheet = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .heavy))
                            Text("End Trip")
                                .font(.system(size: 16, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [Theme.crimson, Theme.crimson.opacity(0.85)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: .capsule
                        )
                        .shadow(color: Theme.crimson.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                        tracker.start()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .heavy))
                            Text("Start Trip")
                                .font(.system(size: 16, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                           startPoint: .leading, endPoint: .trailing),
                            in: .capsule
                        )
                        .shadow(color: Theme.ember.opacity(0.45), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .background(
            LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Range filter

enum MileageRange: String, CaseIterable, Identifiable {
    case week, month, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "Year to Date"
        case .all: return "All Time"
        }
    }
}

// MARK: - Trip Row

private struct TripRow: View {
    let trip: MileageTrip
    let rate: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(trip.purpose.tint.opacity(0.15))
                Image(systemName: trip.purpose.icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(trip.purpose.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trip.purpose.rawValue)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    if !trip.purpose.isDeductible {
                        Text("Personal")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.inkFaint.opacity(0.18), in: .capsule)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                if let job = trip.jobName, !job.isEmpty {
                    Text(job)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(trip.startLabel)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .heavy))
                    Text(trip.endLabel)
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f mi", trip.miles))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if trip.purpose.isDeductible {
                    Text(currency(trip.miles * rate))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.mint)
                        .monospacedDigit()
                }
                Text(dateString(trip.startedAt))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
        .contentShape(.rect)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func dateString(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "'Today' h:mma"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "'Yesterday' h:mma"
        } else {
            f.dateFormat = "MMM d · h:mma"
        }
        return f.string(from: date).lowercased()
    }
}

// MARK: - Pending Trip + Stop Sheet

struct PendingTrip: Identifiable {
    let id = UUID()
    let miles: Double
    let startedAt: Date
    let endedAt: Date
    let path: [MileageTripPoint]
}

private struct StopTripSheet: View {
    let draft: PendingTrip
    var onSave: (MileageTrip) -> Void
    var onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var purpose: TripPurpose = .inspection
    @State private var startLabel: String = ""
    @State private var endLabel: String = ""
    @State private var jobName: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        bigStat(label: "Miles", value: String(format: "%.2f", draft.miles), tint: Theme.ember)
                        bigStat(label: "Time", value: durationString, tint: Theme.sky)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }

                Section("Purpose") {
                    Picker("Trip purpose", selection: $purpose) {
                        ForEach(TripPurpose.allCases) { p in
                            Label(p.rawValue, systemImage: p.icon).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Locations") {
                    TextField("From (e.g. Office)", text: $startLabel)
                    TextField("To (e.g. Job Site)", text: $endLabel)
                }

                Section("Details") {
                    TextField("Linked job (optional)", text: $jobName)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Save Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                    .foregroundStyle(Theme.crimson)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trip = MileageTrip(startedAt: draft.startedAt,
                                               endedAt: draft.endedAt,
                                               miles: draft.miles,
                                               purpose: purpose,
                                               startLabel: startLabel.isEmpty ? "Start" : startLabel,
                                               endLabel: endLabel.isEmpty ? "End" : endLabel,
                                               jobName: jobName.isEmpty ? nil : jobName,
                                               notes: notes.isEmpty ? nil : notes,
                                               path: draft.path)
                        onSave(trip)
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var durationString: String {
        let s = Int(draft.endedAt.timeIntervalSince(draft.startedAt))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func bigStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
    }
}

// MARK: - Manual Trip Sheet

private struct ManualTripSheet: View {
    var existing: MileageTrip?
    var onSave: (MileageTrip) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var miles: String = ""
    @State private var purpose: TripPurpose = .inspection
    @State private var date: Date = Date()
    @State private var startLabel: String = ""
    @State private var endLabel: String = ""
    @State private var jobName: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Miles", text: $miles)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date)
                    Picker("Purpose", selection: $purpose) {
                        ForEach(TripPurpose.allCases) { p in
                            Label(p.rawValue, systemImage: p.icon).tag(p)
                        }
                    }
                }
                Section("Locations") {
                    TextField("From", text: $startLabel)
                    TextField("To", text: $endLabel)
                }
                Section("Details") {
                    TextField("Linked job", text: $jobName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existing == nil ? "Add Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let m = Double(miles) ?? 0
                        guard m > 0 else { dismiss(); return }
                        let trip = MileageTrip(
                            id: existing?.id ?? UUID(),
                            startedAt: date,
                            endedAt: date.addingTimeInterval(60 * 20),
                            miles: m,
                            purpose: purpose,
                            startLabel: startLabel.isEmpty ? "Start" : startLabel,
                            endLabel: endLabel.isEmpty ? "End" : endLabel,
                            jobName: jobName.isEmpty ? nil : jobName,
                            notes: notes.isEmpty ? nil : notes,
                            path: existing?.path ?? []
                        )
                        onSave(trip)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
            .onAppear {
                if let e = existing {
                    miles = String(format: "%.2f", e.miles)
                    purpose = e.purpose
                    date = e.startedAt
                    startLabel = e.startLabel
                    endLabel = e.endLabel
                    jobName = e.jobName ?? ""
                    notes = e.notes ?? ""
                }
            }
        }
    }
}

// MARK: - Rate Sheet

private struct MileageRateSheet: View {
    let rate: Double
    var onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rate per mile (USD)", text: $input)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Mileage Rate")
                } footer: {
                    Text("IRS standard business rate is $0.70/mile for 2026. Adjust if your firm uses a different reimbursement rate.")
                }
            }
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let v = Double(input) { onSave(v) }
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
            .onAppear { input = String(format: "%.2f", rate) }
        }
    }
}

#Preview {
    MileageTrackerView()
}
