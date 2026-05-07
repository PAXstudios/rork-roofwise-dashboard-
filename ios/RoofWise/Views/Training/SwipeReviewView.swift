import SwiftUI
import SwiftData

struct SwipeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialItems: [ReviewPhotoItem]

    @State private var queue = TrainingQueueStore.shared
    @State private var index: Int = 0
    @State private var confirmed: Int = 0
    @State private var edited: Int = 0
    @State private var falsePositive: Int = 0
    @State private var skipped: Int = 0
    @State private var editedItem: ReviewPhotoItem? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var toast: String? = nil

    init(items: [ReviewPhotoItem] = ReviewPhotoFactory.pendingQueueItems()) {
        self.initialItems = items
    }

    private var items: [ReviewPhotoItem] { initialItems }
    private var current: ReviewPhotoItem? { index < items.count ? items[index] : nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()
            if let current {
                VStack(spacing: 14) {
                    topBar
                    reviewCard(current)
                    actionGrid(current)
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            } else {
                doneState
            }
        }
        .sheet(item: $editedItem) { item in
            OverlayEditorView(item: item) { delta, markers, type in
                writeCorrection(item: item, delta: delta, correctedMarkers: markers, type: type)
                edited += 1
                if let id = item.trainingItemId { queue.correct(id: id, override: markers.count) }
                showLearningToast(for: item, type: type)
                advance()
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 56, height: 56)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review AI")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("\(min(index + 1, max(items.count, 1))) of \(items.count) - \(confirmed) confirmed - \(edited) edited - \(falsePositive) false positive")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            ProgressView(value: items.isEmpty ? 1 : Double(index), total: Double(max(items.count, 1)))
                .tint(Theme.ember)
        }
    }

    private func reviewCard(_ item: ReviewPhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture().onChanged { value in scale = max(1, min(4, value.magnification)) })
                } else {
                    LinearGradient(colors: [Theme.ink, Theme.inkRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                                Text("AI overlay snapshot")
                                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                                Text(item.slopeLabel)
                                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                }
                GeometryReader { geo in
                    ForEach(item.markers) { marker in
                        Circle()
                            .fill(marker.category.markerType.color.opacity(0.30))
                            .overlay(Circle().stroke(marker.category.markerType.color, lineWidth: 3))
                            .frame(width: max(28, CGFloat(marker.radius) * 820), height: max(28, CGFloat(marker.radius) * 820))
                            .position(x: marker.x * geo.size.width, y: marker.y * geo.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .clipShape(.rect(cornerRadius: 22))
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 18)))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in handleSwipe(value.translation, item: item) }
            )

            Text(item.verdict)
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(item.snapshot.categories) { category in
                    HStack(spacing: 6) {
                        Text(category.kind.displayName)
                        Text("\(Int((category.confidence * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(category.confidence < LocalLearningEngine.shared.autoQueueThreshold ? Theme.crimson : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.canvas, in: .rect(cornerRadius: 12))
                }
            }
        }
        .cardStyle(padding: 14, radius: 24)
    }

    private func actionGrid(_ item: ReviewPhotoItem) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                bigAction("Correct", icon: "checkmark.seal.fill", tint: Theme.mint) { confirm(item) }
                bigAction("Edit", icon: "pencil.circle.fill", tint: Theme.ember) { editedItem = item }
            }
            HStack(spacing: 12) {
                smallAction("Skip", icon: "arrow.up.circle.fill", tint: Theme.inkSoft) { skipped += 1; advance() }
                smallAction("Not damage", icon: "arrow.down.circle.fill", tint: Theme.crimson) { reject(item) }
            }
        }
        .padding(.bottom, 12)
    }

    private func bigAction(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(tint, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func smallAction(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(tint, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var doneState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(Theme.mint)
            Text("Review complete")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                summaryTile("Confirmed", "\(confirmed)", Theme.mint)
                summaryTile("Edited", "\(edited)", Theme.ember)
                summaryTile("False +", "\(falsePositive)", Theme.crimson)
            }
            if let toast {
                Text(toast)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.mint)
                    .multilineTextAlignment(.center)
                    .cardStyle(padding: 14, radius: 16)
                    .padding(.horizontal, 20)
            }
            Spacer()
            Button {
                WeeklyCalibrationSummaryService.shared.schedule(profile: LocalLearningEngine.shared.profile, liftPercent: LocalLearningEngine.shared.weeklyLiftPercent)
                dismiss()
            } label: {
                Text("Apply corrections")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 14, radius: 18)
    }

    private func handleSwipe(_ translation: CGSize, item: ReviewPhotoItem) {
        defer { withAnimation(.spring(duration: 0.3)) { dragOffset = .zero } }
        if translation.width > 120 { confirm(item) }
        else if translation.width < -120 { editedItem = item }
        else if translation.height < -110 { skipped += 1; advance() }
        else if translation.height > 110 { reject(item) }
    }

    private func confirm(_ item: ReviewPhotoItem) {
        writeCorrection(item: item, delta: .empty, correctedMarkers: item.markers, type: .confirmed)
        confirmed += 1
        if let id = item.trainingItemId { queue.accept(id: id) }
        showLearningToast(for: item, type: .confirmed)
        advance()
    }

    private func reject(_ item: ReviewPhotoItem) {
        let ops = item.markers.map { MarkerOperation(markerId: $0.id, op: .deleted, before: $0, after: nil) }
        writeCorrection(item: item, delta: DetectionDelta(operations: ops), correctedMarkers: [], type: .rejected)
        falsePositive += 1
        if let id = item.trainingItemId { queue.reject(id: id) }
        showLearningToast(for: item, type: .rejected)
        advance()
    }

    private func writeCorrection(item: ReviewPhotoItem,
                                 delta: DetectionDelta,
                                 correctedMarkers: [EditableDamageMarker],
                                 type: CorrectionType) {
        let categories = affectedCategories(item: item, delta: delta, correctedMarkers: correctedMarkers, type: type)
        let correction = Correction(
            inspectionId: item.inspectionId,
            photoId: item.photoId,
            slopeId: item.slopeId,
            originalDetection: item.originalDetection,
            correctedDetection: AIDetectionSnapshot(snapshot: item.snapshot, markers: correctedMarkers, verdict: item.verdict),
            correctionType: type,
            categoriesAffected: categories,
            delta: delta
        )
        CorrectionsStore.shared.add(correction, in: modelContext)
    }

    private func affectedCategories(item: ReviewPhotoItem,
                                    delta: DetectionDelta,
                                    correctedMarkers: [EditableDamageMarker],
                                    type: CorrectionType) -> [ReviewDamageCategory] {
        let fromDelta = delta.operations.flatMap { [$0.before?.category, $0.after?.category].compactMap { $0 } }
        if !fromDelta.isEmpty { return Array(Set(fromDelta)) }
        if type == .rejected { return Array(Set(item.markers.map(\.category))) }
        if type == .confirmed { return Array(Set(item.markers.map(\.category))) }
        return Array(Set(correctedMarkers.map(\.category)))
    }

    private func showLearningToast(for item: ReviewPhotoItem, type: CorrectionType) {
        let categories = type == .rejected ? item.markers.map(\.category) : item.markers.map(\.category)
        toast = LocalLearningEngine.shared.improvementText(for: categories)
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.32)) {
            index += 1
            scale = 1
        }
    }
}
