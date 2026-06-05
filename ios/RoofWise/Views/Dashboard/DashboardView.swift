import SwiftUI

struct DashboardView: View {
    var onQuickInspection: () -> Void = {}
    var onOpenTraining: () -> Void = {}
    var onOpenLeads: () -> Void = {}
    var onOpenLeadsStage: (JobPipelineStage?) -> Void = { _ in }

    @State private var path: [DashboardRoute] = []
    @State private var serviceAreaStore = ServiceAreaStore.shared
    @State private var alertStore = StormAlertStore.shared
    @State private var pushRouter = PushAlertRouter.shared
    @State private var showMileage = false
    @State private var showLiveAR = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    DashboardHeader(onOpenSettings: { path.append(.settings) })
                    if !serviceAreaStore.hasConfiguredServiceArea {
                        ServiceAreaBanner(onConfigure: { path.append(.serviceArea) })
                            .padding(.horizontal, 18)
                    } else {
                        StormPushPermissionBanner()
                            .padding(.horizontal, 18)
                    }
                    KPIStrip(onQuickInspection: onQuickInspection)
                    if APIKeys.useLiveARAnalysis {
                        LiveARInspectCTA(onTap: { showLiveAR = true })
                            .padding(.horizontal, 18)
                    }
                    MileageSummaryCard(onOpen: { showMileage = true })
                    StormAlertHero(
                        alert: alertStore.latestActiveAlert,
                        onView: {
                            if let a = alertStore.latestActiveAlert {
                                routeToImpactedMap(for: a)
                            } else {
                                onOpenLeads()
                            }
                        }
                    )
                    WeatherTile()
                    RecentJobsHomeSection(
                        onSeeAll: onOpenLeads,
                        onOpenJob: { _ in onOpenLeads() }
                    )
                    SavedEstimatesSection()
                    PipelineMiniSection(
                        onOpenBoard: { onOpenLeadsStage(nil) },
                        onTapStage: { stage in onOpenLeadsStage(stage.mappedStage) }
                    )
                    TodaysGoalsCard()
                    LeaderboardCard()
                    RecentWinsCard()
                    AICalibrationCard()
                    HomeCardsCarousel(onOpenTraining: onOpenTraining)
                    CoachingActivityCard(onOpenTraining: onOpenTraining)
                    StormAlertSubscriptionCard()
                    PipelineCard()
                    ScheduleCard()
                    RecentJobsRow(onOpenCustomer: { id in path.append(.customer(id)) })
                    AIInsightsCard()
                    Color.clear.frame(height: 120)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .customer(let id): CustomerProfileView(customerID: id)
                case .serviceArea: ServiceAreaView()
                case .settings: SettingsHubView()
                case .pushSettings: PushNotificationSettingsView()
                case .stormImpact(let alertId):
                    if let alert = StormAlertStore.shared.alerts.first(where: { $0.id == alertId }) {
                        MapHubView(
                            focusedStorm: alert.asPinEvent,
                            initialRadiusFilterMiles: 5
                        )
                    } else {
                        MapHubView()
                    }
                }
            }
        }
        .sheet(isPresented: $showMileage) {
            MileageTrackerView()
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showLiveAR) {
            LiveARInspectionView(onClose: { showLiveAR = false })
        }
        .onChange(of: pushRouter.pendingAlertId) { _, newId in
            guard let newId else { return }
            if let match = StormAlertStore.shared.alerts.first(where: { $0.id == newId }) {
                routeToImpactedMap(for: match)
            }
            pushRouter.clear()
        }
    }

    /// Single helper used by both the hero CTA and PushAlertRouter so push-tap
    /// and in-app tap converge on the same destination.
    private func routeToImpactedMap(for alert: StormAlert) {
        alertStore.markRead(id: alert.id)
        alertStore.markActedOn(id: alert.id)
        path.append(.stormImpact(alert.id))
    }
}

/// Home CTA that launches the Live AR Damage Detection experience.
/// Navy primary button per the pitch-deck spec, gated by `APIKeys.useLiveARAnalysis`.
struct LiveARInspectCTA: View {
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.16))
                    Image(systemName: "arkit")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live AR Inspect")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Real-time AI damage overlay")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(Theme.inkGradient, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 0.6))
            .shadow(color: Theme.ink.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

enum DashboardRoute: Hashable {
    case customer(UUID)
    case serviceArea
    case settings
    case pushSettings
    case stormImpact(UUID)
}

struct ServiceAreaBanner: View {
    var onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.amberSoft)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SET YOUR SERVICE AREA")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text("Set your service area to enable storm alerts")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            Button(action: onConfigure) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Configure now")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.amberSoft, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.amber.opacity(0.5), lineWidth: 0.8))
    }
}

// MARK: - Header

struct DashboardHeader: View {
    var onOpenSettings: () -> Void = {}

    #if DEBUG
    @State private var debugLongPressCount: Int = 0
    @State private var debugLongPressFirstAt: Date?
    @State private var debugStormToast: Bool = false
    #endif

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                                             startPoint: .top, endPoint: .bottom))
                Text("AC")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Circle().fill(Theme.mint)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                    .offset(x: 16, y: 16)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome back")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                Text("Alex Coleman")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            #if DEBUG
            .contentShape(.rect)
            .onLongPressGesture(minimumDuration: 0.45) { handleDebugLongPress() }
            .overlay(alignment: .bottomLeading) {
                if debugStormToast {
                    Text("Mock storm injected")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.ember, in: .capsule)
                        .offset(y: 22)
                        .transition(.opacity)
                }
            }
            #endif

            Spacer()

            if !APIKeys.requireAuth {
                Text("DEV MODE — auth disabled")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.hairline, in: .rect(cornerRadius: 12))
                    .accessibilityLabel("Developer mode, authentication disabled")
            }

            // P2 audit: search/bell icons removed — no destinations existed and
            // dead controls violate glove rules. Settings stays as the sole header CTA.
            iconButton(systemName: "gearshape.fill", action: {
                ActivityStore.shared.logTap(target: "DashboardHeader.settings")
                onOpenSettings()
            })
        }
        .padding(.horizontal, 20)
    }

    #if DEBUG
    private func handleDebugLongPress() {
        let now = Date()
        if let first = debugLongPressFirstAt, now.timeIntervalSince(first) > 4 {
            debugLongPressCount = 0
            debugLongPressFirstAt = nil
        }
        if debugLongPressFirstAt == nil { debugLongPressFirstAt = now }
        debugLongPressCount += 1
        if debugLongPressCount >= 3 {
            debugLongPressCount = 0
            debugLongPressFirstAt = nil
            _ = StormWatchService.shared.injectMockStorm()
            withAnimation { debugStormToast = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation { debugStormToast = false }
            }
        }
    }
    #endif

    private func iconButton(systemName: String, badge: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(Theme.card)
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))

                if badge {
                    Circle()
                        .fill(Theme.ember)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
