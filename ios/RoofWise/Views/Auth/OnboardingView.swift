import SwiftUI

// MARK: - Persistence

enum OnboardingStore {
    static let completedKey = "roofwise.onboarding.completed.v2"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
}

// MARK: - Page model

private struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let eyebrow: String
    let title: String
    let body: String
    let accent: Color
    let kind: Kind

    enum Kind: Equatable {
        case brand
        case scan
        case storm
        case claim
        case launch
    }
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        id: 0,
        eyebrow: "ROOFWISE",
        title: "Storm-ready\nroofing, simplified.",
        body: "The field tool built for inspectors who chase hail, write claims, and close jobs before the next front rolls in.",
        accent: Theme.ember,
        kind: .brand
    ),
    OnboardingPage(
        id: 1,
        eyebrow: "AI DAMAGE SCAN",
        title: "See every hit.\nDocument it once.",
        body: "Point your camera. RoofWise marks hail, wind, and wear in real time so your report is courtroom-clean before you leave the driveway.",
        accent: Theme.ember,
        kind: .scan
    ),
    OnboardingPage(
        id: 2,
        eyebrow: "STORM INTEL",
        title: "Chase the path.\nKnock the right doors.",
        body: "Three years of hail and wind history on a live map — filter by size, radius, and service area, then walk a door-knock route that actually converts.",
        accent: Theme.sky,
        kind: .storm
    ),
    OnboardingPage(
        id: 3,
        eyebrow: "CLAIMS & CLOSES",
        title: "From photo\nto signed proposal.",
        body: "One flow for leads, inspections, estimates, and homeowner-ready packets. Less paperwork. More roofs won.",
        accent: Theme.mint,
        kind: .claim
    ),
    OnboardingPage(
        id: 4,
        eyebrow: "LET'S GO",
        title: "Your crew is\nwaiting on deck.",
        body: "Create your account and start your first lead in under a minute. Built for gloves, sun, and the next severe weather alert.",
        accent: Theme.ember,
        kind: .launch
    ),
]

// MARK: - Root onboarding

