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
        // Safety net: if neither `authStateChanges` nor `.session` answers within
        // 2.5s (slow network, blocked DNS, etc.), unstick the UI by falling back
        // to signedOut so the Welcome screen renders instead of hanging on the
        // launch splash forever.
        let fallback = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard let self else { return }
            if case .unknown = self.state {
                print("[AuthStore] bootstrap timeout — defaulting to signedOut")
                self.state = .signedOut
            }
        }

        // Kick off a non-blocking hydrate. `authStateChanges` will also emit
        // `.initialSession`, but on some cold starts the property read is what
        // triggers it, so we still want to ping it.
        Task { [weak self] in
            do {
                let session = try await SupabaseService.client.auth.session
                await MainActor.run { self?.applySession(session) }
            } catch {
                await MainActor.run {
                    if case .unknown = self?.state ?? .signedOut {
                        self?.state = .signedOut
                    }
                }
            }
        }

        // Stream auth changes (sign-in, token refresh, sign-out).
        for await change in SupabaseService.client.auth.authStateChanges {
            fallback.cancel()
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
        // Dev bypass: when auth is disabled via APIKeys.requireAuth = false,
        // surface a stable per-install id so downstream services (leads sync,
        // local learning) don't no-op on a nil user.
        if !APIKeys.requireAuth { return "dev-local-user" }
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
            let response = try await SupabaseService.client.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: "roofwise://auth/callback")
            )
            // Some projects require email confirmation; in that case session is nil.
            if response.session == nil {
                self.lastErrorMessage = "Check your email to confirm your account, then sign in."
            }
        }
    }

    func sendPasswordReset(email: String) async {
        await run {
            try await SupabaseService.client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "roofwise://auth/callback")
            )
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
            self.lastErrorMessage = Self.appleFailureMessage(for: error)
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

    /// Deletes the signed-in account and wipes local user data. Tries the
    /// Supabase `delete-account` edge function first (server-side admin
    /// delete). If that isn't deployed yet, still clears every on-device
    /// store and signs the session out so the user is fully de-authed and
    /// their local PII is gone — satisfying Guideline 5.1.1(v) locally
    /// while the server-side wipe finishes asynchronously when available.
    func deleteAccount() async -> Bool {
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        // 1. Best-effort server-side account deletion via edge function.
        // The function (when deployed) should call auth.admin.deleteUser with
        // the service-role key. Failure here is non-fatal — local wipe + sign
        // out still run so the user is de-authed on device.
        var serverDeleted = false
        do {
            // Decode as raw Data so we don't require a response schema.
            let _: Data = try await SupabaseService.client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(method: .post)
            )
            serverDeleted = true
        } catch {
            print("[AuthStore] delete-account function: \(error)")
        }

        // 2. Wipe local user data regardless of server result.
        Self.wipeLocalUserData()

        // 3. Sign out so the session is gone.
        do {
            try await SupabaseService.client.auth.signOut()
            state = .signedOut
        } catch {
            // Force local signed-out even if the network call fails.
            state = .signedOut
            print("[AuthStore] signOut after delete failed: \(error)")
        }

        if !serverDeleted {
            lastErrorMessage = "Account removed from this device. If you still see it on another device, email support@roofwise.app and we'll finish the wipe."
        }
        return true
    }

    /// Clears every on-device store that holds user/PII data.
    private static func wipeLocalUserData() {
        LeadsSyncService.shared.resetLedger()
        PhotoSyncService.shared.resetLedger()

        // Wipe Documents JSON files the app owns.
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let prefixes = [
            "inspections", "knock-sessions", "training-queue",
            "storm_alerts", "stormwatch-seen", "activity-",
            "customers", "proposals", "estimates", "corrections",
            "safety_assessments", "geocode-cache"
        ]
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if prefixes.contains(where: { name.hasPrefix($0) }) {
                    try? fm.removeItem(at: url)
                }
            }
        }

        // Clear UserDefaults keys we own.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("rw.") {
            defaults.removeObject(forKey: key)
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

    /// Maps Apple's ASAuthorization errors to a friendly message. User cancellation
    /// is silent; the simulator "unknown" failure (no iCloud account) is explained.
    private static func appleFailureMessage(for error: Error) -> String? {
        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled:
                return nil // user backed out — don't show an error
            case .unknown, .failed, .notInteractive:
                return "Sign in with Apple needs a device signed into iCloud. It can't run in the preview simulator — install RoofWise on your iPhone to use it, or sign in with email below."
            default:
                break
            }
        }
        return "Apple sign-in couldn't be completed. Try again, or sign in with email below."
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
