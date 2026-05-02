import SwiftUI

struct TasksAndActivityCard: View {
    var embedded: Bool = false
    @State private var tasks: [TaskItem] = MockData.tasks
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
                VStack(spacing: 8) {
                    ForEach($tasks) { $task in
                        TaskRow(task: $task)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(MockData.activity.enumerated()), id: \.element.id) { idx, entry in
                        ActivityRow(entry: entry, isLast: idx == MockData.activity.count - 1)
                    }
                }
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

private struct ActivityRow: View {
    let entry: ActivityEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Image(systemName: entry.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(entry.iconColor)
                    .frame(width: 30, height: 30)
                    .background(entry.iconColor.opacity(0.14), in: .circle)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(entry.time)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                Text(entry.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.bottom, isLast ? 0 : 14)
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            }
        }
    }
}
