import SwiftUI

/// Top-level Settings hub. Replaces the direct Service Area navigation from
/// the dashboard gear button so we can house Account + other settings rows.
struct SettingsHubView: View {
    @State private var auth = AuthStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                accountRow
                row(
                    icon: "mappin.and.ellipse",
                    title: "Service area",
                    subtitle: "ZIPs we watch for storms",
                    tint: Theme.amber,
                    destination: AnyView(ServiceAreaView())
                )
                row(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Storm and weekly summary pushes",
                    tint: Theme.sky,
                    destination: AnyView(PushNotificationSettingsView())
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var accountRow: some View {
        NavigationLink {
            AccountView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(initials)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(emailLabel)
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("Account")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func row(icon: String, title: String, subtitle: String, tint: Color, destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private var emailLabel: String {
        if case .signedIn(_, let email, _) = auth.state, let email, !email.isEmpty { return email }
        return "Apple ID user"
    }

    private var initials: String {
        let parts = emailLabel.split(separator: "@").first.map(String.init) ?? "U"
        return String(parts.prefix(2)).uppercased()
    }
}

#Preview { NavigationStack { SettingsHubView() } }
