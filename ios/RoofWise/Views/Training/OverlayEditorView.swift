import SwiftUI
import UIKit

/// Phase 9B. Lightweight editor that captures inspector edits as a
/// `DetectionDelta`. Real per-marker geometry is intentionally minimal here —
/// we wire the user actions to the delta surface so corrections flow into
/// CorrectionsStore; full canvas geometry comes when photo bytes are wired.
struct OverlayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: TrainingItem
    let onSave: (DetectionDelta) -> Void

    @State private var ops: [DetectionDeltaOp] = []
    @State private var markers: [EditMarker] = []
    @State private var showDiscardConfirm: Bool = false
    @State private var showCategoryPicker: Bool = false
    @State private var showMarkerActions: Bool = false
    @State private var addMode: Bool = false
    @State private var pendingPoint: CGPoint? = nil
    @State private var pickedCategory: String? = nil
    @State private var pickedSeverity: String? = nil
    @State private var note: String = ""
    /// When set, the next canvas tap relocates this marker (Move action).
    @State private var moveModeMarkerId: UUID? = nil
    /// Marker currently targeted by the action dialog / category re-pick.
    @State private var selectedMarkerId: UUID? = nil
    /// When set, the category sheet re-categorizes this existing marker.
    @State private var recategorizeMarkerId: UUID? = nil

    /// A locally-editable damage marker rendered on the canvas.
    private struct EditMarker: Identifiable {
        let id: UUID
        var x: Double
        var y: Double
        var radius: Double
        var category: DamageMarkerType
        var severity: String
    }

    /// Canonical 13 pitch-deck categories, in deck order. Labels + colors are
    /// sourced from `DamageMarkerType` so they auto-sync if the enum changes.
    private let categories: [DamageMarkerType] = [
        .hailHits, .bruising, .granuleLoss, .windDamage, .windCreasing,
        .blistering, .cracking, .flashing, .algaeMoss, .missingShingles,
        .splitting, .lifted, .structuralSagging
    ]
    private let severities: [String] = ["Minor", "Moderate", "Severe"]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    canvas
                    deltaSummary
                    Color.clear.frame(height: 140)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            saveBar
        }
        .navigationTitle("Edit detections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if ops.isEmpty { dismiss() } else { showDiscardConfirm = true }
                }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addFab
                .padding(.trailing, 20)
                .padding(.bottom, 120)
        }
        .sheet(isPresented: $showCategoryPicker) { categorySheet }
        .confirmationDialog("Marker", isPresented: $showMarkerActions, titleVisibility: .visible) {
            Button("Move") {
                moveModeMarkerId = selectedMarkerId
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            Button("Resize") { resizeSelectedMarker() }
            Button("Change Category") {
                recategorizeMarkerId = selectedMarkerId
                pickedCategory = nil
                pickedSeverity = nil
                showCategoryPicker = true
            }
            Button("Delete", role: .destructive) { deleteSelectedMarker() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(moveModeMarkerId == nil ? "Edit this marker." : "Tap the photo to move it.")
        }
        .confirmationDialog("Discard changes?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("You have \(ops.count) unsaved edit\(ops.count == 1 ? "" : "s") on this photo.")
        }
    }

    // MARK: Header / canvas

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.kind.displayName)
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("\(item.aiCount) AI markers · \(item.slopeOrientation) slope")
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.amberSoft)
                if markers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                        Text(addMode ? "Tap the photo to drop a marker" : "Add missed damage")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(addMode ? "Pick a category, then severity" : "Use the + Add Damage button to start")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
                ForEach(markers) { marker in
                    let size = dotSize(marker, in: geo.size)
                    Circle()
                        .fill(marker.category.color.opacity(0.22))
                        .overlay(Circle().stroke(marker.category.color, lineWidth: 2.5))
                        .frame(width: size, height: size)
                        .position(x: geo.size.width * marker.x, y: geo.size.height * marker.y)
                        .onTapGesture {
                            selectedMarkerId = marker.id
                            showMarkerActions = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleCanvasTap(location, in: geo.size)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(addMode ? Theme.ember : Theme.hairline,
                                                            lineWidth: addMode ? 2 : 0.6))
    }

    /// Floating action button that toggles "drop a marker" mode.
    private var addFab: some View {
        Button {
            addMode.toggle()
            moveModeMarkerId = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: addMode ? "xmark" : "plus")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Text(addMode ? "Done" : "Add Damage")
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(addMode ? Theme.crimson : Theme.ember, in: .capsule)
            .shadow(color: Theme.ember.opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var deltaSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EDITS")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            if ops.isEmpty {
                Text("No edits yet")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(Array(ops.enumerated()), id: \.offset) { _, op in
                    HStack(spacing: 10) {
                        Image(systemName: op.kind == .added ? "plus.circle.fill"
                              : op.kind == .deleted ? "minus.circle.fill"
                              : "pencil.circle.fill")
                            .foregroundStyle(op.kind == .added ? Theme.mint : Theme.crimson)
                        Text("\(op.kind.rawValue.capitalized) · \(op.category ?? "—") · \(op.severity ?? "")")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private var saveBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSave(DetectionDelta(ops: ops))
            dismiss()
        } label: {
            Text("Save")
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.25), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Theme.canvas)
    }

    // MARK: Category sheet

    private var categorySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Category")
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(categories, id: \.self) { (cat: DamageMarkerType) in
                        CategoryChip(category: cat,
                                     isPicked: pickedCategory == cat.rawValue) {
                            pickedCategory = cat.rawValue
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }

                Text("Severity")
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    ForEach(severities, id: \.self) { sev in
                        Button {
                            pickedSeverity = sev
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(sev)
                                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                                .foregroundStyle(pickedSeverity == sev ? .white : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(pickedSeverity == sev ? Theme.ember : Theme.card,
                                            in: .rect(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    addMarker()
                } label: {
                    Text("Add")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(canAdd ? Theme.inkGradient
                                    : LinearGradient(colors: [Theme.inkFaint, Theme.inkFaint],
                                                     startPoint: .top, endPoint: .bottom),
                                    in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("New marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCategoryPicker = false
                    }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var canAdd: Bool {
        pickedCategory != nil && pickedSeverity != nil
    }

    // MARK: Geometry / interactions

    private func dotSize(_ marker: EditMarker, in size: CGSize) -> CGFloat {
        let minEdge = min(size.width, size.height)
        return max(24, minEdge * CGFloat(marker.radius) * 2)
    }

    private func clamp01(_ value: CGFloat) -> Double {
        Double(min(1, max(0, value)))
    }

    private func handleCanvasTap(_ location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        // Move mode: relocate the selected marker to the tapped point.
        if let id = moveModeMarkerId {
            let nx = clamp01(location.x / size.width)
            let ny = clamp01(location.y / size.height)
            if let idx = markers.firstIndex(where: { $0.id == id }) {
                markers[idx].x = nx
                markers[idx].y = ny
            }
            ops.append(DetectionDeltaOp(kind: .moved, markerId: id,
                                        x: nx, y: ny, radius: nil,
                                        category: nil, severity: nil, note: nil))
            moveModeMarkerId = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        // Add mode: drop a new marker at the tapped (normalized) point.
        guard addMode else { return }
        pendingPoint = CGPoint(x: clamp01(location.x / size.width),
                               y: clamp01(location.y / size.height))
        pickedCategory = nil
        pickedSeverity = nil
        recategorizeMarkerId = nil
        showCategoryPicker = true
    }

    private func resizeSelectedMarker() {
        guard let id = selectedMarkerId,
              let idx = markers.firstIndex(where: { $0.id == id }) else { return }
        let steps: [Double] = [0.03, 0.05, 0.08, 0.12]
        let current = markers[idx].radius
        let next = steps.first(where: { $0 > current + 0.001 }) ?? steps[0]
        markers[idx].radius = next
        ops.append(DetectionDeltaOp(kind: .resized, markerId: id,
                                    x: nil, y: nil, radius: next,
                                    category: nil, severity: nil, note: nil))
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func deleteSelectedMarker() {
        guard let id = selectedMarkerId else { return }
        markers.removeAll { $0.id == id }
        ops.append(DetectionDeltaOp(kind: .deleted, markerId: id,
                                    x: nil, y: nil, radius: nil,
                                    category: nil, severity: nil, note: nil))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Single damage-category chip — label + color sourced from `DamageMarkerType`.
    private struct CategoryChip: View {
        let category: DamageMarkerType
        let isPicked: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                Text(category.display)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isPicked ? Color.white : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .cardStyle(padding: 8, radius: 12)
                    .background(isPicked ? category.color : Color.clear,
                                in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(category.color.opacity(isPicked ? 0 : 0.55), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func addMarker() {
        guard let cat = pickedCategory, let sev = pickedSeverity else { return }
        let type = DamageMarkerType(rawValue: cat) ?? .hailHits
        // Re-categorize an existing marker rather than adding a new one.
        if let editId = recategorizeMarkerId {
            if let idx = markers.firstIndex(where: { $0.id == editId }) {
                markers[idx].category = type
                markers[idx].severity = sev
            }
            ops.append(DetectionDeltaOp(kind: .recategorized, markerId: editId,
                                        x: nil, y: nil, radius: nil,
                                        category: cat, severity: sev, note: nil))
            recategorizeMarkerId = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showCategoryPicker = false
            return
        }
        // pendingPoint is already normalized to the canvas rect.
        let p = pendingPoint ?? CGPoint(x: 0.5, y: 0.5)
        let newId = UUID()
        markers.append(EditMarker(id: newId, x: Double(p.x), y: Double(p.y),
                                  radius: 0.04, category: type, severity: sev))
        ops.append(DetectionDeltaOp(
            kind: .added,
            markerId: newId,
            x: Double(p.x),
            y: Double(p.y),
            radius: 0.04,
            category: cat,
            severity: sev,
            note: note.isEmpty ? nil : note
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showCategoryPicker = false
    }
}
