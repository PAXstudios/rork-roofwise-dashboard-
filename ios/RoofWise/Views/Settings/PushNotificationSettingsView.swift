import SwiftUI
import UserNotifications

struct PushNotificationSettingsView: View {
    @State private var push = StormPushService.shared
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var enabled: Bool = StormPushService.shared.isEnabled
    @State private var sound: Bool = StormPushService.shared.soundEnabled
    @State private var snoozeMinutes: Int = StormPushService.shared.snoozeMinutes
    @State private var requesting = false

    private let snoozeChoices: [Int] = [15, 30, 60, 120, 240]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                permissionCard
                preferenceCard
                snoozeCard
                correctionsSyncCard
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    // MARK: Phase 9 corrections sync

    @State private var syncCorrections: Bool = CorrectionsSyncService.shared.syncEnabled

    private var correctionsSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI LEARNING")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            Toggle(isOn: $syncCorrections) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync corrections to cloud")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Help RoofWise improve the AI")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.ember)
            .onChange(of: syncCorrections) { _, newValue in
                CorrectionsSyncService.shared.syncEnabled = newValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Storm Push Alerts")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Get a push the moment a qualifying storm hits any of your service areas.")
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(statusTint.opacity(0.18))
                    Image(systemName: statusIcon)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(statusTint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SYSTEM PERMISSION")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text(statusLabel)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }

            if status != .authorized && status != .provisional {
                Button(action: handlePermissionTap) {
                    HStack(spacing: 8) {
                        Image(systemName: status == .denied ? "gear" : "bell.fill")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        Text(status == .denied ? "Open iOS Settings" : "Enable notifications")
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
        }
        .cardStyle(padding: 18, radius: 22)
    }

    private var preferenceCard: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "Storm push alerts",
                subtitle: "Master switch for storm notifications.",
                isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        enabled = newValue
                        push.isEnabled = newValue
                    }
                )
            )
            Divider().background(Theme.hairline)
            toggleRow(
                title: "Sound",
                subtitle: "Play the default sound with each alert.",
                isOn: Binding(
                    get: { sound },
                    set: { newValue in
                        sound = newValue
                        push.soundEnabled = newValue
                    }
                )
            )
            .opacity(enabled ? 1 : 0.4)
            .disabled(!enabled)
        }
        .cardStyle(padding: 0, radius: 22)
    }

    private var snoozeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snooze duration")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("How long the 'Snooze' notification action hides an alert.")
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(snoozeChoices, id: \.self) { mins in
                        snoozeChip(mins: mins)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 22)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private func snoozeChip(mins: Int) -> some View {
        let selected = snoozeMinutes == mins
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            snoozeMinutes = mins
            push.snoozeMinutes = mins
        } label: {
            Text(label(forMinutes: mins))
                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                .foregroundStyle(selected ? .white : Theme.ink)
                .frame(minHeight: 56)
                .padding(.horizontal, 18)
                .background(
                    selected ? AnyShapeStyle(Theme.inkGradient) : AnyShapeStyle(Theme.card as Color),
                    in: .rect(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(selected ? Color.clear : Theme.hairline, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private func label(forMinutes mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let hours = mins / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    // MARK: Rows

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.ember)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }

    // MARK: Status presentation

    private var statusLabel: String {
        switch status {
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .denied: return "Blocked in iOS Settings"
        case .notDetermined: return "Not yet requested"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized, .provisional: return "checkmark.shield.fill"
        case .denied: return "xmark.shield.fill"
        default: return "bell.slash.fill"
        }
    }

    private var statusTint: Color {
        switch status {
        case .authorized, .provisional: return Theme.mint
        case .denied: return Theme.crimson
        default: return Theme.amber
        }
    }

    // MARK: Actions

    private func handlePermissionTap() {
        if status == .denied {
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
        enabled = push.isEnabled
        sound = push.soundEnabled
        snoozeMinutes = push.snoozeMinutes
    }
}

#Preview {
    NavigationStack { PushNotificationSettingsView() }
}
