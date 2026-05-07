import SwiftUI

struct TrainingView: View {
    @Environment(TrainingProgressStore.self) private var progress
    @State private var selectedLesson: Lesson? = nil
    @State private var showCoach = false
    @State private var showExplainer = false
    @State private var showQueue = false
    @State private var queue = TrainingQueueStore.shared

    private let curriculum = TrainingCurriculum.lessons

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    pendingReviewCard
                    reviewStatsCard
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
            .navigationDestination(isPresented: $showQueue) {
                TrainingQueueView()
            }
        }
    }

    // MARK: - AI Training Queue

    private var pendingReviewCard: some View {
        let count = queue.pendingCount
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(count > 0 ? Theme.crimson.opacity(0.15) : Theme.mintSoft)
                    Image(systemName: count > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(count > 0 ? Theme.crimson : Theme.mint)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PENDING REVIEW")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text(count == 0 ? "All caught up" : "\(count) \(count == 1 ? "detection" : "detections")")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showQueue = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text(count > 0 ? "Review queue" : "Open queue")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private var reviewStatsCard: some View {
        let total = queue.totalReviewed
        let acc = queue.accuracyPercent
        let last = queue.lastReviewedAt
        return HStack(spacing: 10) {
            statTile(label: "Reviewed",
                     value: "\(total)",
                     icon: "text.badge.checkmark",
                     tint: Theme.ink)
            statTile(label: "Accuracy",
                     value: acc.map { "\($0)%" } ?? "—",
                     icon: "target",
                     tint: Theme.mint)
            statTile(label: "Last",
                     value: last.map {
                        $0.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
                     } ?? "—",
                     icon: "clock",
                     tint: Theme.amber)
        }
    }

    private func statTile(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 14))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sharpen your craft")
                .font(.system(size: Theme.TypeRamp.title, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Lessons, scripts, and AI coaching built for storm-restoration reps.")
                .font(.system(size: Theme.TypeRamp.meta))
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
                        .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .textCase(.uppercase)
                    Text("\(progress.completedCount) of \(progress.totalLessons) lessons")
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .bold))
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
                        .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
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
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: Theme.TypeRamp.micro, weight: .semibold))
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
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                aiToolCard(
                    title: "Role-Play Coach",
                    subtitle: "Type your pitch. Get scored feedback.",
                    icon: "mic.and.signal.meter.fill",
                    gradient: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                    action: {
                        ActivityStore.shared.logTap(target: "Training.aiTool.coach")
                        showCoach = true
                    }
                )
                aiToolCard(
                    title: "Damage Explainer",
                    subtitle: "Translate findings for homeowners.",
                    icon: "house.lodge.fill",
                    gradient: [Theme.ember, Theme.emberDeep],
                    action: {
                        ActivityStore.shared.logTap(target: "Training.aiTool.explainer")
                        showExplainer = true
                    }
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
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                Spacer(minLength: 4)

                Text(title)
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.caption))
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
                    .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
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
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
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
                                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
                                    .foregroundStyle(category.tint)
                            }
                            .frame(width: 28, height: 28)
                            Text(category.rawValue)
                                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .bold))
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
            ActivityStore.shared.logTap(target: "Training.lesson.\(lesson.id)")
            selectedLesson = lesson
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.title)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(lesson.summary)
                        .font(.system(size: Theme.TypeRamp.caption))
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
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .bold))
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
                .font(.system(size: Theme.TypeRamp.micro, weight: .semibold))
            Text(text)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.canvas, in: .rect(cornerRadius: 8))
    }
}

#Preview { TrainingView().environment(TrainingProgressStore()) }
