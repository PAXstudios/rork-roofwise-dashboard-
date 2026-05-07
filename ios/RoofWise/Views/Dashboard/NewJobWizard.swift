import SwiftUI

// MARK: - Steps

enum InspectionWizardStep: Int, CaseIterable, Identifiable {
    case customer, insurance, roof, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .customer:  return "Customer & Property"
        case .insurance: return "Insurance"
        case .roof:      return "Roof System"
        case .review:    return "Review"
        }
    }
}

// MARK: - Carrier list

private let kCarriers: [String] = [
    "State Farm", "Allstate", "USAA", "Farmers",
    "Liberty Mutual", "Travelers", "Nationwide", "Other"
]

// MARK: - Root wizard

struct NewJobWizard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared

    // Optional contact fields not in the JSON schema (kept on the wizard only).
    @State private var phone: String = ""
    @State private var email: String = ""

    // Working draft
    @State private var draft: Inspection = InspectionStore.shared.makeDraft()

    @State private var step: InspectionWizardStep = .customer
    @State private var showCancelConfirm = false
    @State private var createdReportId: String? = nil

    var onCreated: (String) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                stepIndicator
                ScrollView {
                    Group {
                        switch step {
                        case .customer:
                            CustomerStep(draft: $draft, phone: $phone, email: $email)
                        case .insurance:
                            InsuranceStep(draft: $draft)
                        case .roof:
                            RoofStep(draft: $draft)
                        case .review:
                            ReviewStep(draft: $draft, phone: phone, email: email,
                                       onJump: { jump(to: $0) })
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
            .navigationDestination(item: $createdReportId) { rid in
                JobDetailView(reportId: rid)
            }
        }
        .confirmationDialog("Discard this job?",
                            isPresented: $showCancelConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Anything you've entered will be lost.")
        }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button {
                showCancelConfirm = true
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
                Text("New Job")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Step \(step.rawValue + 1) of \(InspectionWizardStep.allCases.count) · \(step.title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var stepIndicator: some View {
        let total = InspectionWizardStep.allCases.count
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

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    advance(by: -1)
                } label: {
                    Text("Back")
                        .font(.system(size: 18, weight: .semibold))
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
                    create()
                } else {
                    advance(by: 1)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(step == .review ? "Create Job" : "Next")
                    Image(systemName: step == .review ? "checkmark" : "arrow.right")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    LinearGradient(
                        colors: canAdvance
                            ? [Theme.ink, Theme.inkRaised]
                            : [Theme.inkFaint, Theme.inkFaint],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 18)
                )
                .shadow(color: canAdvance ? Theme.ink.opacity(0.28) : .clear,
                        radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .background(Theme.canvas)
    }

    private var canAdvance: Bool {
        switch step {
        case .customer:
            let nameOK = !draft.job.clientName.trimmingCharacters(in: .whitespaces).isEmpty
            let addrOK = !draft.job.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty
            return nameOK && addrOK
        default:
            return true
        }
    }

    private func advance(by delta: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = step.rawValue + delta
        guard let s = InspectionWizardStep(rawValue: next) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = s
        }
    }

    private func jump(to s: InspectionWizardStep) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = s
        }
    }

    // MARK: create

    private func create() {
        // Stamp inspection/report dates at creation time.
        draft.job.inspectionDate = .now
        draft.job.reportDate = .now
        let saved = store.add(draft)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCreated(saved.job.reportId)
        createdReportId = saved.job.reportId
    }
}

// MARK: - Reusable form components

private struct WizardSection<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.emberSoft)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            content()
        }
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.inkSoft)
            .tracking(0.6)
    }
}

private struct MicField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    // Voice-input stub: hooked up when real dictation lands.
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 56, height: 56)
                        .background(Theme.emberSoft, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}

