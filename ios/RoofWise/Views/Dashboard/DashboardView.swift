import SwiftUI

struct DashboardView: View {
    var onQuickInspection: () -> Void = {}
    var onOpenTraining: () -> Void = {}
    var onOpenLeads: () -> Void = {}
    var onOpenLeadsStage: (JobPipelineStage?) -> Void = { _ in }

    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    DashboardHeader()
                    KPIStrip(onQuickInspection: onQuickInspection)
                    StormAlertHero(onView: onOpenLeads)
                    RecentJobsHomeSection(
                        onSeeAll: onOpenLeads,
                        onOpenJob: { _ in onOpenLeads() }
                    )
                    PipelineMiniSection(
                        onOpenBoard: { onOpenLeadsStage(nil) },
                        onTapStage: { stage in onOpenLeadsStage(stage.mappedStage) }
                    )
                    TodaysGoalsCard()
                    LeaderboardCard()
                    RecentWinsCard()
                    HomeCardsCarousel(onOpenTraining: onOpenTraining)
                    CoachingActivityCard(onOpenTraining: onOpenTraining)
                    StormAlertSubscriptionCard()
                    PipelineCard()
                    ScheduleCard()
                    RecentJobsRow(onOpenCustomer: { id in path.append(id) })
                    AIInsightsCard()
                    Color.clear.frame(height: 120)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationDestination(for: UUID.self) { id in
                CustomerProfileView(customerID: id)
            }
        }
    }
}

// MARK: - Header

struct DashboardHeader: View {
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

            Spacer()

            iconButton(systemName: "magnifyingglass")
            iconButton(systemName: "bell.fill", badge: true)
        }
        .padding(.horizontal, 20)
    }

    private func iconButton(systemName: String, badge: Bool = false) -> some View {
        Button {} label: {
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
