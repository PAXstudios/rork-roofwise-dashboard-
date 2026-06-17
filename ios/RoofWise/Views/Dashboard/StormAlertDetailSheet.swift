import SwiftUI

/// Lightweight detail sheet shown when the user taps a storm push notification.
/// Phase 6D will replace the dashboard hero with a richer treatment; this gives
/// us an immediate, useful destination for the routing pipeline today.
struct StormAlertDetailSheet: View {
    let alert: StormAlert
    var onActed: (() -> Void)? = nil
    var onSnooze: ((Date) -> Void)? = nil
    var onDismissAlert: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var push = StormPushService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricsCard
                actionStack
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                    .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(badgeText)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(badgeColor, in: .capsule)
                Text(alert.eventDate.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(alert.headline)
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(alert.areaLabel)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 10)
    }

    private var metricsCard: some View {
        HStack(spacing: 16) {
            metric("Magnitude",
                   String(format: "%.2f %@", alert.magnitudeValue, alert.magnitudeUnit))
            divider
            metric("Distance",
                   String(format: "%.1f mi", alert.distanceMi))
            divider
            metric("Properties",
                   "\(alert.propertyCount)")
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 18, radius: 18)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 0.6, height: 36)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                StormAlertStore.shared.markActedOn(id: alert.id)
                onActed?()
                dismiss()
            } label: {
                actionLabel("Mark as acted on", icon: "checkmark.circle.fill", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                let until = Date().addingTimeInterval(TimeInterval(push.snoozeMinutes * 60))
                StormAlertStore.shared.snooze(id: alert.id, until: until)
                onSnooze?(until)
                dismiss()
            } label: {
                actionLabel("Snooze \(push.snoozeMinutes) min", icon: "moon.zzz.fill", filled: false)
            }
            .buttonStyle(.plain)

            Button {
                StormAlertStore.shared.dismiss(id: alert.id)
                onDismissAlert?()
                dismiss()
            } label: {
                actionLabel("Dismiss alert", icon: "xmark.circle.fill", filled: false, destructive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ text: String, icon: String, filled: Bool, destructive: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
            Text(text)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
        }
        .foregroundStyle(filled ? Color.white : (destructive ? Theme.crimson : Theme.ink))
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(actionBackground(filled: filled, destructive: destructive),
                    in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(filled ? Color.clear : (destructive ? Theme.crimson.opacity(0.3) : Theme.hairline),
                        lineWidth: 0.6)
        )
        .shadow(color: filled ? Theme.ink.opacity(0.18) : .clear, radius: 12, y: 4)
    }

    private func actionBackground(filled: Bool, destructive: Bool) -> AnyShapeStyle {
        if filled { return AnyShapeStyle(Theme.inkGradient) }
        if destructive { return AnyShapeStyle(Theme.crimson.opacity(0.10)) }
        return AnyShapeStyle(Theme.card)
    }

    private var badgeText: String {
        switch alert.eventType {
        case .hail: return "HAIL"
        case .wind: return "WIND"
        case .tornado: return "TORNADO"
        }
    }

    private var badgeColor: Color {
        switch alert.eventType {
        case .hail: return Theme.sky
        case .wind: return Theme.amber
        case .tornado: return Theme.crimson
        }
    }
}
