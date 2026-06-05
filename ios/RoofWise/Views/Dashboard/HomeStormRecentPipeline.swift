import SwiftUI

// Glove-friendly home sections inserted between the Overview hero pair
// and the Today's Lesson area.
//
// Touch targets ≥56pt, ≥12pt spacing between tappable elements, no thin
// affordances, high contrast for outdoor sun, big primary CTAs.

// MARK: - Models (mock-only)

struct HomeJobStage {
    let label: String
    let color: Color
}

enum HomeJobStageType: CaseIterable {
    case inspectionDone, estimateSent, approved, inProgress, completed

    var stage: HomeJobStage {
        switch self {
        case .inspectionDone: return .init(label: "Inspection Done", color: Theme.sky)
        case .estimateSent:   return .init(label: "Estimate Sent",
                                           color: Color(red: 0.55, green: 0.30, blue: 0.85))
        case .approved:       return .init(label: "Approved", color: Theme.mint)
        case .inProgress:     return .init(label: "In Progress", color: Theme.ember)
        case .completed:      return .init(label: "Completed",
                                           color: Color(red: 0.10, green: 0.62, blue: 0.62))
        }
    }
}

struct HomeRecentJob: Identifiable {
    let id = UUID()
    let customerName: String
    let address: String
    let stageType: HomeJobStageType
    let damageScore: Int
    let imageURL: String

    var damageColor: Color {
        switch damageScore {
        case 0...30:  return Theme.crimson
        case 31...60: return Theme.ember
        default:      return Theme.mint
        }
    }
}

struct HomePipelineStage: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
    let count: Int
    let mappedStage: JobPipelineStage?
}

enum HomeSectionsMock {
    static let stormAlertActive: Bool = true

    static let recentJobs: [HomeRecentJob] = [
        .init(customerName: "Coleman Family",
              address: "1247 Oakridge Ln · Plano",
              stageType: .completed,
              damageScore: 88,
              imageURL: "https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=900"),
        .init(customerName: "Mia & Tom Smith",
              address: "445 Pine Lane · Frisco",
              stageType: .inProgress,
              damageScore: 64,
              imageURL: "https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=900"),
        .init(customerName: "Hawthorn Estate",
              address: "88 Maple Cove · McKinney",
              stageType: .approved,
              damageScore: 72,
              imageURL: "https://images.unsplash.com/photo-1605276374104-dee2a0ed3cd6?w=900"),
        .init(customerName: "Patel Residence",
              address: "5501 Stonebriar Pkwy · Frisco",
              stageType: .estimateSent,
              damageScore: 54,
              imageURL: "https://images.unsplash.com/photo-1518780664697-55e3ad937233?w=900"),
        .init(customerName: "Riverside Townhomes",
              address: "2210 Custer Pkwy · Plano",
              stageType: .inProgress,
              damageScore: 41,
              imageURL: "https://images.unsplash.com/photo-1597047084897-51e81819a499?w=900"),
        .init(customerName: "Nguyen Residence",
              address: "312 Eldorado Pkwy · McKinney",
              stageType: .inspectionDone,
              damageScore: 22,
              imageURL: "https://images.unsplash.com/photo-1564501049412-61c2a3083791?w=900")
    ]

    static func pipeline() -> [HomePipelineStage] {
        // Mocked from existing leads/jobs feel; always returns 8 chips even at 0.
        [
            .init(label: "NEW LEAD",   color: Theme.inkFaint, count: 18, mappedStage: .knocked),
            .init(label: "CONTACTED",  color: Theme.sky,       count: 12, mappedStage: .interested),
            .init(label: "INSP SCHED", color: Theme.amber,     count: 7,  mappedStage: .inspectionScheduled),
            .init(label: "INSP DONE",  color: Theme.amber,     count: 5,  mappedStage: .inspectionComplete),
            .init(label: "ESTIMATE",   color: Color(red: 0.55, green: 0.30, blue: 0.85),
                  count: 6, mappedStage: .recapSent),
            .init(label: "APPROVED",   color: Theme.mint,      count: 4,  mappedStage: .approved),
            .init(label: "INSTALL",    color: Theme.ember,     count: 3,  mappedStage: .materialOrdered),
            .init(label: "PAID",       color: Color(red: 0.10, green: 0.55, blue: 0.35),
                  count: 9, mappedStage: .paid)
        ]
    }
}

// MARK: - 1. Storm Alert Hero (dynamic, Phase 6D)

