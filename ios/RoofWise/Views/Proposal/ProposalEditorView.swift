import SwiftUI

// MARK: - Steps

enum ProposalEditorStep: Int, CaseIterable, Identifiable {
    case cover, scope, lineItems, pricing, terms, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cover:     return "Cover"
        case .scope:     return "Scope"
        case .lineItems: return "Line Items"
        case .pricing:   return "Pricing"
        case .terms:     return "Terms"
        case .review:    return "Review"
        }
    }
}

// MARK: - Root wizard

struct ProposalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProposalStore.shared

    @State private var draft: Proposal
    @State private var step: ProposalEditorStep = .cover
    @State private var dirty: Bool = false
    @State private var showCancelConfirm: Bool = false
    @State private var editingItem: ProposalLineItem? = nil
    @State private var showSend: Bool = false

    private let inspection: Inspection?

    init(proposal: Proposal, inspection: Inspection? = nil) {
        _draft = State(initialValue: proposal)
        self.inspection = inspection
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                stepIndicator
                ScrollView {
                    Group {
                        switch step {
                        case .cover:     coverStep
                        case .scope:     scopeStep
                        case .lineItems: lineItemsStep
                        case .pricing:   pricingStep
                        case .terms:     termsStep
                        case .review:    reviewStep
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                footer
            }
            .background(Theme.canvas.ignoresSafeArea())
            .sheet(item: $editingItem) { item in
                LineItemEditSheet(item: item) { updated in
                    if let idx = draft.lineItems.firstIndex(where: { $0.id == updated.id }) {
                        draft.lineItems[idx] = updated
                        dirty = true
                    }
                }
            }
            .sheet(isPresented: $showSend) {
                ProposalSendSheet(proposal: draft) { sent in
                    store.update(sent)
                    if let insp = inspection {
                        ActivityStore.shared.log(
                            .proposalSent,
                            summary: "Proposal sent",
                            detail: sent.sentChannel?.rawValue,
                            on: insp
                        )
                    }
                    dismiss()
                }
            }
            .confirmationDialog("Discard this proposal?",
                                isPresented: $showCancelConfirm,
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Anything you've changed will be lost.")
            }
        }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            Button {
                if dirty { showCancelConfirm = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text("Proposal")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Step \(step.rawValue + 1) of \(ProposalEditorStep.allCases.count) · \(step.title)")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var stepIndicator: some View {
        let total = ProposalEditorStep.allCases.count
        let progress = CGFloat(step.rawValue + 1) / CGFloat(total)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(LinearGradient(
                    colors: [Theme.ember, Theme.amber],
                    startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 8)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    advance(by: -1)
                } label: {
                    Text("Back")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 140)
            }
            Button {
                if step == .review {
                    saveDraftAndSend()
                } else {
                    advance(by: 1)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(step == .review ? "Send to Homeowner" : "Next")
                    Image(systemName: step == .review ? "paperplane.fill" : "arrow.right")
                }
                .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 12)
        .background(Theme.canvas)
    }

    private func advance(by delta: Int) {
        let next = step.rawValue + delta
        guard let new = ProposalEditorStep(rawValue: next) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = new }
    }

    private func saveDraftAndSend() {
        var p = draft
        p.updatedAt = .now
        if store.find(byJobId: p.originJobId) != nil {
            store.update(p)
        } else {
            _ = store.create(p)
            if let insp = inspection {
                ActivityStore.shared.log(.proposalDrafted,
                                         summary: "Proposal drafted",
                                         on: insp)
            }
        }
        draft = p
        showSend = true
    }

    // MARK: Step 1 - Cover

    private var coverStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Homeowner")
            VoiceTextField(text: $draft.homeownerName,
                           placeholder: "Homeowner name",
                           onChange: { dirty = true })
            sectionLabel("Project Address")
            VoiceTextField(text: $draft.projectAddress,
                           placeholder: "Property address",
                           onChange: { dirty = true })
        }
    }

    // MARK: Step 2 - Scope

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("Scope of Work")
                Spacer()
                Button {
                    if let insp = inspection {
                        let regenerated = ProposalGenerator.generate(forInspection: insp)
                        draft.scopeNarrative = regenerated.scopeNarrative
                        dirty = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Regenerate")
                    }
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.emberSoft, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(inspection == nil)
            }
            VoiceTextEditor(text: $draft.scopeNarrative,
                            placeholder: "Describe the scope of work…",
                            minHeight: 240,
                            onChange: { dirty = true })
        }
    }

    // MARK: Step 3 - Line Items

    private var lineItemsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Line Items")
            VStack(spacing: 10) {
                ForEach(draft.lineItems) { item in
                    Button {
                        editingItem = item
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label)
                                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(String(format: "%.1f %@ × %@",
                                            item.quantity, item.unit,
                                            currency(item.unitPrice)))
                                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text(currency(item.totalPrice))
                                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .cardStyle(padding: 14, radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let new = ProposalLineItem(kind: .other, quantity: 1, unitPrice: 0)
                draft.lineItems.append(new)
                editingItem = new
                dirty = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                    Text("Add line item")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Step 4 - Pricing

    private var pricingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Totals")
            VStack(spacing: 10) {
                pricingRow("Subtotal", value: currency(draft.subtotal), emphasis: false)
                pricingRow(String(format: "Tax (%.2f%%)", draft.taxRate * 100),
                           value: currency(draft.tax), emphasis: false)
                pricingRow("Total", value: currency(draft.total), emphasis: true)
                pricingRow(String(format: "Deposit (%.0f%%)", draft.depositPct * 100),
                           value: currency(draft.depositAmount), emphasis: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)

            sectionLabel("Tax rate (%)")
            NumpadField(value: Binding(
                get: { draft.taxRate * 100 },
                set: { draft.taxRate = $0 / 100; dirty = true }
            ), suffix: "%")

            sectionLabel("Deposit (%)")
            NumpadField(value: Binding(
                get: { draft.depositPct * 100 },
                set: { draft.depositPct = $0 / 100; dirty = true }
            ), suffix: "%")
        }
    }

    private func pricingRow(_ label: String, value: String, emphasis: Bool) -> some View {
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
        .frame(minHeight: 36)
    }

    // MARK: Step 5 - Terms

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Warranty")
            VoiceTextEditor(text: $draft.warrantyTerms,
                            placeholder: "Warranty terms…",
                            minHeight: 140,
                            onChange: { dirty = true })
            sectionLabel("Payment Schedule")
            VoiceTextEditor(text: $draft.paymentSchedule,
                            placeholder: "Payment schedule…",
                            minHeight: 140,
                            onChange: { dirty = true })
            sectionLabel("Valid Until")
            DatePicker("", selection: $draft.validUntil, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 14)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 1))
                .onChange(of: draft.validUntil) { _, _ in dirty = true }
        }
    }

    // MARK: Step 6 - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            reviewCard(title: "Cover") {
                Text(draft.homeownerName.isEmpty ? "—" : draft.homeownerName)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(draft.projectAddress.isEmpty ? "—" : draft.projectAddress)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            reviewCard(title: "Scope") {
                Text(draft.scopeNarrative.isEmpty ? "—" : draft.scopeNarrative)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            reviewCard(title: "Line Items") {
                VStack(spacing: 6) {
                    ForEach(draft.lineItems) { item in
                        HStack {
                            Text(item.label)
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                            Spacer()
                            Text(currency(item.totalPrice))
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                    }
                }
            }
            reviewCard(title: "Totals") {
                HStack {
                    Text("Total").font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Spacer()
                    Text(currency(draft.total))
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .monospacedDigit()
                }
                HStack {
                    Text("Deposit").font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(currency(draft.depositAmount))
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func reviewCard<Content: View>(title: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
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
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Voice text controls (mic stub)

struct VoiceTextField: View {
    @Binding var text: String
    let placeholder: String
    var onChange: () -> Void = {}
    @State private var listening = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                listening.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(listening ? Theme.ember : Theme.inkSoft)
                    .frame(width: 44, height: 44)
                    .background(listening ? Theme.emberSoft : Theme.canvas, in: .circle)
            }
            .buttonStyle(.plain)
            TextField(placeholder, text: $text)
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .onChange(of: text) { _, _ in onChange() }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }
}

struct VoiceTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 140
    var onChange: () -> Void = {}
    @State private var listening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 14)
                        .padding(.leading, 16)
                }
                TextEditor(text: $text)
                    .font(.system(size: Theme.TypeRamp.body, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: minHeight)
                    .onChange(of: text) { _, _ in onChange() }
            }
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))

            Button {
                listening.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: listening ? "mic.fill" : "mic")
                    Text(listening ? "Listening…" : "Voice input")
                }
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(listening ? Theme.ember : Theme.inkSoft)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(listening ? Theme.emberSoft : Theme.canvas, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Numpad field

struct NumpadField: View {
    @Binding var value: Double
    var suffix: String = ""

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .onAppear { text = formatted(value) }
                .onChange(of: text) { _, new in
                    if let v = Double(new.replacingOccurrences(of: ",", with: ".")) {
                        value = v
                    }
                }
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    private func formatted(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Line item edit sheet

struct LineItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ProposalLineItem
    let onSave: (ProposalLineItem) -> Void
    @State private var showKindMenu = false

    init(item: ProposalLineItem, onSave: @escaping (ProposalLineItem) -> Void) {
        _item = State(initialValue: item)
        self.onSave = onSave
    }

    private let units = ["sq", "lf", "ea", "hr", "sf"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionLabel("Kind")
                    Button { showKindMenu = true } label: {
                        HStack {
                            Text(item.kind.displayName)
                                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .background(Theme.card, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Change kind",
                                        isPresented: $showKindMenu,
                                        titleVisibility: .visible) {
                        ForEach(ProposalLineItemKind.allCases, id: \.self) { k in
                            Button(k.displayName) {
                                item.kind = k
                                if item.label.isEmpty { item.label = k.displayName }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }

                    sectionLabel("Label")
                    VoiceTextField(text: $item.label, placeholder: "Label")

                    sectionLabel("Quantity")
                    HStack(spacing: 12) {
                        stepperButton("minus") { item.quantity = max(0, item.quantity - 1) }
                        NumpadField(value: $item.quantity)
                        stepperButton("plus") { item.quantity += 1 }
                    }

                    sectionLabel("Unit")
                    HStack(spacing: 8) {
                        ForEach(units, id: \.self) { u in
                            Button {
                                item.unit = u
                            } label: {
                                Text(u)
                                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                                    .foregroundStyle(item.unit == u ? .white : Theme.ink)
                                    .frame(minWidth: 56, minHeight: 56)
                                    .background(item.unit == u ? Theme.ink : Theme.card,
                                                in: .rect(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionLabel("Unit Price")
                    NumpadField(value: $item.unitPrice, suffix: "$")

                    sectionLabel("Total")
                    Text(currency(item.totalPrice))
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .background(Theme.canvas)
            .navigationTitle("Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(item); dismiss()
                    }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private func stepperButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 64, height: 64)
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
