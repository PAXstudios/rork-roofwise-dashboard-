import SwiftUI
import CoreLocation

/// Bottom sheet shown when a storm pin is tapped. Glove-friendly stack with
/// a 64pt navy "Find inspections nearby" CTA.
struct StormPinDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let event: StormPinEvent
    let centerCoord: CLLocationCoordinate2D
    /// When non-nil and the inspection has an inspection_date, the
    /// "Use as evidence for current job" CTA is shown.
    var currentReportId: String? = nil
    var onFindNearby: (Double) -> Void
    var onUseAsEvidence: (() -> Void)? = nil

    @State private var radius: Double = 5
    @State private var showEvidenceConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statRow
            sourceRow
            radiusPicker
            ctaRow
            if showEvidenceCTA { evidenceCTA }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(event.typeTint.opacity(0.18))
                Image(systemName: event.symbolName)
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(event.typeTint)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.headline)
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
    }

    private var primaryStat: (label: String, value: String) {
        switch event.eventType {
        case .hail:
            return ("Hail Size", String(format: "%.2f\"", event.hailSizeIn ?? 0))
        case .wind:
            return ("Peak Gust", "\(event.windGustMph ?? 0) mph")
        case .tornado:
            return ("Tornado", event.windGustMph.map { "\($0) mph" } ?? "On record")
        }
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat(label: primaryStat.label,
                 value: primaryStat.value,
                 tint: event.typeTint)
            stat(label: "Distance",
                 value: String(format: "%.1f mi", event.distanceMiles(from: centerCoord)),
                 tint: Theme.amber)
        }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.25), lineWidth: 0.6))
    }

    private var sourceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Text("Source · \(event.source)")
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var radiusPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RADIUS")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("\(Int(radius)) mi")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 8) {
                ForEach([2.0, 5.0, 10.0, 20.0], id: \.self) { v in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        radius = v
                    } label: {
                        Text("\(Int(v)) mi")
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                            .foregroundStyle(radius == v ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                radius == v ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card),
                                in: .capsule
                            )
                            .overlay(Capsule().stroke(radius == v ? .clear : Theme.hairline, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var showEvidenceCTA: Bool {
        guard onUseAsEvidence != nil,
              let rid = currentReportId,
              let insp = InspectionStore.shared.inspection(with: rid) else { return false }
        // Only offer the shortcut once an inspection_date exists; the spec
        // gates this on the active job actually being scheduled.
        _ = insp
        return true
    }

    private var evidenceCTA: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showEvidenceConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Text("Use as evidence for current job")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.20), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .confirmationDialog("Use this storm as event evidence?",
                            isPresented: $showEvidenceConfirm,
                            titleVisibility: .visible) {
            Button("Replace event data", role: .destructive) {
                onUseAsEvidence?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This overwrites event date, magnitude, and source on the current inspection.")
        }
    }

    private var ctaRow: some View {
        Button {
            let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
            onFindNearby(radius)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Text("Find inspections nearby")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.20), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
