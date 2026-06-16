import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var showSignOutConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                accountCard
                signOutButton
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Sign out of RoofWise?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task {
                    LeadsSyncService.shared.resetLedger()
                    PhotoSyncService.shared.resetLedger()
                    await auth.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your leads.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your account")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Signed in across all your devices.")
                .font(.system(size: Theme.TypeRamp.meta))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(initials)
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayEmail)
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("Signed in")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                }
                Spacer(minLength: 0)
            }

            if let date = createdAt {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Text("Joined \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.system(size: Theme.TypeRamp.meta, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .cardStyle()
    }

    private var signOutButton: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                    .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                Text("Sign out")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            }
            .foregroundStyle(Theme.crimson)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.crimson.opacity(0.10), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var displayEmail: String {
        if case .signedIn(_, let email, _) = auth.state, let email, !email.isEmpty {
            return email
        }
        return "Apple ID user"
    }

    private var createdAt: Date? {
        if case .signedIn(_, _, let date) = auth.state { return date }
        return nil
    }

    private var initials: String {
        let parts = displayEmail.split(separator: "@").first.map(String.init) ?? "U"
        return String(parts.prefix(2)).uppercased()
    }
}

#Preview { NavigationStack { AccountView() } }
