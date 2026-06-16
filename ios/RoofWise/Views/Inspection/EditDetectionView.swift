import SwiftUI
import UIKit

// MARK: - Edit Detection (the recursive-learning keystone)
//
// Full-screen editor that lets the inspector correct AI damage detections on
// the real photo, then writes structured `damage_feedback` rows to Supabase via
// `DamageFeedbackService` (cloud, new schema) AND a local `Correction` to
// `CorrectionsStore` (on-device learning + outbox). Without this the box_2d fix
// only makes the AI prettier — this is what makes it smarter over time.
//
// Glove rules: 56–64pt targets, ≥12pt spacing, sticky bottom CTAs, haptics.

/// Frozen copy of an AI marker captured at view entry, used to diff edits.
private struct OriginalSnap: Equatable {
    let type: DamageMarkerType
    let severity: Int      // 1–10
    let x: Double
    let y: Double
    let radius: Double
    let confidence: Int     // 0–100
    let note: String
}

/// A live, editable marker on the canvas. `original == nil` means the inspector
/// added it (the AI missed it).
private struct DraftMarker: Identifiable, Equatable {
    let id: UUID
    let original: OriginalSnap?
    var x: Double
    var y: Double
    var radius: Double
    var type: DamageMarkerType
    var severity: Int      // 1–10
    var note: String

    func isChanged(from o: OriginalSnap) -> Bool {
        if type != o.type || severity != o.severity || note != o.note { return true }
        return abs(x - o.x) > 0.003 || abs(y - o.y) > 0.003 || abs(radius - o.radius) > 0.003
    }

    func toMarker() -> DamageMarker {
        DamageMarker(x: CGFloat(x), y: CGFloat(y), radius: CGFloat(radius),
                     type: type, severity: findingSeverity10(severity),
                     note: note, confidence: original?.confidence ?? 100)
    }
}

private struct DragAnchor: Equatable { let id: UUID; let x: Double; let y: Double }

private struct EditToast: Identifiable, Equatable {
    enum Style { case info, undo, success }
    let id = UUID()
    let text: String
    let systemImage: String
    var style: Style = .info
}

// MARK: - Severity mapping helpers (FindingSeverity <-> 1–10)

private func sev10(_ s: FindingSeverity) -> Int {
    switch s {
    case .none: return 1
    case .minor: return 3
    case .moderate: return 6
    case .severe: return 9
    }
}

private func findingSeverity10(_ v: Int) -> FindingSeverity {
    switch v {
    case ..<4: return .minor
    case 4..<7: return .moderate
    default: return .severe
    }
}

private func severityName10(_ v: Int) -> String {
    findingSeverity10(v).rawValue
}

private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

// MARK: - EditDetectionView

struct EditDetectionView: View {
    let photo: CapturedPhoto
    let inspectionId: String
    /// Persist the final marker set to the parent's store (keeps the overlay's
    /// local mirror in sync). The editor owns all feedback/correction writes.
    var onApply: ([DamageMarker]) -> Void
    var onClose: () -> Void

    private let originalMarkers: [DamageMarker]

    @State private var drafts: [DraftMarker]
    @State private var selectedID: UUID?
    @State private var currentCategory: DamageMarkerType = .hailHits
    @State private var currentSeverity: Int = 6
    @State private var addMode: Bool = true

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var zoomBase: CGFloat?
    @State private var panBase: CGSize?
    @State private var resizeBase: Double?
    @State private var dragAnchor: DragAnchor?

    @State private var isDirty = false
    @State private var pulseID: UUID?
    @State private var lastDeleted: DraftMarker?
    @State private var toast: EditToast?
    @State private var detailMarkerID: UUID?
    @State private var showDiscardConfirm = false
    @State private var saving = false

    @State private var speech = SpeechDictationService()

    private let categories: [DamageMarkerType] = [
        .hailHits, .bruising, .granuleLoss, .windDamage, .windCreasing,
        .blistering, .cracking, .flashing, .algaeMoss, .missingShingles,
        .splitting, .lifted, .structuralSagging
    ]

