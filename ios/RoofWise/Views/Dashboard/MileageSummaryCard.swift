import SwiftUI

/// Home-screen surface for the trip distance tracker. Shows month-to-date miles
/// and the estimated mileage deduction, and opens the full Mileage Tracker on tap.
struct MileageSummaryCard: View {
    var onOpen: () -> Void = {}

    @State private var store = MileageStore.shared
    @State private var tracker = MileageTrackerService.shared

    private var monthTrips: [MileageTrip] { store.monthToDate }
    private var monthMiles: Double { store.totalMiles(monthTrips) }
    private var monthDeduction: Double { store.totalReimbursement(monthTrips) }
    private var isLive: Bool { tracker.isTracking }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "car.fill")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mileage Tracker")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(statusLine)
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                            .foregroundStyle(isLive ? Theme.ember : Theme.inkFaint)
                    }
                    Spacer()
                    if isLive {
                        liveBadge
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }

                if isLive {
                    HStack(spacing: 12) {
                        metric(value: formatDuration(tracker.elapsedSeconds),
                               unit: "",
                               label: tracker.isPaused ? "Trip paused" : "Trip running",
                               tint: Theme.ember)
                        Rectangle().fill(Theme.hairline).frame(width: 0.6, height: 40)
                        metric(value: String(format: "%.2f", tracker.currentMiles),
                               unit: "mi",
                               label: "Tap to view trip",
                               tint: Theme.ink)
                        Spacer()
                    }
                } else {
                    HStack(spacing: 12) {
                        metric(value: String(format: "%.1f", monthMiles),
                               unit: "mi",
                               label: "This month",
                               tint: Theme.ink)
                        Rectangle().fill(Theme.hairline).frame(width: 0.6, height: 40)
                        metric(value: currency(monthDeduction),
                               unit: "",
                               label: "Est. deduction",
                               tint: Theme.mint)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    private var statusLine: String {
        if isLive {
            return tracker.isPaused ? "Trip paused · tap to resume" : "Trip in progress · tap to view"
        }
        if store.trackingEnabled {
            return "\(monthTrips.count) trips · auto-tracking on"
        }
        return "\(monthTrips.count) trips · tracking paused"
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(tracker.isPaused ? Theme.amber : Theme.ember)
                .frame(width: 6, height: 6)
            Text(tracker.isPaused ? "PAUSED" : "LIVE")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(tracker.isPaused ? Theme.amber : Theme.ember)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((tracker.isPaused ? Theme.amber : Theme.ember).opacity(0.12), in: .capsule)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private func metric(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            Text(label)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}
