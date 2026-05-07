import SwiftUI

/// Glove-friendly review screen for low-confidence AI damage detections.
/// Each card has three big chips: Looks right / Wrong count / Not damage.
struct TrainingQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var queue = TrainingQueueStore.shared
    @State private var correcting: TrainingItem? = nil
    @State private var correctionValue: Int = 0
    @State private var toast: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()
            content
            if let toast {
                Text(toast)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Theme.mint, in: .rect(cornerRadius: 16))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Pending Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $correcting) { item in
            CorrectionSheet(
                item: item,
                value: $correctionValue,
                onSave: { newCount in
                    queue.correct(item, override: newCount)
                    showToast(for: item)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    correcting = nil
                },
                onCancel: { correcting = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        let pending = queue.pending
        if pending.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(pending) { item in
                        card(item)
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .heavy))
                .foregroundStyle(Theme.mint)
            Text("Queue clear")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("New low-confidence detections will appear here for your review.")
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }

    // MARK: Card

    private func card(_ item: TrainingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.emberSoft)
                    Image(systemName: item.kind.icon)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind.displayName)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("\(item.inspectionId) · \(item.slopeOrientation) slope")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(Int((item.aiConfidence * 100).rounded()))% conf")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .foregroundStyle(item.aiConfidence < 0.6 ? Theme.crimson : Theme.amber)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((item.aiConfidence < 0.6 ? Theme.crimson : Theme.amber)
                                .opacity(0.12), in: .capsule)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AI says")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                    Text("\(item.aiCount)")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 12) {
                actionChip(label: "Looks right",
                           icon: "checkmark.circle.fill",
                           tint: Theme.mint) {
                    queue.accept(item)
                    showToast(for: item)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                actionChip(label: "Wrong count",
                           icon: "pencil.circle.fill",
                           tint: Theme.amber) {
                    correctionValue = item.aiCount
                    correcting = item
                }
                actionChip(label: "Not damage",
                           icon: "xmark.circle.fill",
                           tint: Theme.crimson) {
                    queue.reject(item)
                    showToast(for: item)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func showToast(for item: TrainingItem) {
        let text = LocalLearningEngine.shared.improvementText(for: [item.kind.reviewCategory])
        guard let text else { return }
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toast = nil }
        }
    }

    private func actionChip(label: String,
                            icon: String,
                            tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                Text(label)
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(tint, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Correction sheet

private struct CorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: TrainingItem
    @Binding var value: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.kind.displayName)
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("AI counted \(item.aiCount). What's the right count?")
                        .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                HStack(spacing: 14) {
                    Button {
                        value = max(0, value - 1)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 64, height: 64)
                            .background(Theme.card, in: .circle)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Text("\(value)")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                    Button {
                        value += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Theme.ember, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    onSave(value)
                } label: {
                    Text("Save correction")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                        .shadow(color: Theme.ink.opacity(0.28), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Correct count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