    init(photo: CapturedPhoto,
         inspectionId: String,
         onApply: @escaping ([DamageMarker]) -> Void,
         onClose: @escaping () -> Void) {
        self.photo = photo
        self.inspectionId = inspectionId
        self.onApply = onApply
        self.onClose = onClose
        self.originalMarkers = photo.damageMarkers
        _drafts = State(initialValue: photo.damageMarkers.map { m in
            DraftMarker(
                id: m.id,
                original: OriginalSnap(type: m.type, severity: sev10(m.severity),
                                       x: Double(m.x), y: Double(m.y),
                                       radius: Double(m.radius), confidence: m.confidence,
                                       note: m.note),
                x: Double(m.x), y: Double(m.y), radius: Double(m.radius),
                type: m.type, severity: sev10(m.severity), note: m.note)
        })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            canvas
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomDock
            }
            if let toast {
                toastView(toast)
                    .padding(.bottom, 290)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(true)
        .confirmationDialog("Discard changes?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onClose() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your marker corrections won’t be saved.")
        }
        .sheet(isPresented: detailPresented) {
            if let id = detailMarkerID, let binding = bindingFor(id) {
                MarkerDetailSheet(draft: binding, speech: speech) {
                    detailMarkerID = nil
                    speech.stop()
                    markDirty()
                }
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let rect = imageRect(for: photo.image, container: geo.size)
            ZStack {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in handleCanvasTap(location, rect: rect) }

                ForEach(drafts) { d in
                    DraftPin(draft: d, selected: selectedID == d.id, pulsing: pulseID == d.id)
                        .position(x: rect.minX + d.x * rect.width,
                                  y: rect.minY + d.y * rect.height)
                        .gesture(markerDrag(d, rect: rect))
                        .onTapGesture { selectMarker(d.id) }
                        .onLongPressGesture(minimumDuration: 0.4) { openDetail(d.id) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(zoom)
            .offset(pan)
            .gesture(zoomGesture)
            .simultaneousGesture(panGesture)
        }
        .ignoresSafeArea()
    }

    private func imageRect(for image: UIImage, container: CGSize) -> CGRect {
        let imgRatio = image.size.width / max(image.size.height, 1)
        let conRatio = container.width / max(container.height, 1)
        var w = container.width
        var h = container.height
        if imgRatio > conRatio {
            w = container.width
            h = container.width / imgRatio
        } else {
            h = container.height
            w = container.height * imgRatio
        }
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    // MARK: - Gestures

    private func markerDrag(_ d: DraftMarker, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard selectedID == d.id else { return }
                let anchor: DragAnchor
                if let a = dragAnchor, a.id == d.id {
                    anchor = a
                } else {
                    anchor = DragAnchor(id: d.id, x: d.x, y: d.y)
                    dragAnchor = anchor
                }
                let nx = clamp01(anchor.x + Double(value.translation.width / max(rect.width, 1)))
                let ny = clamp01(anchor.y + Double(value.translation.height / max(rect.height, 1)))
                setPosition(d.id, x: nx, y: ny)
            }
            .onEnded { _ in
                if dragAnchor != nil { markDirty(); impact(.light) }
                dragAnchor = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if let id = selectedID {
                    let base = resizeBase ?? radius(of: id)
                    if resizeBase == nil { resizeBase = base }
                    setRadius(id, value: min(max(base * Double(scale), 0.015), 0.18))
                } else {
                    let base = zoomBase ?? zoom
                    if zoomBase == nil { zoomBase = base }
                    zoom = min(max(base * scale, 1), 4)
                }
            }
            .onEnded { _ in
                if selectedID != nil { markDirty() }
                resizeBase = nil
                zoomBase = nil
                if zoom <= 1.02 {
                    withAnimation(Theme.Motion.snappy) { zoom = 1; pan = .zero }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedID == nil, zoom > 1 else { return }
                let base = panBase ?? pan
                if panBase == nil { panBase = base }
                pan = CGSize(width: base.width + value.translation.width,
                             height: base.height + value.translation.height)
            }
            .onEnded { _ in panBase = nil }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { attemptClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Detection")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(.white)
                Text("\(drafts.count) marker\(drafts.count == 1 ? "" : "s") · \(photo.slope.shortName)")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if zoom > 1.02 {
                Button {
                    withAnimation(Theme.Motion.snappy) { zoom = 1; pan = .zero }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: .circle)
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))
                }
            }

            if lastDeleted != nil {
                Button { undoDelete() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .heavy))
                        Text("Undo")
                            .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(.black.opacity(0.5), in: .capsule)
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear],
                                   startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Bottom dock

    private var bottomDock: some View {
        VStack(spacing: 12) {
            if selectedID != nil {
                selectedControls
            } else {
                addControls
            }
            categoryStrip
            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            ZStack {
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.clear, .black, .black],
                                         startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .environment(\.colorScheme, .dark)
    }

    private var addControls: some View {
        HStack(spacing: 10) {
            modeButton(title: "Tap to Add", icon: "plus.viewfinder", active: addMode) {
                withAnimation(Theme.Motion.snappy) { addMode = true }
                impact(.light)
            }
            modeButton(title: "Move / Zoom", icon: "hand.draw.fill", active: !addMode) {
                withAnimation(Theme.Motion.snappy) { addMode = false }
                impact(.light)
            }
        }
    }

    private func modeButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14, weight: .heavy))
                Text(title).font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
            }
            .foregroundStyle(active ? .white : .white.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(active ? Theme.ember : Color.white.opacity(0.1), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(active ? .white.opacity(0.25) : .white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var selectedControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("EDITING MARKER")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    withAnimation(Theme.Motion.snappy) { selectedID = nil }
                    impact(.light)
                } label: {
                    Text("Done")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Theme.ember.opacity(0.16), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Text("Sev \(currentSeverity)")
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .leading)
                Slider(value: severityBinding, in: 1...10, step: 1)
                    .tint(Theme.ember)
            }

            HStack(spacing: 10) {
                iconAction("minus.magnifyingglass") { stepRadius(-1) }
                iconAction("plus.magnifyingglass") { stepRadius(1) }
                Button { openDetail(selectedID) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill").font(.system(size: 13, weight: .heavy))
                        Text("Notes").font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                Button { deleteSelected() } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.crimson, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconAction(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    CategoryChipView(category: cat, selected: currentCategory == cat) {
                        tapCategory(cat)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { attemptClose() } label: {
                Text("Discard")
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 120, height: 64)
                    .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Button { Task { await save() } } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 17, weight: .heavy))
                    }
                    Text(saving ? "Saving…" : "Save Corrections")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.4), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
    }

    // MARK: - Toast

    private func toastView(_ t: EditToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.systemImage)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(t.style == .success ? Theme.mint : (t.style == .undo ? Theme.amber : .white))
            Text(t.text)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
            if t.style == .undo {
                Spacer(minLength: 6)
                Button { undoDelete() } label: {
                    Text("Undo")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    // MARK: - Marker mutations

    private func handleCanvasTap(_ location: CGPoint, rect: CGRect) {
        if selectedID != nil {
            withAnimation(Theme.Motion.snappy) { selectedID = nil }
            return
        }
        guard addMode, rect.width > 0, rect.height > 0 else { return }
        let nx = Double((location.x - rect.minX) / rect.width)
        let ny = Double((location.y - rect.minY) / rect.height)
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
        let new = DraftMarker(id: UUID(), original: nil, x: nx, y: ny, radius: 0.04,
                              type: currentCategory, severity: currentSeverity, note: "")
        drafts.append(new)
        withAnimation(Theme.Motion.snappy) { selectedID = new.id }
        pulseID = new.id
        markDirty()
        impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if pulseID == new.id { pulseID = nil }
        }
    }

    private func selectMarker(_ id: UUID) {
        impact(.light)
        withAnimation(Theme.Motion.snappy) {
            selectedID = id
            if let d = drafts.first(where: { $0.id == id }) {
                currentCategory = d.type
                currentSeverity = d.severity
            }
        }
    }

    private func tapCategory(_ cat: DamageMarkerType) {
        impact(.light)
        currentCategory = cat
        if let id = selectedID, let idx = drafts.firstIndex(where: { $0.id == id }) {
            drafts[idx].type = cat
            markDirty()
        }
    }

    private func setPosition(_ id: UUID, x: Double, y: Double) {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].x = x
        drafts[idx].y = y
    }

    private func setRadius(_ id: UUID, value: Double) {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].radius = value
    }

    private func radius(of id: UUID) -> Double {
        drafts.first(where: { $0.id == id })?.radius ?? 0.04
    }

    private func stepRadius(_ direction: Int) {
        guard let id = selectedID else { return }
        let next = min(max(radius(of: id) + Double(direction) * 0.012, 0.015), 0.18)
        setRadius(id, value: next)
        markDirty()
        impact(.rigid)
    }

    private func deleteSelected() {
        guard let id = selectedID, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        let removed = drafts.remove(at: idx)
        lastDeleted = removed
        withAnimation(Theme.Motion.snappy) { selectedID = nil }
        markDirty()
        notify(.warning)
        showToast(EditToast(text: "Marker deleted", systemImage: "trash.fill", style: .undo))
    }

    private func undoDelete() {
        guard let m = lastDeleted else { return }
        drafts.append(m)
        lastDeleted = nil
        withAnimation(Theme.Motion.snappy) { selectedID = m.id }
        toast = nil
        impact(.light)
    }

    private func openDetail(_ id: UUID?) {
        guard let id else { return }
        selectedID = id
        detailMarkerID = id
        impact(.medium)
    }

    private func markDirty() { isDirty = true }

    private func attemptClose() {
        if isDirty {
            showDiscardConfirm = true
        } else {
            onClose()
        }
    }

    private func bindingFor(_ id: UUID) -> Binding<DraftMarker>? {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return nil }
        return $drafts[idx]
    }

    private var detailPresented: Binding<Bool> {
        Binding(get: { detailMarkerID != nil },
                set: { if !$0 { detailMarkerID = nil; speech.stop() } })
    }

    private var severityBinding: Binding<Double> {
        Binding(get: { Double(currentSeverity) },
                set: { v in
                    let s = Int(v.rounded())
                    currentSeverity = s
                    if let id = selectedID, let idx = drafts.firstIndex(where: { $0.id == id }) {
                        drafts[idx].severity = s
                        markDirty()
                    }
                })
    }

    private func showToast(_ t: EditToast) {
        withAnimation(Theme.Motion.standard) { toast = t }
        let token = t.id
        let delay = t.style == .undo ? 1.5 : 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if toast?.id == token { withAnimation(Theme.Motion.standard) { toast = nil } }
        }
    }

    // MARK: - Save

    private func save() async {
        saving = true
        let final = drafts.map { $0.toMarker() }
        let events = buildFeedbackEvents()

        appendCorrection(final: final)
        onApply(final)

        if !events.isEmpty {
            await DamageFeedbackService.shared.record(events)
        }
        saving = false
        notify(.success)

        let queued = !events.isEmpty && DamageFeedbackService.shared.pendingCount > 0
        showToast(queued
                  ? EditToast(text: "Couldn’t reach the cloud — corrections saved, will retry",
                              systemImage: "arrow.triangle.2.circlepath", style: .info)
                  : EditToast(text: "Thanks — your corrections will train the model for everyone",
                              systemImage: "arrow.up.circle.fill", style: .success))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onClose() }
    }

    private func buildFeedbackEvents() -> [DamageFeedbackEvent] {
        let userId = AuthStore.shared.currentUserId ?? ""
        let trust = DamageFeedbackService.snapshotTrustScore()
        let model = GeminiAnalysisService.modelVersion
        let photoId = photo.id.uuidString
        let currentIds = Set(drafts.map { $0.id })
        var events: [DamageFeedbackEvent] = []

        for d in drafts {
            if let orig = d.original {
                let changed = d.isChanged(from: orig)
                events.append(DamageFeedbackEvent(
                    inspectionPhotoId: photoId, userId: userId,
                    action: changed ? .modify : .confirm,
                    aiPredictionId: d.id.uuidString,
                    aiDamageType: orig.type.rawValue,
                    aiBoundingBox: FeedbackBox.from(x: orig.x, y: orig.y, radius: orig.radius),
                    aiConfidence: min(Double(orig.confidence) / 100.0, 9.99),
                    aiModelVersion: model,
                    userDamageType: d.type.rawValue,
                    userBoundingBox: FeedbackBox.from(x: d.x, y: d.y, radius: d.radius),
                    userSeverity: d.severity,
                    userNotes: d.note.isEmpty ? nil : d.note,
                    userTrustScore: trust))
            } else {
                events.append(DamageFeedbackEvent(
                    inspectionPhotoId: photoId, userId: userId,
                    action: .addNew,
                    aiModelVersion: model,
                    userDamageType: d.type.rawValue,
                    userBoundingBox: FeedbackBox.from(x: d.x, y: d.y, radius: d.radius),
                    userSeverity: d.severity,
                    userNotes: d.note.isEmpty ? nil : d.note,
                    userTrustScore: trust))
            }
        }

        for m in originalMarkers where !currentIds.contains(m.id) {
            events.append(DamageFeedbackEvent(
                inspectionPhotoId: photoId, userId: userId,
                action: .reject,
                aiPredictionId: m.id.uuidString,
                aiDamageType: m.type.rawValue,
                aiBoundingBox: FeedbackBox.from(x: Double(m.x), y: Double(m.y), radius: Double(m.radius)),
                aiConfidence: min(Double(m.confidence) / 100.0, 9.99),
                aiModelVersion: model,
                userTrustScore: trust))
        }
        return events
    }

    private func appendCorrection(final: [DamageMarker]) {
        guard !originalMarkers.isEmpty || !final.isEmpty else { return }
        let before = CorrectionDetectionSnapshot.from(findings: photo.findings, markers: originalMarkers)
        let after = CorrectionDetectionSnapshot.from(findings: photo.findings, markers: final)

        let currentIds = Set(drafts.map { $0.id })
        let deleted = originalMarkers.filter { !currentIds.contains($0.id) }
        let added = drafts.filter { $0.original == nil }
        let modified = drafts.filter { d in
            if let o = d.original { return d.isChanged(from: o) }
            return false
        }

        var ops: [DetectionDeltaOp] = []
        for d in added {
            ops.append(DetectionDeltaOp(kind: .added, markerId: d.id, x: d.x, y: d.y, radius: d.radius,
                                        category: d.type.rawValue, severity: severityName10(d.severity),
                                        note: d.note.isEmpty ? nil : d.note))
        }
        for m in deleted {
            ops.append(DetectionDeltaOp(kind: .deleted, markerId: m.id, x: nil, y: nil, radius: nil,
                                        category: m.type.rawValue, severity: nil, note: nil))
        }
        for d in modified {
            ops.append(DetectionDeltaOp(kind: .recategorized, markerId: d.id, x: d.x, y: d.y, radius: d.radius,
                                        category: d.type.rawValue, severity: severityName10(d.severity),
                                        note: d.note.isEmpty ? nil : d.note))
        }

        let type: CorrectionType
        if added.isEmpty && deleted.isEmpty && modified.isEmpty {
            type = .confirmed
        } else if !added.isEmpty && deleted.isEmpty && modified.isEmpty {
            type = .addedMissed
        } else if !deleted.isEmpty && added.isEmpty && modified.isEmpty {
            type = .removedFalsePositive
        } else {
            type = .edited
        }

        let categories = Array(Set(added.map { $0.type.rawValue }
                                   + deleted.map { $0.type.rawValue }
                                   + modified.map { $0.type.rawValue }))

        let correction = Correction(
            inspectionId: CorrectionsStore.deterministicUUID(from: inspectionId),
            photoId: CorrectionsStore.deterministicUUID(from: photo.id.uuidString),
            originalDetection: CorrectionsStore.encode(before),
            correctedDetection: CorrectionsStore.encode(after),
            correctionType: type,
            categoriesAffected: categories,
            delta: CorrectionsStore.encode(DetectionDelta(ops: ops)),
            correctedBy: CorrectionsStore.localUserId)
        CorrectionsStore.shared.append(correction)
    }

    // MARK: - Haptics

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Draft pin