struct StormAlertHero: View {
    /// Optional explicit alert. When nil, the hero observes
    /// `StormAlertStore.shared.latestActiveAlert` and renders dynamically.
    var alert: StormAlert? = nil
    var onView: () -> Void = {}
    var onSnooze: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var store = StormAlertStore.shared
    @State private var showDismissConfirm: Bool = false
    @State private var pulse: Bool = false

    private var resolvedAlert: StormAlert? { alert ?? store.latestActiveAlert }

    var body: some View {
        Group {
            if let a = resolvedAlert {
                ZStack(alignment: .topTrailing) {
                    cardBody(for: a)
                    dismissXButton
                }
                .contentShape(.rect)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    onView()
                }
                .onLongPressGesture(minimumDuration: 1.0) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showDismissConfirm = true
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.22), value: a.id)
                .confirmationDialog(
                    "Dismiss alert",
                    isPresented: $showDismissConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Dismiss", role: .destructive) {
                        StormAlertStore.shared.dismiss(id: a.id)
                        onDismiss?()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Hide this storm alert from Home. New alerts will still come through.")
                }
            }
        }
    }

    private var dismissXButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            showDismissConfirm = true
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.18))
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.8))
                Image(systemName: "xmark")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .frame(width: 56, height: 56) // 56×56 hit target around the visual
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityLabel("Dismiss alert")
    }

    // MARK: - Card

    private func cardBody(for a: StormAlert) -> some View {
        let theme = HeroTheme.theme(for: a.eventType)
        return ZStack(alignment: .leading) {
            LinearGradient(colors: theme.gradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            Canvas { ctx, size in
                let blobs: [(CGFloat, CGFloat, CGFloat, Double)] = [
                    (size.width * 0.20, size.height * 0.30, 80, 0.07),
                    (size.width * 0.55, size.height * 0.20, 110, 0.09),
                    (size.width * 0.85, size.height * 0.55, 100, 0.06),
                    (size.width * 0.30, size.height * 0.75, 90, 0.05)
                ]
                for b in blobs {
                    let rect = CGRect(x: b.0 - b.2, y: b.1 - b.2,
                                      width: b.2 * 2, height: b.2 * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(b.3)))
                }
                var bolt = Path()
                bolt.move(to: CGPoint(x: size.width * 0.78, y: size.height * 0.18))
                bolt.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.48))
                bolt.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.50))
                bolt.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.86))
                ctx.stroke(bolt,
                           with: .color(.white.opacity(0.10)),
                           style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            .allowsHitTesting(false)

            Rectangle()
                .fill(theme.accent)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 7, height: 7)
                            .scaleEffect(pulse ? 1.0 : 0.55)
                            .shadow(color: theme.accent.opacity(pulse ? 0.0 : 0.7),
                                    radius: pulse ? 7 : 0)
                        Text(theme.badge)
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white, in: .capsule)
                    .scaleEffect(pulse ? 1.03 : 1.0)
                    .onAppear {
                        guard !pulse else { return }
                        withAnimation(Theme.Motion.pulse) { pulse = true }
                    }
                    Spacer(minLength: 0)
                    Text(a.eventDate.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(a.propertyCount) \(a.propertyCount == 1 ? "property" : "properties") impacted")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(subtitle(for: a))
                        .font(.system(size: Theme.TypeRamp.body, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }

                // Primary CTA — full-width 64pt
                HStack(spacing: 8) {
                    Spacer()
                    Text("View Impacted Properties")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "arrow.right")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(.white, in: .capsule)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("View impacted properties for \(a.areaLabel)")

                // Secondary glove-friendly affordance: snooze (dismiss is now
                // the top-right X + long-press confirm flow, per Phase 6D).
                secondaryButton("Snooze 4h", icon: "moon.zzz.fill") {
                    let until = Date().addingTimeInterval(4 * 3600)
                    StormAlertStore.shared.snooze(id: a.id, until: until)
                    onSnooze?()
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.vertical, 22)
        }
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private func secondaryButton(_ label: String,
                                 icon: String,
                                 action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                Text(label)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white.opacity(0.14), in: .capsule)
            .overlay(
                Capsule().stroke(.white.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for a: StormAlert) -> String {
        let mag: String
        switch a.eventType {
        case .hail:
            mag = a.magnitudeIn.map { String(format: "%.2f″ hail", $0) } ?? "Hail"
        case .wind:
            mag = a.windMph.map { "\($0) mph wind" } ?? "High wind"
        case .tornado:
            mag = "Tornado"
        }
        let dist = String(format: "%.1f mi", a.distanceMi)
        return "\(mag) · \(dist) · \(a.areaLabel)"
    }

    // MARK: - Per-event-type theme

    private struct HeroTheme {
        let badge: String
        let accent: Color
        let gradient: [Color]

        static func theme(for kind: StormEventType) -> HeroTheme {
            switch kind {
            case .hail:
                return HeroTheme(
                    badge: "SEVERE HAIL WARNING",
                    accent: Theme.ember,
                    gradient: [
                        Color(red: 0.05, green: 0.09, blue: 0.20),
                        Color(red: 0.10, green: 0.16, blue: 0.32),
                        Color(red: 0.16, green: 0.22, blue: 0.40)
                    ]
                )
            case .wind:
                return HeroTheme(
                    badge: "HIGH WIND ALERT",
                    accent: Theme.amber,
                    gradient: [
                        Color(red: 0.10, green: 0.13, blue: 0.22),
                        Color(red: 0.18, green: 0.20, blue: 0.30),
                        Color(red: 0.28, green: 0.24, blue: 0.30)
                    ]
                )
            case .tornado:
                return HeroTheme(
                    badge: "TORNADO WARNING",
                    accent: Theme.crimson,
                    gradient: [
                        Color(red: 0.16, green: 0.06, blue: 0.10),
                        Color(red: 0.26, green: 0.10, blue: 0.16),
                        Color(red: 0.36, green: 0.14, blue: 0.20)
                    ]
                )
            }
        }
    }
}

// MARK: - 2. Recent Jobs (home variant)

struct RecentJobsHomeSection: View {
    var onSeeAll: () -> Void = {}
    var onOpenJob: (HomeRecentJob) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row 56pt
            HStack(spacing: 12) {
                Text("Recent Jobs")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onSeeAll) {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(Theme.ember)
                    .frame(minWidth: 56, minHeight: 56)
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(HomeSectionsMock.recentJobs) { job in
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            onOpenJob(job)
                        } label: {
                            RecentJobHomeCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct RecentJobHomeCard: View {
    let job: HomeRecentJob

    // Card 240×220, photo top 60% (132pt), bottom info ~88pt
    var body: some View {
        VStack(spacing: 0) {
            // Photo with scrim + address overlay
            Color(.secondarySystemBackground)
                .frame(width: 240, height: 132)
                .overlay {
                    AsyncImage(url: URL(string: job.imageURL)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            ZStack {
                                LinearGradient(colors: [Theme.ink.opacity(0.65), Theme.inkSoft],
                                               startPoint: .top, endPoint: .bottom)
                                Image(systemName: "house.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 64)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(job.address)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }

            // Info block
            VStack(alignment: .leading, spacing: 8) {
                Text(job.customerName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Status pill
                    let s = job.stageType.stage
                    HStack(spacing: 5) {
                        Circle().fill(.white).frame(width: 5, height: 5)
                        Text(s.label)
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.4)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(s.color, in: .capsule)

                    Spacer(minLength: 4)

                    // Damage score chip
                    HStack(spacing: 4) {
                        Image(systemName: "drop.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(job.damageScore)")
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(job.damageColor, in: .capsule)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 240, height: 88, alignment: .topLeading)
            .background(Theme.card)
            .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        }
        .frame(width: 240, height: 220)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 0.6)
        )
        .shadow(color: Theme.ink.opacity(0.10), radius: 12, x: 0, y: 6)
        .contentShape(.rect(cornerRadius: 16))
    }
}

// MARK: - 3. Pipeline Mini

struct PipelineMiniSection: View {
    var onOpenBoard: () -> Void = {}
    var onTapStage: (HomePipelineStage) -> Void = { _ in }

    private let stages = HomeSectionsMock.pipeline()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Pipeline")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onOpenBoard) {
                    HStack(spacing: 4) {
                        Text("Open board")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(Theme.ember)
                    .frame(minWidth: 56, minHeight: 56)
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stages) { stage in
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            onTapStage(stage)
                        } label: {
                            PipelineMiniChip(stage: stage)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct PipelineMiniChip: View {
    let stage: HomePipelineStage

    var body: some View {
        HStack(spacing: 0) {
            // 4pt color bar
            Rectangle()
                .fill(stage.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.label)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(stage.count)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 110, height: 84, alignment: .leading)
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 0.6)
        )
        .shadow(color: Theme.ink.opacity(0.06), radius: 8, x: 0, y: 3)
        .contentShape(.rect(cornerRadius: 16))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            StormAlertHero()
            RecentJobsHomeSection()
            PipelineMiniSection()
        }
        .padding(.vertical, 24)
    }
    .background(Theme.canvas)
}

