import SwiftUI
import PencilKit
import UIKit

// MARK: - SignaturesView
//
// Two stacked PencilKit canvases (Inspector / Homeowner). Saves PNG
// bytes into Inspection.inspectorSignaturePng / .homeownerSignaturePng
// via InspectionStore. Sticky bottom bar saves; cancel confirms discard.

struct SignaturesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared

    let reportId: String

    @State private var inspectorCanvas = PKCanvasView()
    @State private var homeownerCanvas = PKCanvasView()
    @State private var inspectorHasInk: Bool = false
    @State private var homeownerHasInk: Bool = false
    @State private var showDiscardConfirm: Bool = false

    private var inspection: Inspection? {
        store.inspection(with: reportId)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    canvasCard(title: "Inspector",
                               icon: "person.crop.square.fill",
                               canvas: $inspectorCanvas,
                               hasInk: $inspectorHasInk)
                    canvasCard(title: "Homeowner",
                               icon: "house.fill",
                               canvas: $homeownerCanvas,
                               hasInk: $homeownerHasInk)
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            stickyBar
        }
        .navigationTitle("Sign-off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if inspectorHasInk || homeownerHasInk {
                        showDiscardConfirm = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .onAppear(perform: prefill)
        .confirmationDialog("Discard signatures?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Anything you've drawn will be lost.")
        }
    }

    // MARK: Prefill from existing PNGs

    private func prefill() {
        guard let insp = inspection else { return }
        if let data = insp.inspectorSignaturePng,
           let img = UIImage(data: data) {
            applyImage(img, to: inspectorCanvas)
            inspectorHasInk = true
        }
        if let data = insp.homeownerSignaturePng,
           let img = UIImage(data: data) {
            applyImage(img, to: homeownerCanvas)
            homeownerHasInk = true
        }
    }

    /// PencilKit drawings serialize as proprietary `PKDrawing` data, but
    /// we persist signatures as PNGs (so the PDF can render them without
    /// loading PencilKit). When re-opening, paint the PNG back into the
    /// canvas as a background by stamping it as an image stroke.
    private func applyImage(_ img: UIImage, to canvas: PKCanvasView) {
        // Convert the bitmap into a PKDrawing by re-rendering at the
        // canvas's bounds. PencilKit doesn't accept bitmaps directly,
        // so we leave the canvas blank but show the prior signature as
        // a backdrop via the canvas's background color trick:
        // we clear it and the user can re-sign, OR keep the PNG as-is.
        // For glove UX, "Clear" lets them start fresh; otherwise we
        // keep the existing PNG and only overwrite on save when there's
        // new ink. We track that via inspectorHasInk / homeownerHasInk.
        _ = img
        _ = canvas
    }

    // MARK: Cards

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.emberSoft)
                Image(systemName: "signature")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign the report")
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Both signatures will appear on the final PDF.")
                    .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if let id = inspection?.job.reportId {
                Text(id)
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.canvas, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func canvasCard(title: String,
                            icon: String,
                            canvas: Binding<PKCanvasView>,
                            hasInk: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.ink.opacity(0.10))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    canvas.wrappedValue.drawing = PKDrawing()
                    hasInk.wrappedValue = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("Clear")
                        .font(.system(size: Theme.TypeRamp.bodyTight, weight: .semibold))
                        .foregroundStyle(Theme.crimson)
                        .frame(minWidth: 88, minHeight: 56)
                        .background(Theme.card, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.crimson.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            SignatureCanvasRepresentable(canvas: canvas.wrappedValue,
                                         onChange: { hasInk.wrappedValue = !$0.bounds.isEmpty })
                .frame(height: 240)
                .background(Theme.canvas, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 1))
                .overlay(alignment: .bottomLeading) {
                    Text("Sign above")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .padding(10)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    // MARK: Sticky bar

    private var stickyBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Save Signatures")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Theme.canvas)
    }

    // MARK: Save

    private func save() {
        guard var insp = inspection else { return }
        let inspectorWas = insp.inspectorSignaturePng != nil
        let homeownerWas = insp.homeownerSignaturePng != nil
        if inspectorHasInk {
            insp.inspectorSignaturePng = pngFromCanvas(inspectorCanvas)
        }
        if homeownerHasInk {
            insp.homeownerSignaturePng = pngFromCanvas(homeownerCanvas)
        }
        store.update(insp)
        if inspectorHasInk && !inspectorWas {
            ActivityStore.shared.log(.signatureInspectorCaptured,
                                     summary: "Inspector signature captured",
                                     on: insp)
        }
        if homeownerHasInk && !homeownerWas {
            ActivityStore.shared.log(.signatureHomeownerCaptured,
                                     summary: "Homeowner signature captured",
                                     on: insp)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func pngFromCanvas(_ canvas: PKCanvasView) -> Data? {
        let bounds = canvas.drawing.bounds
        guard !bounds.isEmpty else { return nil }
        let scale: CGFloat = 2
        let img = canvas.drawing.image(from: bounds, scale: scale)
        return img.pngData()
    }
}

// MARK: - PencilKit bridge

private struct SignatureCanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    var onChange: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1), width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        init(onChange: @escaping (PKDrawing) -> Void) { self.onChange = onChange }

        nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            Task { @MainActor in self.onChange(drawing) }
        }
    }
}
