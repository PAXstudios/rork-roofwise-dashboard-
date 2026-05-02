import SwiftUI

struct TrainingView: View {
    @State private var progress = TrainingProgressStore()
    @State private var selectedLesson: Lesson? = nil
    @State private var showCoach = false
    @State private var showExplainer = false

    private let curriculum = TrainingCurriculum.lessons

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    progressCard
                    aiToolsRow
                    lessonsByCategory
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Training")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .sheet(item: $selectedLesson) { lesson in
                LessonDetailView(lesson: lesson, progress: progress)
            }
            .sheet(isPresented: $showCoach) {
                RolePlayCoachView(progress: progress)
            }
            .sheet(isPresented: $showExplainer) {
                DamageExplainerView(progress: progress)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sharpen your craft")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Lessons, scripts, and AI coaching built for storm-restoration reps.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .textCase(.uppercase)
                    Text("\(progress.completedCount) of \(progress.totalLessons) lessons")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress.progressFraction)
                        .stroke(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.6), value: progress.progressFraction)
                    Text("\(Int(progress.progressFraction * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 54, height: 54)
            }

            HStack(spacing: 10) {
                statChip(icon: "mic.fill",
                         label: "Coach sessions",
                         value: "\(progress.coachSessionsCompleted)",
                         tint: Theme.sky)
                statChip(icon: "house.lodge.fill",
                         label: "Explainers",
                         value: "\(progress.explainerGenerationsCount)",
                         tint: Theme.mint)
                statChip(icon: "star.fill",
                         label: "Last score",
                         value: progress.lastCoachScore.map { "\($0)" } ?? "—",
                         tint: Theme.amber)
            }
        }
        .cardStyle(padding: 18, radius: 22)
    }

    private func statChip(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 14))
    }

    // MARK: - AI Tools

    private var aiToolsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI tools")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                aiToolCard(
                    title: "Role-Play Coach",
                    subtitle: "Type your pitch. Get scored feedback.",
                    icon: "mic.and.signal.meter.fill",
                    gradient: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                    action: { showCoach = true }
                )
                aiToolCard(
                    title: "Damage Explainer",
                    subtitle: "Translate findings for homeowners.",
                    icon: "house.lodge.fill",
                    gradient: [Theme.ember, Theme.emberDeep],
                    action: { showExplainer = true }
                )
            }
        }
    }

    private func aiToolCard(title: String, subtitle: String, icon: String,
                            gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                Spacer(minLength: 4)

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(14)
            .background(
                LinearGradient(colors: gradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 20)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lessons by Category

    private var lessonsByCategory: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Training Hub")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)

            ForEach(LessonCategory.allCases) { category in
                let lessons = TrainingCurriculum.lessons(for: category)
                if !lessons.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(category.tint.opacity(0.14))
                                Image(systemName: category.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(category.tint)
                            }
                            .frame(width: 28, height: 28)
                            Text(category.rawValue)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                        ForEach(lessons) { lesson in
                            lessonCard(lesson)
                        }
                    }
                }
            }
        }
    }

    private func lessonCard(_ lesson: Lesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(lesson.summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        metaChip(icon: "clock", text: "\(lesson.durationMinutes) min")
                        metaChip(icon: "chart.bar.fill", text: lesson.difficulty)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(progress.isComplete(lesson.id) ? Theme.mint : Theme.canvas)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(progress.isComplete(lesson.id) ? Theme.mint : Theme.hairline,
                                            lineWidth: 1)
                        )
                    Image(systemName: progress.isComplete(lesson.id) ? "checkmark" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(progress.isComplete(lesson.id) ? .white : Theme.inkSoft)
                }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.canvas, in: .rect(cornerRadius: 8))
    }
}

#Preview { TrainingView() }
