import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var showSignOutConfirm: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteFinalConfirm: Bool = false
    @State private var isDeleting: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                accountCard
                legalCard
                signOutButton
                deleteAccountButton
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
        .confirmationDialog(
            "Delete your RoofWise account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showDeleteFinalConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account, leads, inspections, and photos from this device and requests deletion from RoofWise servers. This cannot be undone.")
        }
        .confirmationDialog(
            "Are you absolutely sure?",
            isPresented: $showDeleteFinalConfirm,
            titleVisibility: .visible
        ) {
            Button(isDeleting ? "Deleting…" : "Delete Account Forever", role: .destructive) {
                guard !isDeleting else { return }
                isDeleting = true
                Task {
                    _ = await auth.deleteAccount()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Final step. Your account and all associated data will be erased.")
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

    private var legalCard: some View {
        VStack(spacing: 0) {
            legalRow(
                icon: "hand.raised.fill",
                title: "Privacy Policy",
                url: LegalLinks.privacyPolicy
            )
            Rectangle().fill(Theme.hairline).frame(height: 0.6)
            legalRow(
                icon: "doc.text.fill",
                title: "Terms of Use",
                url: LegalLinks.termsOfUse
            )
            Rectangle().fill(Theme.hairline).frame(height: 0.6)
            legalRow(
                icon: "envelope.fill",
                title: "Support",
                url: LegalLinks.support
            )
        }
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func legalRow(icon: String, title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.ink.opacity(0.06))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 40, height: 40)
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    private var deleteAccountButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                Text(isDeleting ? "Deleting…" : "Delete account")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.crimson, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .opacity(isDeleting ? 0.7 : 1)
        .accessibilityHint("Permanently deletes your RoofWise account and data")
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

/// Hosted legal URLs. Keep these stable — App Review and Sign in with Apple
/// both require them to resolve.
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://roofwise.app/privacy")!
    static let termsOfUse = URL(string: "https://roofwise.app/terms")!
    static let support = URL(string: "https://roofwise.app/support")!
}

#Preview { NavigationStack { AccountView() } }
