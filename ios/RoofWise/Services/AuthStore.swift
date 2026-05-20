import Foundation
import Observation
import Supabase
import AuthenticationServices
import CryptoKit
import UIKit

enum AuthState: Equatable {
    case unknown          // initial — checking persisted session
    case signedOut
    case signedIn(userId: String, email: String?, createdAt: Date?)
}

@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var state: AuthState = .unknown
    var lastErrorMessage: String? = nil
    var isBusy: Bool = false

    private var sessionTask: Task<Void, Never>? = nil
    /// Per-sign-in-with-Apple nonce, kept between request and credential delivery.
    private var currentNonce: String? = nil

    private init() {
        sessionTask = Task { [weak self] in
            await self?.startSessionObserver()
        }
    }

    deinit { sessionTask?.cancel() }

    // MARK: - Session lifecycle

    private func startSessionObserver() async {
        // Hydrate from any persisted session.
        do {
            let session = try await SupabaseService.client.auth.session
            applySession(session)
        } catch {
            state = .signedOut
        }

        // Stream auth changes (sign-in, token refresh, sign-out).
        for await change in SupabaseService.client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
                if let session = change.session {
                    applySession(session)
                } else {
                    state = .signedOut
                }
            case .signedOut:
                state = .signedOut
            default:
                break
            }
        }
    }

    private func applySession(_ session: Session) {
        let user = session.user
        state = .signedIn(
            userId: user.id.uuidString,
            email: user.email,
            createdAt: user.createdAt
        )
    }

    var currentUserId: String? {
        if case .signedIn(let id, _, _) = state { return id }
        return nil
    }

    // MARK: - Email + password

    func signIn(email: String, password: String) async {
        await run {
            _ = try await SupabaseService.client.auth.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            let response = try await SupabaseService.client.auth.signUp(email: email, password: password)
            // Some projects require email confirmation; in that case session is nil.
            if response.session == nil {
                self.lastErrorMessage = "Check your email to confirm your account, then sign in."
            }
        }
    }

    func sendPasswordReset(email: String) async {
        await run {
            try await SupabaseService.client.auth.resetPasswordForEmail(email)
            self.lastErrorMessage = "Password reset link sent — check your email."
        }
    }

    // MARK: - Sign in with Apple

    /// Prepare an ASAuthorizationAppleIDRequest with a fresh nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            self.lastErrorMessage = "Apple sign-in cancelled or failed: \(error.localizedDescription)"
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                self.lastErrorMessage = "Apple sign-in returned an unexpected response."
                return
            }
            await run {
                try await SupabaseService.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
            }
        }
    }

    // MARK: - Sign in with Google (Supabase OAuth via ASWebAuthenticationSession)

    func signInWithGoogle() async {
        await run {
            _ = try await SupabaseService.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "roofwise://login-callback"),
                queryParams: [
                    (name: "access_type", value: "offline"),
                    (name: "prompt", value: "consent")
                ]
            ) { (session: ASWebAuthenticationSession) in
                session.presentationContextProvider = WebAuthAnchor.shared
                session.prefersEphemeralWebBrowserSession = false
            }
        }
    }

    // MARK: - Sign out / delete

    func signOut() async {
        await run {
            try await SupabaseService.client.auth.signOut()
        }
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            self.lastErrorMessage = Self.friendlyMessage(for: error)
            print("[AuthStore] error: \(error)")
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login") || raw.contains("invalid credentials") {
            return "Wrong email or password — try again or reset it."
        }
        if raw.contains("user already registered") || raw.contains("already registered") {
            return "An account with that email already exists. Try signing in."
        }
        if raw.contains("network") || raw.contains("offline") {
            return "No internet connection — try again when you're back online."
        }
        return error.localizedDescription
    }

    // MARK: - Apple nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms: [UInt8] = Array(repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess { fatalError("Unable to generate nonce: \(status)") }
            for r in randoms where remaining > 0 {
                if r < charset.count { result.append(charset[Int(r)]); remaining -= 1 }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
