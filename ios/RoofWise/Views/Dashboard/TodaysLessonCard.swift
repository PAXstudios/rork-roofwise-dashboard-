import SwiftUI

/// Surfaces the rep's recommended micro-lesson for the day, biased toward
/// their weakest skill area (pulled from Role-Play Coach scores). Rotates
/// daily and skips lessons completed in the last 7 days.
struct TodaysLessonCard: View {
    @Environment(TrainingProgressStore.self) private var progress
    var onOpenTraining: () -> Void = {}

    @State private var presented: Lesson? = nil

    var body: some View {
        Group {
            if let lesson = progress.recommendedDailyLesson() {
                content(for: lesson)
            } else {
                allCaughtUp
            }
        }
        .padding(.horizontal, 18)
        .sheet(item: $presented) { lesson in
            @Bindable var bindable = progress
            LessonDetailView(lesson: lesson, progress: bindable)
        }
    }

    // MARK: - Lesson Card

    private func content(for lesson: Lesson) -> some View {
        Button { presented = lesson } label: {
            VStack(alignment: .leading, spacing: 14) {
                header(for: lesson)
                title(for: lesson)
                metaRow(for: lesson)
                ctaRow(for: lesson)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                LinearGradient(colors: [Theme.card, Theme.canvas],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(lesson.category.tint.opacity(0.35), lineWidth: 0.8)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(lesson.category.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(lesson.category.tint.opacity(0.12), in: .capsule)
                    .padding(14)
            }
            .shadow(color: lesson.category.tint.opacity(0.10), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func header(for lesson: Lesson) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [lesson.category.tint, lesson.category.tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: lesson.category.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Lesson")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Text(reasonLabel(lesson.category))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(lesson.category.tint)
                    .lineLimit(1)
            }
            Spacer()
            if progress.isComplete(lesson.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.mint)
            }
        }
    }

    private func title(for lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson.title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text(lesson.summary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
    }

    private func metaRow(for lesson: Lesson) -> some View {
        HStack(spacing: 8) {
            metaPill(icon: "clock", text: "\(lesson.durationMinutes) min read")
            metaPill(icon: "chart.bar.fill", text: lesson.difficulty)
            if let last = progress.lastCoachScore {
                metaPill(icon: "mic.fill", text: "Last score \(last)")
            }
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.canvas, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func ctaRow(for lesson: Lesson) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .heavy))
            Text(progress.isComplete(lesson.id) ? "Review Lesson" : "Start Lesson")
                .font(.system(size: 14, weight: .heavy))
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [lesson.category.tint, lesson.category.tint.opacity(0.7)],
                startPoint: .leading, endPoint: .trailing),
            in: .rect(cornerRadius: 14)
        )
    }

    // MARK: - Empty / Caught up

    private var allCaughtUp: some View {
        Button(action: onOpenTraining) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.mint.opacity(0.18))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.mint)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caught up on training")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Browse the Training Hub for advanced plays.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reasoning

    private func reasonLabel(_ category: LessonCategory) -> String {
        if progress.coachSessionsCompleted == 0 {
            return "Start with \(category.rawValue.lowercased())"
        }
        return "Sharpen your weakest area: \(category.rawValue)"
    }
}

#Preview {
    ScrollView {
        TodaysLessonCard()
            .environment(TrainingProgressStore())
    }
    .background(Theme.canvas)
}
