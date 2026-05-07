import SwiftUI

struct OverlayEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let item: ReviewPhotoItem
    var onSave: (DetectionDelta, [EditableDamageMarker], CorrectionType) -> Void

    @State private var markers: [EditableDamageMarker]
    @State private var selectedMarker: EditableDamageMarker? = nil
    @State private var markerAction: EditableDamageMarker? = nil
    @State private var isDroppingMarker: Bool = false
    @State private var pendingPoint: CGPoint? = nil
    @State private var showAddSheet: Bool = false
    @State private var scale: CGFloat = 1
    @State private var notesDraft: String = ""
    @State private var showDiscardConfirm: Bool = false

    init(item: ReviewPhotoItem,
         onSave: @escaping (DetectionDelta, [EditableDamageMarker], CorrectionType) -> Void) {
        self.item = item
        self.onSave = onSave
        _markers = State(initialValue: item.markers)
    }

    private var delta: DetectionDelta {
        DetectionDelta(operations: MarkerDeltaBuilder.delta(from: item.markers, to: markers))
    }

    private var isDirty: Bool { !delta.operations.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    editorCanvas
                    bottomBar
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isDroppingMarker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        Text("Add Damage")
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 64)
                    .padding(.horizontal, 18)
                    .background(Theme.ember, in: .rect(cornerRadius: 18))
                    .shadow(color: Theme.ember.opacity(0.28), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 112)
            }
            .navigationTitle("Edit AI markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if isDirty { showDiscardConfirm = true } else { dismiss() }
                    }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
            .confirmationDialog("Marker",
                                isPresented: Binding(
                                    get: { markerAction != nil },
                                    set: { if !$0 { markerAction = nil } }
                                ),
                                titleVisibility: .visible) {
                if let marker = markerAction {
                    Button("Move") { selectedMarker = marker; isDroppingMarker = true; markerAction = nil }
                    Button("Resize larger") { resize(marker, by: 0.012); markerAction = nil }
                    Button("Resize smaller") { resize(marker, by: -0.012); markerAction = nil }
                    Button("Change Category") { selectedMarker = marker; pendingPoint = CGPoint(x: marker.x, y: marker.y); showAddSheet = true; markerAction = nil }
                    Button("Delete", role: .destructive) { delete(marker); markerAction = nil }
                }
                Button("Cancel", role: .cancel) { markerAction = nil }
            }
            .sheet(isPresented: $showAddSheet) {
                MarkerEditSheet(
                    marker: selectedMarker,
                    initialNote: notesDraft,
                    onCancel: {
                        showAddSheet = false
                        selectedMarker = nil
                        pendingPoint = nil
                    },
                    onSave: { category, severity, note in
                        saveMarker(category: category, severity: severity, note: note)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog("Discard marker edits?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your marker corrections have not been saved.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.verdict)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(isDroppingMarker ? "Tap the photo to place or move the marker." : "Tap a marker for Move / Resize / Delete / Change Category.")
                        .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text("\(markers.count)")
                    .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .monospacedDigit()
            }
            confidenceChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var confidenceChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
            ForEach(item.snapshot.categories) { category in
                Text("\(category.kind.displayName) \(Int((category.confidence * 100).rounded()))%")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(category.confidence < 0.6 ? Theme.crimson : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background((category.confidence < 0.6 ? Theme.emberSoft : Theme.canvas), in: .rect(cornerRadius: 12))
            }
        }
    }

    private var editorCanvas: some View {
        GeometryReader { geo in
            ZStack {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(MagnifyGesture().onChanged { value in
                            scale = max(1, min(4, value.magnification))
                        })
                        .allowsHitTesting(!isDroppingMarker)
                } else {
                    roofPlaceholder
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                }

                ForEach(markers) { marker in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        markerAction = marker
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.ember.opacity(0.36))
                                .frame(width: markerSize(marker), height: markerSize(marker))
                            Circle()
                                .stroke(Theme.ember, lineWidth: 3)
                                .frame(width: markerSize(marker), height: markerSize(marker))
                            Image(systemName: marker.category.markerType.icon)
                                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .position(x: marker.x * geo.size.width, y: marker.y * geo.size.height)
                }

                if isDroppingMarker {
                    Color.black.opacity(0.001)
                        .contentShape(.rect)
                        .onTapGesture { point in
                            pendingPoint = CGPoint(x: max(0, min(1, point.x / max(geo.size.width, 1))),
                                                   y: max(0, min(1, point.y / max(geo.size.height, 1))))
                            notesDraft = selectedMarker?.note ?? ""
                            showAddSheet = true
                            isDroppingMarker = false
                        }
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        Text("Tap damage spot")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(Theme.scrim, in: .rect(cornerRadius: 18))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var roofPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink, Theme.inkRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.82))
                Text("AI overlay review")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Photo not retained in this mock session; marker deltas still persist for training.")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                let correctionType: CorrectionType = delta.operations.contains(where: { $0.op == .added }) ? .addedMissed : .edited
                onSave(delta, markers, correctionType)
                dismiss()
            } label: {
                Text("Save corrections")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!isDirty)
            .opacity(isDirty ? 1 : 0.45)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(minHeight: 88)
        .background(Theme.canvas.overlay(Rectangle().fill(Theme.hairline).frame(height: 0.5), alignment: .top))
    }

    private func markerSize(_ marker: EditableDamageMarker) -> CGFloat {
        max(44, min(86, CGFloat(marker.radius) * 900))
    }

    private func resize(_ marker: EditableDamageMarker, by amount: Double) {
        guard let index = markers.firstIndex(where: { $0.id == marker.id }) else { return }
        markers[index].radius = max(0.006, min(0.16, markers[index].radius + amount))
    }

    private func delete(_ marker: EditableDamageMarker) {
        markers.removeAll { $0.id == marker.id }
    }

    private func saveMarker(category: ReviewDamageCategory, severity: AIDamageCategorySeverity, note: String) {
        guard let point = pendingPoint else { return }
        if let selectedMarker, let index = markers.firstIndex(where: { $0.id == selectedMarker.id }) {
            markers[index].x = Double(point.x)
            markers[index].y = Double(point.y)
            markers[index].category = category
            markers[index].severity = severity
            markers[index].note = note
        } else {
            markers.append(EditableDamageMarker(x: Double(point.x),
                                                y: Double(point.y),
                                                radius: 0.028,
                                                category: category,
                                                severity: severity,
                                                note: note,
                                                confidence: 1))
        }
        selectedMarker = nil
        pendingPoint = nil
        showAddSheet = false
    }
}

