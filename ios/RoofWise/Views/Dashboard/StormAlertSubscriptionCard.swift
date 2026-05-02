import SwiftUI
import UserNotifications

struct StormAlertSubscriptionCard: View {
    @AppStorage("rw.storm.alerts.on") private var alertsOn: Bool = true
    @AppStorage("rw.storm.alerts.zips") private var zipsRaw: String = "75024,75035,75070"
    @State private var permissionDenied = false
    @State private var pulse = false

    private var zips: [String] {
        zipsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.crimson, Theme.ember],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(pulse ? 1.08 : 1.0)
                            .animation(.spring(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storm Push Alerts")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(alertsOn ? "Live monitoring · \(zips.count) ZIPs" : "Paused")
                            .font(.system(size: 11))
                            .foregroundStyle(alertsOn ? Theme.mint : Theme.inkFaint)
                    }
                }
                Spacer()
                Toggle("", isOn: $alertsOn)
                    .labelsHidden()
                    .tint(Theme.ember)
                    .onChange(of: alertsOn) { _, newValue in
                        if newValue { requestPermissionAndDemo() }
                    }
            }

            // ZIPs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(zips, id: \.self) { z in
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9, weight: .bold))
                            Text(z)
                                .font(.system(size: 11, weight: .heavy))
                                .monospacedDigit()
                        }
                        .foregroundStyle(alertsOn ? Theme.ink : Theme.inkFaint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(alertsOn ? Theme.canvas : Theme.canvas.opacity(0.6),
                                    in: .capsule)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
                    }
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("Add ZIP")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.emberSoft, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentMargins(.horizontal, 0)

            // Live mock alert preview when on
            if alertsOn {
                liveAlert
            } else {
                pausedNotice
            }

            if permissionDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)
                    Text("Enable notifications in Settings to receive storm pushes.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amberSoft, in: .rect(cornerRadius: 10))
            }
        }
        .cardStyle(padding: 18, radius: 24)
        .padding(.horizontal, 20)
        .onAppear { pulse = true }
    }

    private var liveAlert: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.crimson.opacity(0.15))
                Image(systemName: "cloud.bolt.rain.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.crimson)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.crimson, in: .capsule)
                    Text("12 min ago")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                Text("Hail core moving through 75024 — peak 1.75″")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("18 of your knocked leads sit inside the impact zone.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.95), Theme.canvas],
                           startPoint: .leading, endPoint: .trailing),
            in: .rect(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.crimson.opacity(0.25), lineWidth: 0.8))
    }

    private var pausedNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Alerts paused")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Turn on to get a push the moment a storm hits your work area.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private func requestPermissionAndDemo() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                permissionDenied = !granted
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "RoofWise · Storm Hit"
                content.body = "Hail core in 75024 — 18 of your knocked leads are inside the zone. Tap to canvas."
                content.sound = .default
                let req = UNNotificationRequest(
                    identifier: "rw.storm.demo",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 6, repeats: false)
                )
                center.add(req)
            }
        }
    }
}
