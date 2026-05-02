import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Horizontally scrolling carousel of the six primary Home overview cards.
/// Snaps one card per swipe, peeks the next card on the right, and shows a
/// page indicator beneath the row.
struct HomeCardsCarousel: View {
    var onOpenTraining: () -> Void = {}

    private enum Page: Int, CaseIterable, Identifiable, Hashable {
        case alert, sales, daily, storm, lesson, tasks
        var id: Int { rawValue }
    }

    @State private var currentPage: Page? = .alert

    private let sideInset: CGFloat = 20
    private let peek: CGFloat = 18
    private let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let cardWidth = max(0, geo.size.width - (sideInset * 2) - peek)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        StormAlertCard(embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.alert)

                        SalesMetricsCard(embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.sales)

                        DailySummaryCard(embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.daily)

                        StormHistoryMapCard(embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.storm)

                        TodaysLessonCard(onOpenTraining: onOpenTraining, embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.lesson)

                        TasksAndActivityCard(embedded: true)
                            .frame(width: cardWidth)
                            .id(Page.tasks)
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, sideInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $currentPage, anchor: .leading)
                .onChange(of: currentPage) { _, _ in
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
            }
            .frame(height: cardHeight)

            pageDots
        }
    }

    private var cardHeight: CGFloat {
        switch currentPage ?? .alert {
        case .alert: return 280
        case .sales: return 430
        case .daily: return 380
        case .storm: return 520
        case .lesson: return 320
        case .tasks: return 460
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases) { page in
                Capsule()
                    .fill(page == (currentPage ?? .alert) ? Theme.ink : Theme.hairline)
                    .frame(width: page == (currentPage ?? .alert) ? 18 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: currentPage)
            }
        }
        .padding(.top, 2)
    }
}
