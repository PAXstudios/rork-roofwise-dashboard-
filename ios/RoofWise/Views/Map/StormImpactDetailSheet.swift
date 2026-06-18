import SwiftUI
import CoreLocation

// MARK: - Storm impact detail sheet (Step 6)
//
// Tapping a storm pin opens this. Scrollable summary (date, type, magnitude,
// NOAA event ID, affected service-area ZIPs, lead/job counts inside the impact
// radius, the preserved "find impacted homes" radius control, and — when opened
// from a job — the "use as evidence" shortcut) sitting above three sticky CTAs:
// Door Knock This Storm · Add to Lead List · Share Storm Report.

struct StormImpactDetailSheet: View {
    let event: StormPinEvent
    let noaaEventId: String?
    let centerCoord: CLLocationCoordinate2D
    let affectedAreas: [ServiceArea]
    let leadsInRadius: Int
    let jobsInRadius: Int
    var currentReportId: String? = nil

    var onDoorKnock: () -> Void
    var onAddToLeadList: () -> Void
    var onShare: () -> Void
    var onFindNearby: (Double) -> Void
    var onUseAsEvidence: (() -> Void)? = nil

    @State private var radius: Double = 5
    @State private var showEvidenceConfirm = false

    private var tint: Color { event.isHail ? Theme.sky : Theme.ember }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    severityRow
                    statRow
                    metaCard
                    impactCounts
                    affectedZips
                    findNearbyCard
                    if showEvidenceCTA { evidenceCTA }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            ctaStack
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.18))
                Image(systemName: event.isHail ? "cloud.hail.fill" : "wind")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(tint)
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

    private var severityRow: some View {
        HStack(spacing: 8) {
            pill(text: event.severity.label.uppercased(), tint: event.severityColor)
            pill(text: "\(event.daysSince)d AGO", tint: event.recencyColor)
            Spacer()
        }
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: .capsule)
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 10) {
            stat(label: event.isHail ? "Hail Size" : "Peak Gust",
                 value: event.isHail
                    ? String(format: "%.2f\"", event.hailSizeIn ?? 0)
                    : "\(event.windGustMph ?? 0) mph",
                 tint: tint)
            stat(label: "Impact Radius",
                 value: "\(Int(event.impactRadiusMiles)) mi",
                 tint: Theme.ember)
            stat(label: "Distance",
                 value: String(format: "%.1f mi", event.distanceMiles(from: centerCoord)),
                 tint: Theme.amber)
        }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.25), lineWidth: 0.6))
    }

    // MARK: Meta

    private var metaCard: some View {
        VStack(spacing: 10) {
            metaRow(icon: "number", label: "NOAA Event ID",
                    value: (noaaEventId?.isEmpty == false ? noaaEventId! : "Not catalogued"))
            Divider().overlay(Theme.hairline)
            metaRow(icon: "antenna.radiowaves.left.and.right", label: "Source", value: event.source)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 20)
            Text(label)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Impact counts

    private var impactCounts: some View {
        HStack(spacing: 10) {
            countTile(value: leadsInRadius, label: "Leads in radius", tint: Theme.sky, icon: "person.fill")
            countTile(value: jobsInRadius, label: "Jobs in radius", tint: Theme.mint, icon: "hammer.fill")
        }
    }

    private func countTile(value: Int, label: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(label)
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Affected ZIPs

    @ViewBuilder
    private var affectedZips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AFFECTED SERVICE AREA")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            if affectedAreas.isEmpty {
                Text("No saved ZIPs fall inside this storm's impact radius.")
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(affectedAreas) { area in
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text(area.label)
                                .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.ink.opacity(0.06), in: .capsule)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Find nearby (preserved)

    private var findNearbyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FIND IMPACTED HOMES")
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
                        UISelectionFeedbackGenerator().selectionChanged()
                        radius = v
                    } label: {
                        Text("\(Int(v)) mi")
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                            .foregroundStyle(radius == v ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(radius == v ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card), in: .capsule)
                            .overlay(Capsule().stroke(radius == v ? .clear : Theme.hairline, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onFindNearby(radius)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Filter leads & jobs to this radius")
                        .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.ember.opacity(0.14), in: .capsule)
                .overlay(Capsule().stroke(Theme.ember.opacity(0.35), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Evidence (preserved)

    private var showEvidenceCTA: Bool {
        onUseAsEvidence != nil && currentReportId != nil
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
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.mint, in: .capsule)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Use this storm as event evidence?",
                            isPresented: $showEvidenceConfirm,
                            titleVisibility: .visible) {
            Button("Replace event data", role: .destructive) { onUseAsEvidence?() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This overwrites event date, magnitude, and source on the current inspection.")
        }
    }

    // MARK: Sticky CTAs

    private var ctaStack: some View {
        VStack(spacing: 10) {
            primaryCTA(title: "Door Knock This Storm", icon: "hand.tap.fill",
                       style: .ink, action: onDoorKnock)
            primaryCTA(title: "Add to Lead List", icon: "person.crop.circle.badge.plus",
                       style: .ember, action: onAddToLeadList)
            primaryCTA(title: "Share Storm Report", icon: "square.and.arrow.up",
                       style: .outline, action: onShare)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private enum CTAStyle { case ink, ember, outline }

    private func primaryCTA(title: String, icon: String, style: CTAStyle,
                            action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Text(title)
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            }
            .foregroundStyle(style == .outline ? Theme.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(ctaBackground(style))
            .clipShape(.rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(style == .outline ? Theme.ink.opacity(0.35) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func ctaBackground(_ style: CTAStyle) -> some View {
        switch style {
        case .ink:     Theme.inkGradient
        case .ember:   LinearGradient(colors: [Theme.ember, Theme.emberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .outline: Color.clear
        }
    }
}
