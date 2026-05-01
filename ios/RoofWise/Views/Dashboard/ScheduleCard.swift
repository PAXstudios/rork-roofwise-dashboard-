import SwiftUI

struct ScheduleCard: View {
    @State private var view: String = "List"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Schedule")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Thu, May 1 · 4 stops · 38 mi route")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                segmented
            }

            VStack(spacing: 0) {
                ForEach(Array(MockData.schedule.enumerated()), id: \.element.id) { idx, item in
                    ScheduleRow(item: item, isFirst: idx == 0, isLast: idx == MockData.schedule.count - 1)
                }
            }
        }
        .cardStyle(padding: 18, radius: 24)
        .padding(.horizontal, 20)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(["List", "Map"], id: \.self) { opt in
                Button {
                    withAnimation(.spring(duration: 0.25)) { view = opt }
                } label: {
                    Text(opt)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(view == opt ? Theme.ink : Theme.inkFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(view == opt ? Theme.card : Color.clear, in: .capsule)
                        .overlay(Capsule().stroke(view == opt ? Theme.hairline : Color.clear, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.canvas, in: .capsule)
    }
}

private struct ScheduleRow: View {
    let item: ScheduleItem
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(item.time)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(timePeriod)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)

                ZStack {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1.5)
                        .padding(.top, isFirst ? 8 : 0)
                        .padding(.bottom, isLast ? 8 : 0)
                    Circle()
                        .fill(isFirst ? item.priority.color : Theme.card)
                        .overlay(Circle().stroke(item.priority.color, lineWidth: 2))
                        .frame(width: 12, height: 12)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 44)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(item.priority.color)
                        .frame(width: 22, height: 22)
                        .background(item.priority.bg, in: .rect(cornerRadius: 6))
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    PriorityBadge(priority: item.priority)
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Text(item.address)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(item.assigneeColor.opacity(0.2))
                            .overlay(Text(initials(item.assignee)).font(.system(size: 9, weight: .bold)).foregroundStyle(item.assigneeColor))
                            .frame(width: 22, height: 22)
                        Text(item.assignee)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button {} label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.mint)
                            .frame(width: 28, height: 28)
                            .background(Theme.mintSoft, in: .circle)
                    }
                    .buttonStyle(.plain)
                    Button {} label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.sky)
                            .frame(width: 28, height: 28)
                            .background(Theme.skySoft, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(isFirst ? Theme.canvas : Color.clear, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFirst ? item.priority.color.opacity(0.4) : Color.clear, lineWidth: 1.2)
            )
            .padding(.bottom, isLast ? 0 : 8)
        }
    }

    private var timePeriod: String { Int(item.time.prefix(2)) ?? 0 < 12 ? "AM" : "PM" }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }
}

private struct PriorityBadge: View {
    let priority: Priority
    var body: some View {
        Text(priority.rawValue)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(priority.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(priority.bg, in: .capsule)
    }
}