struct OnboardingView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex: Int = 0
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @Namespace private var dotNS

    private var page: OnboardingPage { onboardingPages[pageIndex] }
    private var isLast: Bool { pageIndex == onboardingPages.count - 1 }

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                TabView(selection: $pageIndex) {
                    ForEach(onboardingPages) { p in
                        pageContent(p)
                            .tag(p.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.Motion.standard, value: pageIndex)

                bottomChrome
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            withAnimation(Theme.Motion.entrance) { appeared = true }
        }
        .sensoryFeedback(.selection, trigger: pageIndex)
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.ink, Theme.inkRaised, Theme.ink.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ember glow — top leading
            Circle()
                .fill(Theme.ember.opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: -130, y: -220)
                .opacity(appeared ? 1 : 0)

            // Sky glow — shifts with page
            Circle()
                .fill(page.accent.opacity(0.40))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: 150, y: 280)
                .animation(Theme.Motion.entrance, value: pageIndex)

            // Soft amber wash
            Circle()
                .fill(Theme.amber.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: 160, y: -60)

            // Subtle grain grid
            OnboardingGridOverlay()
                .opacity(0.35)
                .allowsHitTesting(false)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image("LogoMark")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Text("RoofWise")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -12)

            Spacer()

            if !isLast {
                Button {
                    finish()
                } label: {
                    Text("Skip")
                        .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(minWidth: 56, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
            }
        }
    }

    // MARK: Page content

    private func pageContent(_ p: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            OnboardingIllustration(kind: p.kind, accent: p.accent, active: pageIndex == p.id)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 12)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 14) {
                Text(p.eyebrow)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy, design: .rounded))
                    .foregroundStyle(p.accent)
                    .tracking(1.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(p.accent.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(p.accent.opacity(0.35), lineWidth: 0.6))

                Text(p.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

                Text(p.body)
                    .font(.system(size: Theme.TypeRamp.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
            // Re-trigger text entrance when page changes via id
            .id(p.id)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 18)),
                removal: .opacity.combined(with: .offset(y: -8))
            ))
        }
    }

    // MARK: Bottom chrome

    private var bottomChrome: some View {
        VStack(spacing: 18) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(onboardingPages) { p in
                    let selected = p.id == pageIndex
                    Capsule()
                        .fill(selected ? page.accent : .white.opacity(0.22))
                        .frame(width: selected ? 28 : 8, height: 8)
                        .overlay {
                            if selected {
                                Capsule()
                                    .fill(page.accent)
                                    .matchedGeometryEffect(id: "dot", in: dotNS)
                                    .blur(radius: 6)
                                    .opacity(0.55)
                            }
                        }
                        .animation(Theme.Motion.snappy, value: pageIndex)
                        .onTapGesture {
                            withAnimation(Theme.Motion.standard) { pageIndex = p.id }
                        }
                        .frame(minWidth: 20, minHeight: 28)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity)

            // Primary CTA
            Button {
                advance()
            } label: {
                ZStack {
                    LinearGradient(
                        colors: [page.accent, page.accent.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    HStack(spacing: 10) {
                        Text(isLast ? "Get started" : "Continue")
                            .font(.system(size: Theme.TypeRamp.cta, weight: .heavy, design: .rounded))
                        Image(systemName: isLast ? "arrow.right.circle.fill" : "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .symbolEffect(.bounce, value: pageIndex)
                    }
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.28), lineWidth: 0.7)
                )
                .shadow(color: page.accent.opacity(0.50), radius: 20, x: 0, y: 12)
            }
            .buttonStyle(PressBounceStyle(scale: 0.97))
            .animation(Theme.Motion.standard, value: pageIndex)

            if isLast {
                Text("Already have an account? Continue to sign in.")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                // Keep height stable
                Color.clear.frame(height: 16)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
    }

    // MARK: Actions

    private func advance() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if isLast {
            finish()
        } else if reduceMotion {
            pageIndex += 1
        } else {
            withAnimation(Theme.Motion.standard) { pageIndex += 1 }
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        OnboardingStore.hasCompleted = true
        onFinished()
    }
}

// MARK: - Grid overlay

private struct OnboardingGridOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let step: CGFloat = 42
                let drift = CGFloat(t.truncatingRemainder(dividingBy: Double(step)))
                var path = Path()
                var x: CGFloat = -step + drift
                while x < size.width + step {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = -step + drift * 0.6
                while y < size.height + step {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Illustrations

private struct OnboardingIllustration: View {
    let kind: OnboardingPage.Kind
    let accent: Color
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        ZStack {
            // Soft stage plate
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.10),
                            .white.opacity(0.03),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.28), radius: 28, y: 16)

            Group {
                switch kind {
                case .brand: BrandHeroArt(accent: accent, active: active && entered)
                case .scan: ScanHeroArt(accent: accent, active: active && entered)
                case .storm: StormHeroArt(accent: accent, active: active && entered)
                case .claim: ClaimHeroArt(accent: accent, active: active && entered)
                case .launch: LaunchHeroArt(accent: accent, active: active && entered)
                }
            }
            .padding(18)
            .scaleEffect(entered ? 1 : 0.92)
            .opacity(entered ? 1 : 0)
        }
        .onChange(of: active) { _, isActive in
            if isActive {
                if reduceMotion {
                    entered = true
                } else {
                    withAnimation(Theme.Motion.bouncy) { entered = true }
                }
            } else {
                entered = false
            }
        }
        .onAppear {
            if active {
                if reduceMotion {
                    entered = true
                } else {
                    withAnimation(Theme.Motion.bouncy.delay(0.05)) { entered = true }
                }
            }
        }
    }
}

// MARK: Brand — house silhouette + scan ring

private struct BrandHeroArt: View {
    let accent: Color
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0
            let pulse = 0.5 + 0.5 * sin(t * 1.6)
            ZStack {
                // Orbit rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(accent.opacity(0.18 - Double(i) * 0.04), lineWidth: 1.2)
                        .frame(width: 160 + CGFloat(i) * 48, height: 160 + CGFloat(i) * 48)
                        .scaleEffect(1 + 0.03 * CGFloat(pulse) * CGFloat(3 - i))
                }

                // Roof house mark
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 86, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, accent.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: accent.opacity(0.55), radius: 24, y: 8)
                    .symbolEffect(.pulse, options: .repeating, isActive: active)

                // Ember badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 7, height: 7)
                                .shadow(color: accent, radius: 6)
                            Text("LIVE SCAN")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .tracking(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
                        .colorScheme(.dark)
                        .offset(x: -12, y: -18)
                        .opacity(0.7 + 0.3 * pulse)
                    }
                }
            }
        }
    }
}

// MARK: Scan — phone + damage pins

private struct ScanHeroArt: View {
    let accent: Color
    let active: Bool

