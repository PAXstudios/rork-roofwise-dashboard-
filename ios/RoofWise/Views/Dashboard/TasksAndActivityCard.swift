import SwiftUI

struct TasksAndActivityCard: View {
    var embedded: Bool = false
    // Empty state by default — no seeded tasks. A global task/activity store is a
    // Phase-5 follow-up; until then the dashboard shows clean empty states.
    @State private var tasks: [TaskItem] = []
    @State private var tab: String = "Tasks"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach(["Tasks", "Activity"], id: \.self) { t in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { tab = t }
                    } label: {
                        VStack(spacing: 6) {
                            Text(t)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(tab == t ? Theme.ink : Theme.inkFaint)
                            Capsule()
                                .fill(tab == t ? Theme.ember : Color.clear)
                                .frame(height: 2.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            if tab == "Tasks" {
                if tasks.isEmpty {
                    EmptyHint(icon: "checklist",
                              text: "No tasks yet. Tasks you create will show up here.")
                } else {
                    VStack(spacing: 8) {
                        ForEach($tasks) { $task in
                            TaskRow(task: $task)
                        }
                    }
                }
            } else {
                EmptyHint(icon: "clock.arrow.circlepath",
                          text: "Activity will appear here as you inspect, knock, and send proposals.")
            }
        }
        .cardStyle(padding: 18, radius: 24)
        .padding(.horizontal, embedded ? 0 : 20)
    }
}

private struct TaskRow: View {
    @Binding var task: TaskItem
    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.3)) { task.done.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(task.done ? Theme.mint : Theme.hairline, lineWidth: 1.5)
                        .background(Circle().fill(task.done ? Theme.mint : Color.clear))
                    if task.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(task.done ? Theme.inkFaint : Theme.ink)
                    .strikethrough(task.done)
                Text(task.due)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer()

            Text(task.tag)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(task.tagColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(task.tagColor.opacity(0.12), in: .capsule)
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }
}

