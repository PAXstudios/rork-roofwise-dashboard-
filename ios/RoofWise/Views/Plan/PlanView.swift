import SwiftUI

struct PlanView: View {
    @Environment(CustomerStore.self) private var store
    @State private var selectedDayOffset: Int = 0

    private var weekDays: [(label: String, date: Date, dayNum: String)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1 = Sun
        // Build Mon..Sun of the current week.
        let mondayOffset = (weekday + 5) % 7 // days since Monday
        let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let fmt = DateFormatter(); fmt.dateFormat = "d"
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday) ?? monday
            return (labels[i], d, fmt.string(from: d))
        }
    }

    private var selectedDate: Date {
        weekDays[safe: selectedDayOffset]?.date ?? Date()
    }

    private var items: [ScheduleItem] {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) {
            return HomeLiveData.todaySchedule(customers: store.customers)
        }
        // Non-today: show scheduled customers without inventing clock times.
        return HomeLiveData.untimedScheduledStops(customers: store.customers)
    }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: Date())
    }

    private var weekSummary: String {
        let stops = store.customers.filter {
            $0.stage == .inspectionScheduled || $0.stage == .adjusterMeeting
        }.count
        if stops == 0 { return "\(monthLabel) · nothing scheduled" }
        return "\(monthLabel) · \(stops) stop\(stops == 1 ? "" : "s") this week"
    }

    private var pipelineValue: String {
        HomeLiveData.pipelineSummary(customers: store.customers)
            .components(separatedBy: "·")
            .last?
            .trimmingCharacters(in: .whitespaces) ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(weekSummary)
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                        let isSelected = selectedDayOffset == i
                        let hasWork = hasWork(on: day.date)
                        Button {
                            withAnimation(.spring(duration: 0.25)) { selectedDayOffset = i }
                            ActivityStore.shared.logTap(target: "Plan.day.\(day.label)")
                        } label: {
                            VStack(spacing: 6) {
                                Text(day.label)
                                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(isSelected ? .white : Theme.inkFaint)
                                Text(day.dayNum)
                                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                    .foregroundStyle(isSelected ? .white : Theme.ink)
                                Circle()
                                    .fill(isSelected ? Color.white : Theme.ember)
                                    .frame(width: 5, height: 5)
                                    .opacity(hasWork ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                isSelected
                                ? AnyShapeStyle(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                                                               startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Theme.card)
                            )
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: isSelected ? 0 : 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                ScheduleCard()
                    .padding(.horizontal, -20)

                HStack(spacing: 10) {
                    PlanStat(value: "\(items.count)", label: "Stops", icon: "mappin.and.ellipse", tint: Theme.sky)
                    PlanStat(value: "\(store.customers.filter { $0.stage.kind == .lead }.count)",
                             label: "Open leads", icon: "person.2.fill", tint: Theme.amber)
                    PlanStat(value: pipelineValue == "value TBD" ? "—" : pipelineValue.replacingOccurrences(of: " est.", with: ""),
                             label: "Pipeline", icon: "chart.bar.fill", tint: Theme.mint)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .onAppear {
            // Default selection to today's weekday index within Mon..Sun.
            if let idx = weekDays.firstIndex(where: { Calendar.current.isDateInToday($0.date) }) {
                selectedDayOffset = idx
            }
        }
    }

    private func hasWork(on date: Date) -> Bool {
        if Calendar.current.isDateInToday(date) {
            return !HomeLiveData.todaySchedule(customers: store.customers).isEmpty
        }
        // Without per-day scheduling timestamps, only today is precise.
        return false
    }
}

private struct PlanStat: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
