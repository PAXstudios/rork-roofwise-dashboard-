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
    @State private var showCategoryPicker: Bool = false
    @State private var pendingPoint: CGPoint? = nil
    @State private var pickedCategory: String? = nil
    @State private var pickedSeverity: String? = nil
    @State private var note: String = ""

    private let categories: [String] = ["Hail", "Wind", "Wear", "Missing",
                                         "Bruise", "ExposedMat", "Lifted", "Torn"]
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
                Button("Cancel") { dismiss() }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
        }
        .sheet(isPresented: $showCategoryPicker) { categorySheet }
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
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Theme.amberSoft)
            VStack(spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                Text("Tap to add missed damage")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Long-press an existing marker to remove")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
        .contentShape(Rectangle())
        .onTapGesture { location in
            pendingPoint = location
            pickedCategory = nil
            pickedSeverity = nil
            showCategoryPicker = true
        }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            pickedCategory = cat
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(cat)
                                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                                .foregroundStyle(pickedCategory == cat ? .white : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(pickedCategory == cat ? Theme.ember : Theme.card,
                                            in: .rect(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
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

    private func addMarker() {
        guard let cat = pickedCategory, let sev = pickedSeverity else { return }
        let p = pendingPoint ?? CGPoint(x: 0.5, y: 0.5)
        ops.append(DetectionDeltaOp(
            kind: .added,
            markerId: UUID(),
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
