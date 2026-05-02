import SwiftUI

struct LessonDetailView: View {
    let lesson: Lesson
    @Bindable var progress: TrainingProgressStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    ForEach(Array(lesson.sections.enumerated()), id: \.offset) { idx, section in
                        sectionCard(index: idx + 1, section: section)
                    }
                    takeaways
                    completeButton
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(lesson.category.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(lesson.category.tint.opacity(0.14))
                    Image(systemName: lesson.category.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(lesson.category.tint)
                }
                .frame(width: 28, height: 28)
                Text(lesson.category.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(lesson.category.tint)
                    .tracking(0.5)
            }
            Text(lesson.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(lesson.summary)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Label("\(lesson.durationMinutes) min read", systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.canvas, in: .rect(cornerRadius: 8))
                Label(lesson.difficulty, systemImage: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.canvas, in: .rect(cornerRadius: 8))
            }
        }
    }

    private func sectionCard(index: Int, section: LessonSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.ink))
                Text(section.heading)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Text(section.body)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(section.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Theme.ember)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .padding(12)
            .background(lesson.category.tint.opacity(0.07), in: .rect(cornerRadius: 12))
        }
        .cardStyle()
    }

    private var takeaways: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.amber)
                Text("Key takeaways")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            ForEach(lesson.keyTakeaways, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mint)
                    Text(item)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.amberSoft.opacity(0.6), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.amber.opacity(0.4), lineWidth: 0.8))
    }

    private var completeButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                progress.toggle(lesson.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: progress.isComplete(lesson.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .bold))
                Text(progress.isComplete(lesson.id) ? "Completed" : "Mark as complete")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: progress.isComplete(lesson.id)
                               ? [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)]
                               : [Theme.ember, Theme.emberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 16)
            )
            .shadow(color: (progress.isComplete(lesson.id) ? Theme.mint : Theme.ember).opacity(0.35),
                    radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
