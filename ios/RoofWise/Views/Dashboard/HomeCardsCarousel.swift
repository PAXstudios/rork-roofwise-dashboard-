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
        case lesson, alert, tasks, daily, sales
        var id: Int { rawValue }
    }

    @State private var currentPage: Page? = .lesson

    private let sideInset: CGFloat = 20
    private let peek: CGFloat = 18
    private let spacing: CGFloat = 12
    private let cardHeight: CGFloat = 360

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let cardWidth = max(0, geo.size.width - (sideInset * 2) - peek)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        carouselCard(.lesson) {
                            TodaysLessonCard(onOpenTraining: onOpenTraining, embedded: true)
                        }
                        .frame(width: cardWidth)

                        carouselCard(.alert) {
                            StormAlertCard(embedded: true)
                        }
                        .frame(width: cardWidth)

                        carouselCard(.tasks) {
                            TasksAndActivityCard(embedded: true)
                        }
                        .frame(width: cardWidth)

                        carouselCard(.daily) {
                            DailySummaryCard(embedded: true)
                        }
                        .frame(width: cardWidth)

                        carouselCard(.sales) {
                            SalesMetricsCard(embedded: true)
                        }
                        .frame(width: cardWidth)
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

    @ViewBuilder
    private func carouselCard<Content: View>(_ page: Page, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: cardHeight)
        .id(page)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases) { page in
                Capsule()
                    .fill(page == (currentPage ?? .lesson) ? Theme.ink : Theme.hairline)
                    .frame(width: page == (currentPage ?? .lesson) ? 18 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: currentPage)
            }
        }
        .padding(.top, 2)
    }
}