    private let pins: [(CGFloat, CGFloat, String)] = [
        (0.28, 0.32, "H"),
        (0.62, 0.40, "W"),
        (0.45, 0.58, "G"),
        (0.72, 0.62, "H"),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0
            let sweep = CGFloat((t.truncatingRemainder(dividingBy: 2.8)) / 2.8)

            ZStack {
                // Device frame
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.inkRaised, Theme.ink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 168, height: 250)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.25), lineWidth: 1.5)
                    )
                    .shadow(color: accent.opacity(0.35), radius: 30, y: 16)

                // Screen
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.18, blue: 0.32),
                                Color(red: 0.08, green: 0.12, blue: 0.22),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 148, height: 228)
                    .overlay {
                        // Roof shingle pattern
                        VStack(spacing: 7) {
                            ForEach(0..<12, id: \.self) { row in
                                HStack(spacing: 5) {
                                    ForEach(0..<6, id: \.self) { col in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white.opacity(row % 2 == 0 ? 0.07 : 0.045))
                                            .frame(width: 18, height: 10)
                                            .offset(x: row % 2 == 0 ? 0 : 8)
                                    }
                                }
                            }
                        }
                        .mask(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                    }
                    .overlay(alignment: .top) {
                        // Scan line
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, accent.opacity(0.85), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .shadow(color: accent, radius: 8)
                            .offset(y: 16 + sweep * 196)
                            .opacity(active ? 1 : 0.4)
                    }
                    .overlay {
                        // Damage pins
                        GeometryReader { geo in
                            ForEach(Array(pins.enumerated()), id: \.offset) { idx, pin in
                                let reveal = max(0, min(1, (sweep - pin.1 + 0.15) * 5))
                                let pulse = 0.5 + 0.5 * sin(t * 2.4 + Double(idx))
                                ZStack {
                                    Circle()
                                        .fill(accent.opacity(0.25 * reveal))
                                        .frame(width: 28 + 6 * pulse, height: 28 + 6 * pulse)
                                    Circle()
                                        .fill(accent)
                                        .frame(width: 18, height: 18)
                                    Text(pin.2)
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .opacity(reveal)
                                .scaleEffect(0.7 + 0.3 * reveal)
                                .position(
                                    x: geo.size.width * pin.0,
                                    y: geo.size.height * pin.1
                                )
                            }
                        }
                        .clipShape(.rect(cornerRadius: 22))
                    }
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.mint).frame(width: 6, height: 6)
                            Text("4 markers · 92% conf")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 12)
                    }

                // Floating chips
                floatingChip(icon: "cloud.bolt.fill", label: "Hail 1.75\"", x: -118, y: -70, delay: 0)
                floatingChip(icon: "wind", label: "Wind 68 mph", x: 118, y: 40, delay: 0.4)
            }
        }
    }

    private func floatingChip(icon: String, label: String, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 20.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0
            let bob = CGFloat(sin(t * 1.5 + delay * 4)) * 6
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.6))
            .colorScheme(.dark)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .offset(x: x, y: y + bob)
        }
    }
}

// MARK: Storm — map card with pins

private struct StormHeroArt: View {
    let accent: Color
    let active: Bool

