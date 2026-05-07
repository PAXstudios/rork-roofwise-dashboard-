import SwiftUI

/// Vertical timeline of all events logged against an inspection.
struct ActivityFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ActivityStore.shared

    let reportId: String

    private var events: [ActivityEvent] { store.events(for: reportId) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()

                if events.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(events) { event in
                                row(event)
                            }
                            Color.clear.frame(height: 120)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }

                doneBar
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(Theme.inkFaint)
            Text("No activity yet")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Each step you take on this job will log here automatically.")
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func row(_ event: ActivityEvent) -> some View {
        let style = Self.style(for: event.kind)
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(style.tint.opacity(0.15))
                Image(systemName: style.icon as String)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(style.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.summary)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(event.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .cardStyle(padding: 14, radius: 16)
    }

    private var doneBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.canvas)
    }

    // MARK: Style mapping

    static func style(for kind: ActivityEvent.Kind) -> (icon: String, tint: Color) {
        switch kind {
        case .jobCreated:                  return ("doc.badge.plus", Theme.ink)
        case .addressGeocoded:             return ("mappin.and.ellipse", Theme.sky)
        case .weatherSynced:               return ("cloud.sun.fill", Theme.sky)
        case .stormMatched:                return ("cloud.hail.fill", Theme.amber)
        case .roofDetected:                return ("square.3.layers.3d.top.filled", Theme.ember)
        case .slopeAdded:                  return ("plus.square.on.square", Theme.mint)
        case .slopeEdited:                 return ("pencil.and.outline", Theme.amber)
        case .decisionComputed:            return ("brain.head.profile", Theme.ember)
        case .signatureInspectorCaptured:  return ("signature", Theme.ink)
        case .signatureHomeownerCaptured:  return ("signature", Theme.ember)
        case .reportGenerated:             return ("doc.richtext.fill", Theme.crimson)
        case .estimateSaved:               return ("dollarsign.circle.fill", Theme.mint)
        case .estimateConverted:           return ("arrow.triangle.branch", Theme.mint)
        case .noteAdded:                   return ("note.text", Theme.inkSoft)
        case .knockLogged:                 return ("hand.tap.fill", Theme.sky)
        case .knockConvertedToLead:        return ("person.crop.circle.badge.checkmark", Theme.mint)
        case .routeCompleted:              return ("flag.checkered", Theme.ember)
        }
    }
}
