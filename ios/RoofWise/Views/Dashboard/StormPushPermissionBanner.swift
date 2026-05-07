import SwiftUI
import UserNotifications

/// Shown on the dashboard when the workspace is armed (has at least one
/// service area) but the user hasn't granted notification permission.
struct StormPushPermissionBanner: View {
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var requesting = false
    @State private var push = StormPushService.shared

    var body: some View {
        Group {
            if shouldShow {
                content
                    .task { await refresh() }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: ServiceAreaStore.shared.areas.count) {
            await refresh()
        }
    }

    private var shouldShow: Bool {
        guard ServiceAreaStore.shared.hasConfiguredServiceArea else { return false }
        guard push.isEnabled else { return false }
        return status == .notDetermined || status == .denied
    }

    private var isDenied: Bool { status == .denied }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.emberSoft)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STORM PUSH ALERTS")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text(isDenied
                         ? "Notifications are off — turn them on in Settings to get storm alerts."
                         : "Get a push the moment a storm hits your service area.")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            Button(action: handleTap) {
                HStack(spacing: 8) {
                    Image(systemName: isDenied ? "gear" : "bell.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text(isDenied ? "Open Settings" : "Enable notifications")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
                .opacity(requesting ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(requesting)
        }
        .padding(16)
        .background(Theme.emberSoft, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.ember.opacity(0.45), lineWidth: 0.8))
    }

    private func handleTap() {
        if isDenied {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
            return
        }
        requesting = true
        Task {
            _ = await push.requestAuthorization()
            await refresh()
            requesting = false
        }
    }

    private func refresh() async {
        await push.refreshStatus()
        status = push.authorizationStatus
    }
}