private struct DraftPin: View {
    let draft: DraftMarker
    let selected: Bool
    let pulsing: Bool

    var body: some View {
        let size = max(28, min(110, draft.radius * 320))
        ZStack {
            if selected {
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: size + 12, height: size + 12)
            }
            Circle()
                .fill(draft.type.color.opacity(0.18))
                .overlay(Circle().stroke(draft.type.color, lineWidth: selected ? 3.5 : 2.2))
                .frame(width: size, height: size)
            Image(systemName: draft.type.icon)
                .font(.system(size: max(11, size * 0.34), weight: .heavy))
                .foregroundStyle(draft.type.color)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .scaleEffect(pulsing ? 1.18 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulsing)
        .animation(Theme.Motion.snappy, value: selected)
        .contentShape(Circle())
    }
}

// MARK: - Category chip

private struct CategoryChipView: View {
    let category: DamageMarkerType
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Circle()
                    .fill(category.color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.6))
                Text(category.display)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .foregroundStyle(selected ? .white : .white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(selected ? category.color.opacity(0.9) : Color.white.opacity(0.08),
                        in: .capsule)
            .overlay(Capsule().stroke(selected ? .white.opacity(0.5) : category.color.opacity(0.45),
                                      lineWidth: selected ? 1 : 1.2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Marker detail sheet (severity + voice note)

private struct MarkerDetailSheet: View {
    @Binding var draft: DraftMarker
    let speech: SpeechDictationService
    var onClose: () -> Void

    private let categories: [DamageMarkerType] = [
        .hailHits, .bruising, .granuleLoss, .windDamage, .windCreasing,
        .blistering, .cracking, .flashing, .algaeMoss, .missingShingles,
        .splitting, .lifted, .structuralSagging
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    severitySection
                    sizeSection
                    notesSection
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .background(Theme.canvas)
            .navigationTitle("Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(draft.type.color.opacity(0.18))
                Image(systemName: draft.type.icon)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(draft.type.color)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.type.display)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(draft.original == nil ? "Inspector-added" : "AI detection")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
    }

    private var severitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SEVERITY")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(1.2).foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("\(draft.severity) / 10 · \(severityName10(draft.severity))")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(findingSeverity10(draft.severity).color)
            }
            Slider(value: Binding(get: { Double(draft.severity) },
                                  set: { draft.severity = Int($0.rounded()) }),
                   in: 1...10, step: 1)
                .tint(Theme.ember)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MARKER SIZE")
                .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                .tracking(1.2).foregroundStyle(Theme.inkFaint)
            Slider(value: Binding(get: { draft.radius },
                                  set: { draft.radius = $0 }),
                   in: 0.015...0.18)
                .tint(Theme.ember)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NOTE")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(1.2).foregroundStyle(Theme.inkFaint)
                Spacer()
                voiceButton
            }
            TextField("Add an evidence note…", text: $draft.note, axis: .vertical)
                .font(.system(size: Theme.TypeRamp.body, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2...5)
                .padding(12)
                .background(Theme.canvas, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))

            if case .unavailable(let message) = speech.state {
                Text(message)
                    .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                    .foregroundStyle(Theme.crimson)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isListening, !newValue.isEmpty { draft.note = newValue }
        }
    }

    private var voiceButton: some View {
        Button {
            speech.toggle()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text(speech.isListening ? "Listening…" : "Dictate")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(speech.isListening ? Theme.crimson : Theme.ember, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
