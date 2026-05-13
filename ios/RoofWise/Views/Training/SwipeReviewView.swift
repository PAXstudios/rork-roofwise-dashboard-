import SwiftUI
import UIKit

/// Phase 9A. Full-screen swipe-review card stack for pending AI detections.
/// Right swipe = Correct, left = Edit (opens OverlayEditorView), up = Skip,
/// down = Not damage. Every gesture has a parallel button (glove rule).
struct SwipeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var queue = TrainingQueueStore.shared
    @State private var corrections = CorrectionsStore.shared

    @State private var index: Int = 0
    @State private var confirmedCount: Int = 0
    @State private var editedCount: Int = 0
    @State private var falsePositiveCount: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var editingItem: TrainingItem? = nil
    @State private var showDone: Bool = false

    private var items: [TrainingItem] { queue.pending }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if items.isEmpty || showDone {
                summaryView
            } else {
                reviewStack
            }
        }
        .navigationTitle("Review AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                OverlayEditorView(item: item) { delta in
                    recordEdit(for: item, delta: delta)
                    advance()
                }
            }
        }
    }

    // MARK: - Stack

    private var current: TrainingItem? {
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    private var reviewStack: some View {
        VStack(spacing: 14) {
            progressStrip
            if let item = current {
                cardView(for: item)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 18)))
                    .gesture(swipeGesture)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: dragOffset)
                    .transition(.opacity)
            }
            actionButtons
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var progressStrip: some View {
        let total = items.count
        return VStack(spacing: 6) {
            HStack {
                Text("\(index + 1) of \(total) photos")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text("\(confirmedCount) confirmed · \(editedCount) edited · \(falsePositiveCount) false")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(Theme.inkGradient)
                        .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private func cardView(for item: TrainingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(item.kind.displayName.uppercased()) · \(item.aiCount) hits · \(Int((item.aiConfidence * 100).rounded()))% confidence")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)

            // Photo placeholder — we don't have the photo bytes wired through.
            // Show a labeled tile that matches the rest of the deck visually.
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.canvas)
                VStack(spacing: 10) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                    Text(item.slopeOrientation + " slope")
                        .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Theme.hairline, lineWidth: 0.6)
            )

            HStack(spacing: 8) {
                chip(text: "Hits \(item.aiCount)", color: Theme.ember)
                chip(text: "Conf \(Int((item.aiConfidence * 100).rounded()))%",
                     color: item.aiConfidence < 0.6 ? Theme.crimson : Theme.amber)
                Spacer(minLength: 0)
            }
        }
        .cardStyle(padding: 16, radius: 22)
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: .capsule)
    }

    // MARK: Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { confirm() } label: {
                    actionLabel("Correct", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .background(Theme.mint, in: .rect(cornerRadius: 18))
                .foregroundStyle(.white)

                Button { openEditor() } label: {
                    actionLabel("Edit", systemImage: "pencil.circle.fill")
                }
                .buttonStyle(.plain)
                .background(Theme.ember, in: .rect(cornerRadius: 18))
                .foregroundStyle(.white)
            }
            .frame(height: 88)

            HStack(spacing: 12) {
                Button { skip() } label: {
                    secondaryLabel("Skip")
                }
                .buttonStyle(.plain)
                Button { markFalsePositive() } label: {
                    secondaryLabel("Not damage")
                        .foregroundStyle(Theme.crimson)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 56)
        }
    }

    private func actionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
            Text(text)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
        }
        .frame(maxWidth: .infinity, minHeight: 88)
    }

    private func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: Swipe

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let h = value.translation.width
                let v = value.translation.height
                if abs(h) > 120 || abs(v) > 120 {
                    if abs(h) > abs(v) {
                        if h > 0 { confirm() } else { openEditor() }
                    } else {
                        if v > 0 { markFalsePositive() } else { skip() }
                    }
                }
                dragOffset = .zero
            }
    }

    // MARK: Mutations

    private func confirm() {
        guard let item = current else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        queue.accept(item)
        let snap = CorrectionDetectionSnapshot(markers: [], findings: [])
        let data = CorrectionsStore.encode(snap)
        let correction = Correction(
            inspectionId: CorrectionsStore.deterministicUUID(from: item.inspectionId),
            photoId: CorrectionsStore.deterministicUUID(from: item.photoPath ?? item.id.uuidString),
            originalDetection: data,
            correctedDetection: data,
            correctionType: .confirmed,
            categoriesAffected: [item.kind.rawValue],
            delta: CorrectionsStore.encode(DetectionDelta()),
            correctedBy: CorrectionsStore.localUserId
        )
        corrections.append(correction)
        confirmedCount += 1
        advance()
    }

    private func openEditor() {
        guard let item = current else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        editingItem = item
    }

    private func recordEdit(for item: TrainingItem, delta: DetectionDelta) {
        let isOnlyAdds = !delta.ops.isEmpty && delta.ops.allSatisfy { $0.kind == .added }
        let snap = CorrectionDetectionSnapshot(markers: [], findings: [])
        let data = CorrectionsStore.encode(snap)
        let correction = Correction(
            inspectionId: CorrectionsStore.deterministicUUID(from: item.inspectionId),
            photoId: CorrectionsStore.deterministicUUID(from: item.photoPath ?? item.id.uuidString),
            originalDetection: data,
            correctedDetection: data,
            correctionType: isOnlyAdds ? .addedMissed : .edited,
            categoriesAffected: [item.kind.rawValue],
            delta: CorrectionsStore.encode(delta),
            correctedBy: CorrectionsStore.localUserId
        )
        corrections.append(correction)
        queue.correct(item, override: item.aiCount + delta.addedCount - delta.deletedCount)
        editedCount += 1
    }

    private func skip() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        advance()
    }

    private func markFalsePositive() {
        guard let item = current else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        queue.reject(item)
        let snap = CorrectionDetectionSnapshot(markers: [], findings: [])
        let data = CorrectionsStore.encode(snap)
        let correction = Correction(
            inspectionId: CorrectionsStore.deterministicUUID(from: item.inspectionId),
            photoId: CorrectionsStore.deterministicUUID(from: item.photoPath ?? item.id.uuidString),
            originalDetection: data,
            correctedDetection: data,
            correctionType: .removedFalsePositive,
            categoriesAffected: [item.kind.rawValue],
            delta: CorrectionsStore.encode(DetectionDelta()),
            correctedBy: CorrectionsStore.localUserId
        )
        corrections.append(correction)
        falsePositiveCount += 1
        advance()
    }

    private func advance() {
        if index + 1 >= items.count {
            withAnimation { showDone = true }
        } else {
            withAnimation { index += 1 }
        }
    }

    // MARK: Summary / empty

    private var summaryView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: items.isEmpty && confirmedCount == 0 ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Theme.mint)
            Text(items.isEmpty && confirmedCount == 0 ? "Nothing to review right now" : "Review complete")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            if !(items.isEmpty && confirmedCount == 0) {
                Text("\(confirmedCount) confirmed · \(editedCount) edited · \(falsePositiveCount) false positives")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
            } label: {
                Text("Apply corrections")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                    .shadow(color: Theme.ink.opacity(0.25), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
