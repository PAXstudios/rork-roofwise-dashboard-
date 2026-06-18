import SwiftUI

// MARK: - Date-range sheet (Step 5)
//
// Presets (7d / 30d / 90d / 1yr / All) plus a custom start–end picker. Picking a
// preset applies and dismisses; the custom range applies on its own button.

struct StormDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var range: StormDateRange

    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var showCustom: Bool

    init(range: Binding<StormDateRange>) {
        _range = range
        let now = Date()
        if case let .custom(start, end) = range.wrappedValue {
            _customStart = State(initialValue: start)
            _customEnd = State(initialValue: end)
            _showCustom = State(initialValue: true)
        } else {
            _customStart = State(initialValue: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now)
            _customEnd = State(initialValue: now)
            _showCustom = State(initialValue: false)
        }
    }

    private let presets: [(StormDateRange, String, String)] = [
        (.last7,      "Last 7 days",    "bolt.fill"),
        (.last30,     "Last 30 days",   "calendar"),
        (.last90,     "Last 90 days",   "calendar"),
        (.lastYear,   "Last 12 months", "calendar"),
        (.last3Years, "Last 3 years",   "clock.arrow.circlepath"),
        (.all,        "All time",       "infinity")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(presets, id: \.1) { preset in
                        presetRow(preset.0, label: preset.1, icon: preset.2)
                    }
                    customCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack {
            Text("Date Range")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func isSelected(_ r: StormDateRange) -> Bool { range == r }

    private func presetRow(_ r: StormDateRange, label: String, icon: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            range = r
            dismiss()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.ember.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 44, height: 44)
                Text(label)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if isSelected(r) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(12)
            .frame(minHeight: 64)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected(r) ? Theme.ember.opacity(0.4) : Theme.hairline, lineWidth: isSelected(r) ? 1 : 0.6))
        }
        .buttonStyle(.plain)
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Theme.Motion.snappy) { showCustom.toggle() }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.ink.opacity(0.10))
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(width: 44, height: 44)
                    Text("Custom range")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: showCustom ? "chevron.up" : "chevron.down")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .buttonStyle(.plain)

            if showCustom {
                DatePicker("Start", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .tint(Theme.ember)
                DatePicker("End", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .tint(Theme.ember)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    range = .custom(start: customStart.startOfDay, end: customEnd.endOfDay)
                    dismiss()
                } label: {
                    Text("Apply custom range")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.inkGradient, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.top, 4)
    }
}

private extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }
}
