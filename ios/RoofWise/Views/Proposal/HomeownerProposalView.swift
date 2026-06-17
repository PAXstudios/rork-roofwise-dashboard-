import SwiftUI
import PencilKit

/// Homeowner-facing read-only viewer. Reachable via the share link OR via the
/// debug menu. Renders the proposal as a clean public-facing layout and
/// presents a PencilKit signature sheet when the homeowner taps "Sign Proposal".
struct HomeownerProposalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProposalStore.shared

    let proposalId: UUID

    @State private var showSignSheet = false

    private var proposal: Proposal? {
        store.proposals.first { $0.id == proposalId }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                if let p = proposal {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard(p)
                        scopeCard(p)
                        lineItemsCard(p)
                        totalsCard(p)
                        termsCard(p)
                        if p.status == .signed {
                            signedBanner(p)
                        }
                        Color.clear.frame(height: 140)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                } else {
                    Text("Proposal not found.")
                        .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 80)
                }
            }

            if let p = proposal, p.status != .signed {
                signCTA(p)
            }
        }
        .navigationTitle("Your Proposal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
        }
        .onAppear {
            if let p = proposal, p.status == .sent {
                store.markViewed(id: p.id)
                ActivityStore.shared.log(.proposalViewed,
                                         summary: "Proposal viewed by homeowner",
                                         reportId: p.originJobId)
            }
        }
        .sheet(isPresented: $showSignSheet) {
            if let p = proposal {
                SignProposalSheet(proposal: p) { png in
                    store.markSigned(id: p.id, signature: png)
                    ActivityStore.shared.log(.proposalSigned,
                                             summary: "Proposal signed",
                                             reportId: p.originJobId)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    // MARK: Cards

    private func headerCard(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROOFWISE PROPOSAL")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.ember)
            Text(p.homeownerName.isEmpty ? "Homeowner" : p.homeownerName)
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(p.projectAddress.isEmpty ? "—" : p.projectAddress)
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            statusPill(p)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }

    private func scopeCard(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Scope of Work")
            Text(p.scopeNarrative.isEmpty ? "—" : p.scopeNarrative)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .regular))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }

    private func lineItemsCard(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Line Items")
            VStack(spacing: 8) {
                ForEach(p.lineItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text(String(format: "%.1f %@", item.quantity, item.unit))
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text(currency(item.totalPrice))
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }

    private func totalsCard(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Subtotal", value: currency(p.subtotal))
            row(String(format: "Tax (%.2f%%)", p.taxRate * 100),
                value: currency(p.tax))
            Divider()
            row("Total", value: currency(p.total), emphasis: true)
            row(String(format: "Deposit (%.0f%%)", p.depositPct * 100),
                value: currency(p.depositAmount))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }

    private func termsCard(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Warranty")
            Text(p.warrantyTerms)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .regular))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            sectionLabel("Payment Schedule")
            Text(p.paymentSchedule)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .regular))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            sectionLabel("Valid Until")
            Text(p.validUntil.formatted(date: .long, time: .omitted))
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }

    private func signedBanner(_ p: Proposal) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signed")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Signed on \((p.signedAt ?? .now).formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.mintSoft, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.mint.opacity(0.3), lineWidth: 1))
    }

    private func signCTA(_ p: Proposal) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSignSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "signature")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    Text("Sign Proposal")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.canvas)
    }

    // MARK: Bits

    private func statusPill(_ p: Proposal) -> some View {
        let (bg, fg): (Color, Color) = {
            switch p.status {
            case .draft:    return (Theme.canvas, Theme.inkSoft)
            case .sent:     return (Theme.amberSoft, Theme.amber)
            case .viewed:   return (Theme.skySoft, Theme.sky)
            case .signed:   return (Theme.mintSoft, Theme.mint)
            case .declined: return (Theme.emberSoft, Theme.crimson)
            case .expired:  return (Theme.canvas, Theme.inkFaint)
            }
        }()
        return Text(p.status.displayName)
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg, in: .capsule)
    }

    private func row(_ label: String, value: String, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: emphasis ? Theme.TypeRamp.body : Theme.TypeRamp.subhead,
                              weight: emphasis ? .heavy : .semibold))
                .foregroundStyle(emphasis ? Theme.ink : Theme.inkSoft)
            Spacer()
            Text(value)
                .font(.system(size: emphasis ? Theme.TypeRamp.titleSm : Theme.TypeRamp.body,
                              weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(Theme.inkSoft)
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Sign sheet

struct SignProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let proposal: Proposal
    let onSigned: (Data?) -> Void

    @State private var canvas = PKCanvasView()
    @State private var hasInk = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign below to accept this proposal")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ProposalSignatureCanvas(canvas: canvas) { drawing in
                    hasInk = !drawing.bounds.isEmpty
                }
                .frame(height: 280)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button {
                        canvas.drawing = PKDrawing()
                        hasInk = false
                    } label: {
                        Text("Clear")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                            .foregroundStyle(Theme.crimson)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Theme.card, in: .rect(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(Theme.crimson.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        let bounds = canvas.drawing.bounds
                        let img: Data?
                        if !bounds.isEmpty {
                            img = canvas.drawing.image(from: bounds, scale: 2).pngData()
                        } else {
                            img = nil
                        }
                        onSigned(img)
                        dismiss()
                    } label: {
                        Text("Save Signature")
                            .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(hasInk ? AnyShapeStyle(Theme.inkGradient)
                                               : AnyShapeStyle(Theme.inkFaint),
                                        in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasInk)
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .background(Theme.canvas)
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

private struct ProposalSignatureCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    var onChange: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen,
                                   color: UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1),
                                   width: 4)
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
