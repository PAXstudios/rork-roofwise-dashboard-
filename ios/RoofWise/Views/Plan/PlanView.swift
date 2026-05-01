import SwiftUI

struct PlanView: View {
    @State private var selectedDay = 1

    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let dates = ["28", "29", "30", "1", "2", "3", "4"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("May 2026 · 12 stops this week")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Day picker
                HStack(spacing: 8) {
                    ForEach(0..<7) { i in
                        Button {
                            withAnimation(.spring(duration: 0.25)) { selectedDay = i }
                        } label: {
                            VStack(spacing: 6) {
                                Text(days[i])
                                    .font(.system(size: 10, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(selectedDay == i ? .white : Theme.inkFaint)
                                Text(dates[i])
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundStyle(selectedDay == i ? .white : Theme.ink)
                                Circle()
                                    .fill(selectedDay == i ? Color.white : Theme.ember)
                                    .frame(width: 5, height: 5)
                                    .opacity(i == 1 || i == 3 || i == 4 ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                selectedDay == i
                                ? AnyShapeStyle(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                                                               startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Theme.card)
                            )
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: selectedDay == i ? 0 : 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // Schedule list (reuse)
                ScheduleCard()
                    .padding(.horizontal, -20)

                // Recap
                HStack(spacing: 10) {
                    PlanStat(value: "38 mi", label: "Drive", icon: "car.fill", tint: Theme.sky)
                    PlanStat(value: "6.5 h", label: "Field time", icon: "clock.fill", tint: Theme.amber)
                    PlanStat(value: "$72k", label: "Pipeline", icon: "chart.bar.fill", tint: Theme.mint)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ink)
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
