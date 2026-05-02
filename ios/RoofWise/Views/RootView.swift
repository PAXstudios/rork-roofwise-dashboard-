import SwiftUI

enum AppTab: Int, CaseIterable {
    case home, leads, map, plan
    var title: String {
        switch self {
        case .home: return "Home"
        case .leads: return "Leads"
        case .map: return "Map"
        case .plan: return "Plan"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .leads: return "person.2.fill"
        case .map: return "map.fill"
        case .plan: return "calendar"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showQuickAction = false
    @State private var showInspection = false
    @State private var showMileage = false
    @State private var customerStore = CustomerStore()

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .home: DashboardView(onQuickInspection: { showInspection = true })
                case .leads: LeadsView()
                case .map: MapHubView()
                case .plan: PlanView()
                }
            }
            .safeAreaPadding(.bottom, 96)

            BottomTabBar(tab: $tab) { showQuickAction = true }
        }
        .sheet(isPresented: $showQuickAction) {
            QuickActionSheet(onStartInspection: {
                showQuickAction = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showInspection = true
                }
            }, onOpenMileage: {
                showQuickAction = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showMileage = true
                }
            })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showInspection) {
            QuickInspectionView()
        }
        .sheet(isPresented: $showMileage) {
            MileageTrackerView()
                .presentationDragIndicator(.visible)
        }
        .environment(customerStore)
    }
}

// MARK: - Tab Bar

struct BottomTabBar: View {
    @Binding var tab: AppTab
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home)
            tabItem(.leads)
            plusButton
            tabItem(.map)
            tabItem(.plan)
        }
        .padding(.horizontal, 14)
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
        Button {
            withAnimation(.spring(duration: 0.3)) { tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(t.title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tab == t ? Theme.ember : Theme.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
