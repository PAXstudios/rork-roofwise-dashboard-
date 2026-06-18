import SwiftUI

enum AppTab: Int, CaseIterable {
    case home, leads, map, plan, training
    var title: String {
        switch self {
        case .home: return "Home"
        case .leads: return "Leads"
        case .map: return "Map"
        case .plan: return "Plan"
        case .training: return "Train"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .leads: return "person.2.fill"
        case .map: return "map.fill"
        case .plan: return "calendar"
        case .training: return "graduationcap.fill"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var previousTab: AppTab = .home
    @State private var showQuickAction = false
    @State private var showInspection = false
    @State private var showInspectionChooser = false
    @State private var showMileage = false
    @State private var showNewLead = false
    @State private var customerStore = CustomerStore()
    @State private var trainingProgress = TrainingProgressStore()
    @State private var leadsFilter: JobPipelineStage? = nil
    @State private var auth = AuthStore.shared
    @State private var leadsSync = LeadsSyncService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !APIKeys.requireAuth {
                // Dev bypass: boot straight into the dashboard regardless of
                // auth state. Flip APIKeys.requireAuth to true to restore the
                // full Welcome / sign-in gate.
                signedInBody
                    .transition(.opacity)
            } else {
                switch auth.state {
                case .unknown:
                    LaunchSplashView()
                case .signedOut:
                    WelcomeView()
                        .transition(.opacity)
                case .signedIn:
                    signedInBody
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stateKey)
    }

    /// Switches tabs with a spring, remembering the prior tab so the content
    /// transition can slide in the correct horizontal direction.
    private func selectTab(_ t: AppTab) {
        guard t != tab else { return }
        previousTab = tab
        withAnimation(Theme.Motion.standard) { tab = t }
    }

    /// Asymmetric slide based on travel direction across the tab order.
    private var tabTransition: AnyTransition {
        let forward = tab.rawValue >= previousTab.rawValue
        let insertEdge: Edge = forward ? .trailing : .leading
        let removeEdge: Edge = forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertEdge).combined(with: .opacity),
            removal: .move(edge: removeEdge).combined(with: .opacity)
        )
    }

    private var stateKey: Int {
        switch auth.state {
        case .unknown: return 0
        case .signedOut: return 1
        case .signedIn: return 2
        }
    }

    private var signedInBody: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .home: DashboardView(
                    onOpenTraining: { selectTab(.training) },
                    onOpenLeads: {
                        leadsFilter = nil
                        selectTab(.leads)
                    },
                    onOpenLeadsStage: { stage in
                        leadsFilter = stage
                        selectTab(.leads)
                    }
                )
                case .leads: LeadsView(filter: $leadsFilter)
                case .map: MapHubView()
                case .plan: PlanView()
                case .training: TrainingView()
                }
            }
            .id(tab)
            .transition(tabTransition)
            .safeAreaPadding(.bottom, 96)

            BottomTabBar(tab: $tab, onSelect: { selectTab($0) }) { showQuickAction = true }
        }
        .sheet(isPresented: $showQuickAction) {
            QuickActionSheet(onStartInspection: {
                showQuickAction = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showInspectionChooser = true
                }
            }, onOpenMileage: {
                showQuickAction = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showMileage = true
                }
            }, onNewLead: {
                showQuickAction = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewLead = true
                }
            })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showInspection) {
            QuickInspectionView()
        }
        .fullScreenCover(isPresented: $showNewLead) {
            NewJobWizard()
        }
        .sheet(isPresented: $showInspectionChooser) {
            InspectionTargetChooserSheet(onProceed: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showInspection = true
                }
            })
            .environment(customerStore)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMileage) {
            MileageTrackerView()
                .presentationDragIndicator(.visible)
        }
        .environment(customerStore)
        .environment(trainingProgress)
        .task {
            leadsSync.attach(customerStore)
            await leadsSync.syncNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await leadsSync.syncNow() }
            }
        }
    }
}

/// Minimal launch splash shown while we hydrate the persisted Supabase session.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink, Theme.inkRaised],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                ProgressView().tint(.white)
            }
        }
    }
}

// MARK: - Tab Bar

struct BottomTabBar: View {
    @Binding var tab: AppTab
    var onSelect: (AppTab) -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home)
            tabItem(.leads)
            plusButton
            tabItem(.map)
            tabItem(.plan)
            tabItem(.training)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            Theme.card
                .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
                .shadow(color: Theme.ink.opacity(0.08), radius: 18, x: 0, y: -4)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabItem(_ t: AppTab) -> some View {
        let selected = tab == t
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onSelect(t)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                    .scaleEffect(selected ? 1.12 : 1.0)
                Text(t.title)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.ember : Theme.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .animation(Theme.Motion.snappy, value: selected)
        }
        .buttonStyle(.plain)
    }

    private var plusButton: some View {
        Button(action: onPlus) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .shadow(color: Theme.ember.opacity(0.45), radius: 14, x: 0, y: 8)
            .offset(y: -18)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick Action Sheet

struct QuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onStartInspection: () -> Void = {}
    var onOpenMileage: () -> Void = {}
    var onNewLead: () -> Void = {}
    private let actions: [(String, String, Color)] = [
        ("New Lead", "person.crop.circle.badge.plus", Theme.sky),
        ("Start Inspection", "binoculars.fill", Theme.ember),
        ("Capture Damage Photo", "camera.viewfinder", Theme.amber),
        ("Track Mileage", "car.fill", Theme.mint),
        ("File Storm Claim", "cloud.bolt.rain.fill", Theme.crimson),
        ("Schedule Crew", "hammer.fill", Theme.inkSoft),
        ("New Estimate", "doc.text.fill", Theme.amber)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Actions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Capture work in seconds — synced with the field.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.bottom, 8)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(actions, id: \.0) { item in
                        Button {
                            if item.0 == "Start Inspection" || item.0 == "Capture Damage Photo" {
                                onStartInspection()
                            } else if item.0 == "Track Mileage" {
                                onOpenMileage()
                            } else if item.0 == "New Lead" {
                                onNewLead()
                            } else {
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                ZStack {
                                    Circle().fill(item.2.opacity(0.14))
                                    Image(systemName: item.1)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(item.2)
                                }
                                .frame(width: 42, height: 42)
                                Text(item.0)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Theme.card, in: .rect(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
    }
}

#Preview { RootView() }
