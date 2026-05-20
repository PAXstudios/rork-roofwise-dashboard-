import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @State private var auth = AuthStore.shared
    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showForgot: Bool = false
    @FocusState private var focused: Field?

    enum Mode: String, CaseIterable { case signIn = "Sign in", signUp = "Sign up" }
    enum Field { case email, password }

    var body: some View {
        ZStack {
            backdrop
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero
                            .padding(.top, max(proxy.safeAreaInsets.top + 8, 32))
                            .padding(.bottom, 18)

                        glassCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 24))
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
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
                colors: [Theme.ink, Theme.inkRaised, Theme.sky.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Theme.ember.opacity(0.85))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -150, y: -220)

            Circle()
                .fill(Theme.sky.opacity(0.75))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 160, y: 300)

            Circle()
                .fill(Theme.amber.opacity(0.45))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: 180, y: -40)

            RoofScanAnimationView()
                .ignoresSafeArea()
                .opacity(0.85)

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image("LogoMark")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                Text("RoofWise")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(0.3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.6))
            .colorScheme(.dark)

            VStack(spacing: 8) {
                Text("Storm-ready inspections,\nin your pocket.")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                HStack(spacing: 6) {
                    Circle().fill(Theme.ember).frame(width: 6, height: 6)
                        .shadow(color: Theme.ember, radius: 6)
                    Text("AI damage detection · live")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .tracking(0.4)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Card

    private var glassCard: some View {
        VStack(spacing: 14) {
            segmentedToggle

            if let msg = auth.lastErrorMessage {
                errorBanner(msg)
            }

            oauthRow

            divider

            emailField
            passwordField

            if mode == .signIn {
                Button {
                    showForgot = true
                } label: {
                    Text("Forgot password?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }

            primaryButton

            footnote
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.10),
                                .white.opacity(0.02),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 18)
        .colorScheme(.dark)
    }

    private var segmentedToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.spring(duration: 0.28)) {
                        mode = m
                        auth.lastErrorMessage = nil
                    }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(mode == m ? Theme.ink : .white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            ZStack {
                                if mode == m {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white)
                                        .matchedGeometryEffect(id: "tab", in: tabNS)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.16), lineWidth: 0.6)
        )
    }

    @Namespace private var tabNS

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(msg)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.crimson.opacity(0.55), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.25), lineWidth: 0.6)
        )
    }

    private var oauthRow: some View {
        HStack(spacing: 10) {
            appleButton
            googleButton
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            auth.prepareAppleRequest(request)
        } onCompletion: { result in
            Task { await auth.handleAppleCompletion(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.3), lineWidth: 0.6)
        )
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 8) {
                if auth.isBusy {
                    ProgressView().tint(Theme.ink)
                } else {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Text("Google")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.white, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.3), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.6)
            Text("or with email")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.6)
                .textCase(.uppercase)
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.6)
        }
    }

    private var emailField: some View {
        fieldShell(icon: "envelope.fill", focused: focused == .email) {
            TextField("", text: $email, prompt: Text("Email").foregroundStyle(.white.opacity(0.45)))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .tint(Theme.ember)
        }
    }

    private var passwordField: some View {
        fieldShell(icon: "lock.fill", focused: focused == .password) {
            SecureField("", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.45)))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
                .tint(Theme.ember)
        }
    }

    private func fieldShell<Content: View>(
        icon: String,
        focused: Bool,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(focused ? Theme.ember : .white.opacity(0.6))
                .frame(width: 18)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.white.opacity(focused ? 0.14 : 0.08), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    focused ? Theme.ember.opacity(0.7) : .white.opacity(0.14),
                    lineWidth: focused ? 1.2 : 0.6
                )
        )
        .animation(.easeOut(duration: 0.18), value: focused)
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [Theme.ember, Theme.emberDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(spacing: 10) {
                    if auth.isBusy {
                        ProgressView().tint(.white)
                    }
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.25), lineWidth: 0.6)
            )
            .shadow(color: Theme.ember.opacity(0.55), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || auth.isBusy)
        .opacity((!canSubmit || auth.isBusy) ? 0.6 : 1)
        .padding(.top, 2)
    }

    private var footnote: some View {
        Text("By continuing you agree to our Terms & Privacy.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
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