    private let storms: [(CGFloat, CGFloat, String, Color)] = [
        (0.30, 0.38, "H", Theme.crimson),
        (0.58, 0.30, "W", Theme.amber),
        (0.72, 0.55, "H", Theme.ember),
        (0.42, 0.62, "T", Theme.sky),
        (0.55, 0.72, "H", Theme.crimson),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0

            ZStack {
                // Map plate
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.20, blue: 0.34),
                                Color(red: 0.09, green: 0.13, blue: 0.24),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        // Fake roads
                        Canvas { context, size in
                            var roads = Path()
                            roads.move(to: CGPoint(x: 0, y: size.height * 0.35))
                            roads.addCurve(
                                to: CGPoint(x: size.width, y: size.height * 0.45),
                                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.2),
                                control2: CGPoint(x: size.width * 0.65, y: size.height * 0.55)
                            )
                            roads.move(to: CGPoint(x: size.width * 0.2, y: 0))
                            roads.addCurve(
                                to: CGPoint(x: size.width * 0.55, y: size.height),
                                control1: CGPoint(x: size.width * 0.25, y: size.height * 0.4),
                                control2: CGPoint(x: size.width * 0.7, y: size.height * 0.6)
                            )
                            context.stroke(roads, with: .color(.white.opacity(0.10)), lineWidth: 3)

                            // Blocks
                            for i in 0..<5 {
                                let rect = CGRect(
                                    x: size.width * (0.12 + CGFloat(i) * 0.15),
                                    y: size.height * (0.2 + CGFloat(i % 3) * 0.18),
                                    width: 28,
                                    height: 18
                                )
                                context.fill(
                                    Path(roundedRect: rect, cornerRadius: 3),
                                    with: .color(.white.opacity(0.05))
                                )
                            }
                        }
                    }
                    .overlay {
                        GeometryReader { geo in
                            // Impact rings
                            ForEach(Array(storms.enumerated()), id: \.offset) { idx, s in
                                let pulse = 0.5 + 0.5 * sin(t * 1.8 + Double(idx))
                                Circle()
                                    .stroke(s.3.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 48 + 10 * pulse, height: 48 + 10 * pulse)
                                    .position(x: geo.size.width * s.0, y: geo.size.height * s.1)

                                ZStack {
                                    Circle()
                                        .fill(s.3)
                                        .frame(width: 26, height: 26)
                                        .shadow(color: s.3.opacity(0.7), radius: 8)
                                    Text(s.2)
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .scaleEffect(0.92 + 0.08 * pulse)
                                .position(x: geo.size.width * s.0, y: geo.size.height * s.1)
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.bolt.rain.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(accent)
                            Text("Last 3 years · 128 events")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.6))
                        .colorScheme(.dark)
                        .padding(14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 11, weight: .bold))
                            Text("Door Knock")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                           startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                        .shadow(color: Theme.ember.opacity(0.45), radius: 12, y: 6)
                        .padding(14)
                        .scaleEffect(active ? 1 : 0.9)
                        .opacity(active ? 1 : 0.7)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: Claim — stacked cards

private struct ClaimHeroArt: View {
    let accent: Color
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 20.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0
            let bob = CGFloat(sin(t * 1.2)) * 4

            ZStack {
                cardLayer(
                    title: "Claim Packet",
                    subtitle: "12 photos · sealed",
                    icon: "doc.richtext.fill",
                    tint: Theme.sky,
                    width: 210,
                    offset: CGSize(width: -18, height: -36 + bob * 0.4),
                    rotation: -8
                )
                cardLayer(
                    title: "Scope of Work",
                    subtitle: "Full tear-off · Class 4",
                    icon: "list.bullet.clipboard.fill",
                    tint: Theme.amber,
                    width: 220,
                    offset: CGSize(width: 14, height: -4 - bob * 0.5),
                    rotation: 5
                )
                cardLayer(
                    title: "Proposal Ready",
                    subtitle: "$18,420 · Send to sign",
                    icon: "signature",
                    tint: accent,
                    width: 236,
                    offset: CGSize(width: 0, height: 42 + bob),
                    rotation: -2,
                    highlighted: true
                )
            }
        }
    }

    private func cardLayer(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        width: CGFloat,
        offset: CGSize,
        rotation: Double,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            if highlighted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.mint)
            }
        }
        .padding(14)
        .frame(width: width)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    highlighted
                        ? LinearGradient(colors: [tint.opacity(0.8), tint.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: highlighted ? 1.2 : 0.7
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .colorScheme(.dark)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
    }
}

// MARK: Launch — crest + checklist

private struct LaunchHeroArt: View {
    let accent: Color
    let active: Bool

    private let steps = [
        ("1", "Add your first lead", Theme.sky),
        ("2", "Run a roof scan", Theme.ember),
        ("3", "Send the proposal", Theme.mint),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 20.0 : 1.0)) { ctx in
            let t = active ? ctx.date.timeIntervalSinceReferenceDate : 0
            let pulse = 0.5 + 0.5 * sin(t * 1.5)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18 + 0.08 * pulse))
                        .frame(width: 110, height: 110)
                        .blur(radius: 2)
                    Circle()
                        .stroke(accent.opacity(0.45), lineWidth: 2)
                        .frame(width: 96, height: 96)
                        .scaleEffect(1 + 0.06 * pulse)
                    Image("LogoMark")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .shadow(color: accent.opacity(0.5), radius: 16)
                }

                VStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        let delay = Double(idx) * 0.35
                        let reveal = active
                            ? max(0, min(1, (sin(t * 0.9 - delay) + 1) / 2 * 1.4 - 0.2))
                            : 1
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(step.2.opacity(0.22))
                                    .frame(width: 32, height: 32)
                                Text(step.0)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(step.2)
                            }
                            Text(step.1)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(step.2)
                                .opacity(0.55 + 0.45 * reveal)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.12), lineWidth: 0.6)
                        )
                        .opacity(0.55 + 0.45 * reveal)
                        .offset(x: (1 - reveal) * 12)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
