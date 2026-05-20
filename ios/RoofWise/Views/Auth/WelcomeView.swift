import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @State private var auth = AuthStore.shared
    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showForgot: Bool = false
    @FocusState private var focused: Field?

    enum Mode { case signIn, signUp }
    enum Field { case email, password }

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 64)
                        .padding(.bottom, 28)

                    card
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showForgot) {
            ForgotPasswordView(prefillEmail: email)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.ink, Theme.inkRaised, Theme.sky.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Ember brand glow — warm orange top-left
            Circle()
                .fill(Theme.ember.opacity(0.85))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -150, y: -220)

            // Sky brand glow — storm blue bottom-right
            Circle()
                .fill(Theme.sky.opacity(0.75))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 160, y: 300)

            // Amber accent — middle right
            Circle()
                .fill(Theme.amber.opacity(0.45))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: 180, y: -40)

            // Futuristic roof scan animation
            RoofScanAnimationView()
                .ignoresSafeArea()

            // Soft grain overlay to deepen the gradient
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                // Soft halo behind the logo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.ember.opacity(0.55), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 110
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 8)

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .frame(width: 132, height: 132)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 0.8)
                    )
                    .shadow(color: Theme.ink.opacity(0.45), radius: 24, x: 0, y: 14)

                Image("LogoMark")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 108, height: 108)
            }
            Text("RoofWise")
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(.white)
            Text("Storm-ready inspections, in your pocket.")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 14) {
            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let msg = auth.lastErrorMessage {
                errorBanner(msg)
            }

            appleButton
            googleButton

            divider

            emailField
            passwordField

            if mode == .signIn {
                Button {
                    showForgot = true
                } label: {
                    Text("Forgot password?")
                        .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                        .foregroundStyle(Theme.sky)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }

            primaryButton

            modeToggle
        }
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.4), lineWidth: 0.6)
        )
        .shadow(color: Theme.ink.opacity(0.35), radius: 28, x: 0, y: 18)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.crimson)
            Text(msg)
                .font(.system(size: Theme.TypeRamp.meta, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.crimson.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            auth.prepareAppleRequest(request)
        } onCompletion: { result in
            Task { await auth.handleAppleCompletion(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 56)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if auth.isBusy {
                    ProgressView().tint(Theme.ink)
                } else {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Text("Continue with Google")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.white, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.hairline).frame(height: 0.6)
            Text("or")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Rectangle().fill(Theme.hairline).frame(height: 0.6)
        }
    }

    private var emailField: some View {
        fieldShell {
            Image(systemName: "envelope.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Email", text: $email)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
        }
    }

    private var passwordField: some View {
        fieldShell {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            SecureField("Password", text: $password)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.ink)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
        }
    }

    private func fieldShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Theme.canvas, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 0.8)
            )
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 10) {
                if auth.isBusy {
                    ProgressView().tint(.white)
                }
                Text(mode == .signIn ? "Sign in" : "Create account")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.inkGradient, in: .rect(cornerRadius: 14))
            .shadow(color: Theme.ink.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || auth.isBusy)
        .opacity((!canSubmit || auth.isBusy) ? 0.65 : 1)
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                mode = mode == .signIn ? .signUp : .signIn
                auth.lastErrorMessage = nil
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode == .signIn ? "New to RoofWise?" : "Already have an account?")
                    .foregroundStyle(Theme.inkSoft)
                Text(mode == .signIn ? "Create account" : "Sign in")
                    .foregroundStyle(Theme.ember)
                    .fontWeight(.heavy)
            }
            .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    private func submit() async {
        focused = nil
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .signIn: await auth.signIn(email: trimmed, password: password)
        case .signUp: await auth.signUp(email: trimmed, password: password)
        }
    }
}

// MARK: - Forgot password

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var email: String
    @FocusState private var focused: Bool

    init(prefillEmail: String) {
        _email = State(initialValue: prefillEmail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset password")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Enter your email and we'll send you a link to reset your password.")
                .font(.system(size: Theme.TypeRamp.meta))
                .foregroundStyle(Theme.inkSoft)

            if let msg = auth.lastErrorMessage {
                Text(msg)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .medium))
                    .foregroundStyle(msg.contains("sent") ? Theme.mint : Theme.crimson)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (msg.contains("sent") ? Theme.mintSoft : Theme.crimson.opacity(0.10)),
                        in: .rect(cornerRadius: 12)
                    )
            }

            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                TextField("Email", text: $email)
                    .font(.system(size: Theme.TypeRamp.body))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .focused($focused)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Theme.canvas, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.8))

            Spacer(minLength: 0)

            Button {
                Task {
                    await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                }
            } label: {
                HStack(spacing: 8) {
                    if auth.isBusy { ProgressView().tint(.white) }
                    Text("Send reset link")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(email.isEmpty || auth.isBusy)
            .opacity((email.isEmpty || auth.isBusy) ? 0.65 : 1)

            Button("Done") { dismiss() }
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(Theme.canvas)
        .onAppear { focused = true }
    }
}

#Preview { WelcomeView() }
