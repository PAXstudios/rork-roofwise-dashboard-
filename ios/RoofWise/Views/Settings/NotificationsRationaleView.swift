import SwiftUI
import UserNotifications

/// One-shot rationale screen presented after the user adds their first
/// service area. Explains why we need notification permission and offers
/// an explicit Allow / Not now choice. The actual prompt is only fired
/// when the user taps Allow, matching Apple's HIG guidance.
struct NotificationsRationaleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requesting = false
    @State private var toast: String? = nil

    private let bullets: [(String, String, Color)] = [
        ("cloud.bolt.rain.fill", "Severe weather only", Theme.crimson),
        ("hand.tap.fill", "Tap to start knocking", Theme.sky),
        ("zzz", "Snooze any alert 4h", Theme.amber)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    bodyCard
                    bulletStack
                    Color.clear.frame(height: 140)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)

            stickyBar

            if let toast {
                toastView(toast)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.canvas)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(Theme.emberSoft)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 64, height: 64)

            Text("Stay ahead of the storm.")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyCard: some View {
        Text("When a hailstorm or wind event hits one of your service areas, RoofWise will buzz your phone with the address count and let you tap to start a knocking route. We never share your location with anyone else.")
            .font(.system(size: Theme.TypeRamp.body))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 18, radius: 22)
    }

    // MARK: - Bullets

    private var bulletStack: some View {
        VStack(spacing: 10) {
            ForEach(bullets, id: \.1) { icon, label, tint in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16))
                        Image(systemName: icon)
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 44, height: 44)
                    Text(label)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
            }
        }
    }

    // MARK: - Sticky CTA

    private var stickyBar: some View {
        VStack(spacing: 10) {
            Button(action: handleAllow) {
                HStack(spacing: 10) {
                    if requesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bell.fill")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    }
                    Text(requesting ? "Requesting…" : "Allow notifications")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
                .opacity(requesting ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(requesting)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(requesting)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            Theme.card
                .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
                .shadow(color: Theme.ink.opacity(0.10), radius: 18, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func toastView(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.mint)
            Text(text)
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.12), radius: 14, y: 4)
    }

    // MARK: - Actions

    private func handleAllow() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        requesting = true
        Task {
            let granted = await StormPushService.shared.requestAuthorization()
            requesting = false
            withAnimation(.spring(duration: 0.3)) {
                toast = granted ? "Notifications on" : "You can enable later in Settings"
            }
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        }
    }
}

#Preview {
    NotificationsRationaleView()
}
