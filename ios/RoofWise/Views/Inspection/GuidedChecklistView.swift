import SwiftUI
import UIKit

/// Compact horizontal pill showing the *current* guided zone + a progress dot.
/// Tapping it opens the full sequenced checklist sheet.
struct GuidedZonePill: View {
    let currentZone: GuidedZone
    let completedCount: Int
    let totalCount: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(currentZone.tint.opacity(0.22))
                    Image(systemName: currentZone.icon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(currentZone.tint)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("GUIDED")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.ember.opacity(0.18), in: .capsule)
                        Text("\(completedCount)/\(totalCount)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.8))
                            .monospacedDigit()
                    }
                    Text("Capture: \(currentZone.title)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Progress ring
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.001, CGFloat(completedCount) / CGFloat(max(totalCount, 1))))
                        .stroke(LinearGradient(colors: [Theme.amber, Theme.ember],
                                               startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "list.bullet")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ember.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Checklist Sheet

struct GuidedChecklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let zoneCounts: [GuidedZone: Int]
    @Binding var currentZone: GuidedZone
    @Binding var isGuidedMode: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    progressBar
                    checklist
                }
                .padding(18)
            }
            .background(Theme.canvas)
            .navigationTitle("Guided Inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut) { isGuidedMode = false }
                        dismiss()
                    } label: {
                        Text("Exit")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.crimson)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var completedCount: Int {
        GuidedZone.allCases.filter { (zoneCounts[$0] ?? 0) >= $0.minPhotos }.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Walk the roof in order")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Capture each zone below so nothing is missed. Tap any row to jump there next.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(2)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(completedCount) of \(GuidedZone.allCases.count) complete")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(Double(completedCount) / Double(GuidedZone.allCases.count) * 100))%")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.amber, Theme.ember],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(completedCount) / CGFloat(GuidedZone.allCases.count))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var checklist: some View {
        VStack(spacing: 10) {
            ForEach(Array(GuidedZone.allCases.enumerated()), id: \.element.id) { idx, zone in
                let count = zoneCounts[zone] ?? 0
                let done = count >= zone.minPhotos
                let isCurrent = currentZone == zone
                Button {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        currentZone = zone
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(done ? Theme.mint : (isCurrent ? Theme.ember : Theme.canvas))
                                .overlay(Circle().stroke(done ? Theme.mint : (isCurrent ? Theme.ember : Theme.hairline), lineWidth: 1))
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(idx + 1)")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(isCurrent ? .white : Theme.inkSoft)
                            }
                        }
                        .frame(width: 30, height: 30)

                        ZStack {
                            RoundedRectangle(cornerRadius: 9).fill(zone.tint.opacity(0.14))
                            Image(systemName: zone.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(zone.tint)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(zone.title)
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                if isCurrent && !done {
                                    Text("NEXT")
                                        .font(.system(size: 8, weight: .heavy))
                                        .tracking(0.8)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Theme.ember, in: .capsule)
                                }
                            }
                            Text(zone.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Text(done ? "✓ \(count)" : "\(count)/\(zone.minPhotos)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(done ? Theme.mint : Theme.inkFaint)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        (isCurrent ? Theme.emberSoft : Theme.card),
                        in: .rect(cornerRadius: 14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isCurrent ? Theme.ember.opacity(0.5) : Theme.hairline, lineWidth: isCurrent ? 1.0 : 0.6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