private struct MarkerEditSheet: View {
    let marker: EditableDamageMarker?
    let initialNote: String
    let onCancel: () -> Void
    let onSave: (ReviewDamageCategory, AIDamageCategorySeverity, String) -> Void

    @State private var category: ReviewDamageCategory
    @State private var severity: AIDamageCategorySeverity
    @State private var note: String

    init(marker: EditableDamageMarker?,
         initialNote: String,
         onCancel: @escaping () -> Void,
         onSave: @escaping (ReviewDamageCategory, AIDamageCategorySeverity, String) -> Void) {
        self.marker = marker
        self.initialNote = initialNote
        self.onCancel = onCancel
        self.onSave = onSave
        _category = State(initialValue: marker?.category ?? .hail)
        _severity = State(initialValue: marker?.severity ?? .moderate)
        _note = State(initialValue: marker?.note ?? initialNote)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(marker == nil ? "Add missed damage" : "Update marker")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    chipGrid(title: "Category", options: ReviewDamageCategory.allCases, selected: $category) { $0.displayName }
                    severityGrid
                    noteField
                    Color.clear.frame(height: 90)
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                    Button {
                        onSave(category, severity, note)
                    } label: {
                        Text("Save Marker")
                            .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(Theme.canvas)
            }
        }
    }

    private func chipGrid<T: Hashable>(title: String,
                                       options: [T],
                                       selected: Binding<T>,
                                       label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button { selected.wrappedValue = option } label: {
                        Text(label(option))
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(selected.wrappedValue == option ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(selected.wrappedValue == option ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: selected.wrappedValue == option ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var severityGrid: some View {
        chipGrid(title: "Severity", options: AIDamageCategorySeverity.allCasesForUI, selected: $severity) { severity in
            switch severity {
            case .minor: return "Minor"
            case .moderate: return "Moderate"
            case .severe: return "Severe"
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: .rect(cornerRadius: 12))
                TextEditor(text: $note)
                    .font(.system(size: Theme.TypeRamp.body))
                    .frame(minHeight: 104)
                    .scrollContentBackground(.hidden)
            }
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

private enum MarkerDeltaBuilder {
    static func delta(from original: [EditableDamageMarker], to corrected: [EditableDamageMarker]) -> [MarkerOperation] {
        var operations: [MarkerOperation] = []
        let originalById = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        let correctedById = Dictionary(uniqueKeysWithValues: corrected.map { ($0.id, $0) })

        for marker in corrected where originalById[marker.id] == nil {
            operations.append(MarkerOperation(markerId: marker.id, op: .added, before: nil, after: marker))
        }
        for marker in original where correctedById[marker.id] == nil {
            operations.append(MarkerOperation(markerId: marker.id, op: .deleted, before: marker, after: nil))
        }
        for marker in corrected {
            guard let old = originalById[marker.id], old != marker else { continue }
            let op: MarkerOperationKind
            if old.category != marker.category { op = .recategorized }
            else if abs(old.radius - marker.radius) > 0.001 { op = .resized }
            else { op = .moved }
            operations.append(MarkerOperation(markerId: marker.id, op: op, before: old, after: marker))
        }
        return operations
    }
}

private extension AIDamageCategorySeverity {
    static var allCasesForUI: [AIDamageCategorySeverity] { [.minor, .moderate, .severe] }
}
