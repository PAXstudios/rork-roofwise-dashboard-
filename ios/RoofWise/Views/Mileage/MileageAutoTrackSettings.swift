import SwiftUI
import CoreLocation
import UserNotifications

struct MileageAutoTrackSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = MileageAutoTrackService.shared
    @State private var notificationsAuthorized: Bool = false
    @State private var requesting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    permissionsCard
                    rulesCard
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .background(Theme.canvas)
            .navigationTitle("Auto-Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
            .task { await refreshNotificationStatus() }
        }
    }

    // MARK: Hero / toggle

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Detect Drives Automatically")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("RoofWise watches for drives in the background and asks if you want to log each one.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: Binding(
                get: { service.isEnabled },
                set: { newValue in
                    service.toggle(newValue)
                    if newValue {
                        Task {
                            await ensurePermissions()
                        }
                    }
                }
            )) {
                Text("Auto-Tracking")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ember)

            HStack(spacing: 10) {
                statusChip(label: "Location",
                           value: locationStatusText,
                           color: locationStatusColor)
                statusChip(label: "Notifications",
                           value: notificationsAuthorized ? "Allowed" : "Off",
                           color: notificationsAuthorized ? Theme.mint : Theme.crimson)
            }
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Permissions

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkFaint)

            permissionRow(icon: "location.circle.fill",
                          tint: Theme.sky,
                          title: "Always Allow Location",
                          subtitle: "Required so RoofWise can detect drives even when the app is closed.",
                          actionTitle: locationStatusText == "Always" ? "Granted" : "Allow",
                          isComplete: locationStatusText == "Always") {
                service.requestAuthorization()
            }

            permissionRow(icon: "bell.badge.fill",
                          tint: Theme.amber,
                          title: "Notifications",
                          subtitle: "We tap you with a one-shot prompt: \"Looks like you drove X mi — log it?\"",
                          actionTitle: notificationsAuthorized ? "Granted" : "Allow",
                          isComplete: notificationsAuthorized) {
                Task {
                    requesting = true
                    let ok = await service.requestNotificationAuthorization()
                    notificationsAuthorized = ok
                    requesting = false
                }
            }

            if locationStatusText != "Always" || !notificationsAuthorized {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(.system(size: 11, weight: .heavy))
                        Text("Open System Settings")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(Theme.ember)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func permissionRow(icon: String,
                               tint: Color,
                               title: String,
                               subtitle: String,
                               actionTitle: String,
                               isComplete: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(isComplete ? Theme.mint : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background {
                        if isComplete {
                            Capsule().fill(Theme.mint.opacity(0.15))
                        } else {
                            Capsule().fill(Theme.ink)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isComplete)
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detection Rules")
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkFaint)

            rule(icon: "speedometer", text: "Trip starts when you're moving faster than 5 mph.")
            rule(icon: "ruler", text: "Trip is logged only if you cover more than 0.5 miles.")
            rule(icon: "clock.badge", text: "Trip ends after you've been stopped for 5+ minutes.")
            rule(icon: "battery.100", text: "Powered by significant-location-change monitoring — minimal battery cost.")
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func rule(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.ember)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: Status helpers

    private var locationStatusText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private var locationStatusColor: Color {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return Theme.mint
        case .authorizedWhenInUse: return Theme.amber
        default: return Theme.crimson
        }
    }

    private func statusChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.canvas, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
    }

    private func ensurePermissions() async {
        service.requestAuthorization()
        let ok = await service.requestNotificationAuthorization()
        notificationsAuthorized = ok
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = (settings.authorizationStatus == .authorized
                                    || settings.authorizationStatus == .provisional)
    }
}

// MARK: - Auto-detected trip confirmation sheet

struct AutoDetectedTripSheet: View {
    let trip: PendingAutoTrip
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
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-detected drive")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text(durationString + " · " + dateString)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text(String(format: "%.1f mi", trip.miles))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                            .monospacedDigit()
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
            .navigationTitle("Log This Drive?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Dismiss", role: .destructive) {
                        onDiscard()
                    }
                    .foregroundStyle(Theme.crimson)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log It") {
                        let final = MileageTrip(
                            startedAt: trip.startedAt,
                            endedAt: trip.endedAt,
                            miles: trip.miles,
                            purpose: purpose,
                            startLabel: startLabel.isEmpty ? "Start" : startLabel,
                            endLabel: endLabel.isEmpty ? "End" : endLabel,
                            jobName: jobName.isEmpty ? nil : jobName,
                            notes: notes.isEmpty ? nil : notes,
                            path: trip.path
                        )
                        onSave(final)
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var durationString: String {
        let s = Int(trip.endedAt.timeIntervalSince(trip.startedAt))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mma"
        return f.string(from: trip.startedAt).lowercased()
    }
}