private struct ChipGrid<T: Hashable & Identifiable>: View where T.ID == String {
    let label: String
    let options: [T]
    @Binding var selection: T
    var minimum: CGFloat = 150
    let title: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
                ForEach(options) { opt in
                    let selected = opt == selection
                    Button {
                        selection = opt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(title(opt))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .padding(.horizontal, 12)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StringChipGrid: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    var minimum: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { opt in
                    let selected = opt == selection
                    Button {
                        selection = opt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(opt)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .padding(.horizontal, 12)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BigStepper: View {
    let label: String
    @Binding var value: Int
    var step: Int = 1
    var range: ClosedRange<Int>
    var format: (Int) -> String = { String($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 12) {
                Button {
                    value = max(range.lowerBound, value - step)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(value <= range.lowerBound ? Theme.inkFaint : Theme.ink)
                        .frame(width: 64, height: 64)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text(format(value))
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .padding(.horizontal, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.hairline, lineWidth: 1))

                Button {
                    value = min(range.upperBound, value + step)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Theme.ember, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }
        }
    }
}

// MARK: - Step 1: Customer & Property

private struct CustomerStep: View {
    @Binding var draft: Inspection
    @Binding var phone: String
    @Binding var email: String

    var body: some View {
        WizardSection(
            title: "Customer & Property",
            subtitle: "Who's the homeowner and where's the roof?",
            icon: "person.crop.circle.fill"
        ) {
            MicField(label: "Client name",
                     text: $draft.job.clientName,
                     placeholder: "e.g. Coleman Residence")
            MicField(label: "Property address",
                     text: $draft.job.propertyAddress,
                     placeholder: "1247 Oakridge Ln, Plano TX 75024")
            MicField(label: "Phone",
                     text: $phone,
                     placeholder: "(555) 555-1234",
                     keyboard: .phonePad)
            MicField(label: "Email",
                     text: $email,
                     placeholder: "owner@example.com",
                     keyboard: .emailAddress)
        }
    }
}

// MARK: - Step 2: Insurance

private struct InsuranceStep: View {
    @Binding var draft: Inspection

    var body: some View {
        WizardSection(
            title: "Insurance",
            subtitle: "Carrier and claim numbers for the report.",
            icon: "shield.fill"
        ) {
            StringChipGrid(label: "Carrier",
                           options: kCarriers,
                           selection: $draft.job.carrierName,
                           minimum: 150)
            MicField(label: "Policy #",
                     text: $draft.job.policyNumber,
                     placeholder: "POL-1234567")
            MicField(label: "Claim #",
                     text: $draft.job.claimNumber,
                     placeholder: "CLM-9087421")
        }
    }
}

// MARK: - Step 3: Roof System

private struct RoofStep: View {
    @Binding var draft: Inspection

    var body: some View {
        WizardSection(
            title: "Roof System",
            subtitle: "Pre-storm baseline used for Haag scoring.",
            icon: "house.lodge.fill"
        ) {
            ChipGrid(label: "Primary material",
                     options: RoofPrimaryMaterial.allCases,
                     selection: $draft.roof.primaryMaterial,
                     minimum: 160,
                     title: { $0.displayName })

            BigStepper(label: "Estimated age (years)",
                       value: $draft.roof.estimatedAgeYears,
                       step: 1, range: 0...60,
                       format: { "\($0) yr" })

            BigStepper(label: "Layers",
                       value: $draft.roof.layers,
                       step: 1, range: 1...3,
                       format: { "\($0) \($0 == 1 ? "layer" : "layers")" })

            ChipGrid(label: "Geometry",
                     options: RoofGeometry.allCases,
                     selection: $draft.roof.geometry,
                     minimum: 140,
                     title: { $0.displayName })

            ChipGrid(label: "Overall condition (pre-storm)",
                     options: RoofCondition.allCases,
                     selection: $draft.roof.overallConditionPreStorm,
                     minimum: 140,
                     title: { $0.displayName })
        }
    }
}

// MARK: - Step 4: Review

private struct ReviewStep: View {
    @Binding var draft: Inspection
    let phone: String
    let email: String
    var onJump: (InspectionWizardStep) -> Void

    var body: some View {
        WizardSection(
            title: "Review & create",
            subtitle: "Tap a section to jump back and edit.",
            icon: "checkmark.seal.fill"
        ) {
            reviewRow(
                title: "Customer",
                jump: .customer,
                lines: [
                    draft.job.clientName.isEmpty ? "—" : draft.job.clientName,
                    draft.job.propertyAddress.isEmpty ? "No address" : draft.job.propertyAddress,
                    contactLine
                ].filter { !$0.isEmpty }
            )

            reviewRow(
                title: "Insurance",
                jump: .insurance,
                lines: [
                    draft.job.carrierName.isEmpty ? "No carrier" : draft.job.carrierName,
                    [
                        draft.job.policyNumber.isEmpty ? nil : "Policy \(draft.job.policyNumber)",
                        draft.job.claimNumber.isEmpty  ? nil : "Claim \(draft.job.claimNumber)"
                    ].compactMap { $0 }.joined(separator: " · ")
                ].filter { !$0.isEmpty }
            )

            reviewRow(
                title: "Roof",
                jump: .roof,
                lines: [
                    "\(draft.roof.primaryMaterial.displayName) · \(draft.roof.geometry.displayName)",
                    "\(draft.roof.estimatedAgeYears) yr · \(draft.roof.layers) \(draft.roof.layers == 1 ? "layer" : "layers")",
                    "Pre-storm: \(draft.roof.overallConditionPreStorm.displayName)"
                ]
            )

            reviewRow(
                title: "Report",
                jump: .review,
                lines: [
                    draft.job.reportId,
                    "Inspector: \(draft.job.inspectorName)",
                    draft.job.companyName
                ],
                tappable: false
            )
        }
    }

    private var contactLine: String {
        let parts = [phone, email].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private func reviewRow(title: String,
                           jump: InspectionWizardStep,
                           lines: [String],
                           tappable: Bool = true) -> some View {
        Button {
            if tappable { onJump(jump) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    FieldLabel(text: title)
                    Spacer()
                    if tappable {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ember)
                    }
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
    }
}
