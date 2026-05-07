import SwiftUI
import SwiftData

// MARK: - Draft

@Observable
final class JobDraft {
    // Customer
    var customerName: String = ""
    var phone: String = ""
    var email: String = ""

    // Property
    var addressLine: String = ""
    var city: String = ""
    var state: String = "TX"
    var zip: String = ""
    var latitude: Double = 33.0198
    var longitude: Double = -96.6989

    // Roof
    var roofMaterial: JobRoofMaterial = .asphalt
    var roofPitch: JobRoofPitch = .medium
    var stories: Int = 1
    var sqftEstimate: Int = 2200

    // Insurance
    var carrier: String = ""
    var claimNumber: String = ""
    var adjusterName: String = ""
    var adjusterPhone: String = ""
    var deductibleCents: Int = 100_000

    // Storm
    var stormEventLabel: String = ""

    // Pipeline & rep
    var pipelineStage: JobPipelineStage = .interested
    var assignedRep: String = "Alex Coleman"

    // Notes
    var notes: String = ""
}

// MARK: - Steps

enum NewJobStep: Int, CaseIterable, Identifiable {
    case customer, property, roof, insurance, event, pipeline, notes, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .customer: "Customer"
        case .property: "Property"
        case .roof: "Roof"
        case .insurance: "Insurance"
        case .event: "Storm Event"
        case .pipeline: "Stage & Rep"
        case .notes: "Notes"
        case .review: "Review"
        }
    }
    var icon: String {
        switch self {
        case .customer: "person.crop.circle.fill"
        case .property: "house.fill"
        case .roof: "house.lodge.fill"
        case .insurance: "shield.fill"
        case .event: "cloud.bolt.rain.fill"
        case .pipeline: "list.bullet.clipboard.fill"
        case .notes: "note.text"
        case .review: "checkmark.seal.fill"
        }
    }
}

// MARK: - Root wizard

struct NewJobWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft = JobDraft()
    @State private var step: NewJobStep = .customer
    var onCreated: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            header
            stepIndicator
            ScrollView {
                Group {
                    switch step {
                    case .customer: CustomerStepView(draft: draft)
                    case .property: PropertyStepView(draft: draft)
                    case .roof:     RoofStepView(draft: draft)
                    case .insurance: InsuranceStepView(draft: draft)
                    case .event:    StormEventStepView(draft: draft)
                    case .pipeline: PipelineStepView(draft: draft)
                    case .notes:    NotesStepView(draft: draft)
                    case .review:   ReviewStepView(draft: draft)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            footer
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("New Job")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Step \(step.rawValue + 1) of \(NewJobStep.allCases.count) · \(step.title)")
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
        let total = NewJobStep.allCases.count
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        step = NewJobStep(rawValue: step.rawValue - 1) ?? .customer
                    }
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
                    save()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        step = NewJobStep(rawValue: step.rawValue + 1) ?? .review
                    }
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
                            ? [Theme.ember, Color(red: 0.95, green: 0.45, blue: 0.20)]
                            : [Theme.inkFaint, Theme.inkFaint],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 18)
                )
                .shadow(color: canAdvance ? Theme.ember.opacity(0.35) : .clear,
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
            !draft.customerName.trimmingCharacters(in: .whitespaces).isEmpty
        case .property:
            !draft.addressLine.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            true
        }
    }

    // MARK: save

    private func save() {
        let customer = CustomerRecord(
            name: draft.customerName,
            phone: draft.phone,
            email: draft.email
        )
        let property = PropertyRecord(
            addressLine: draft.addressLine,
            city: draft.city,
            state: draft.state,
            zip: draft.zip,
            latitude: draft.latitude,
            longitude: draft.longitude,
            roofMaterialRaw: draft.roofMaterial.rawValue,
            roofPitchRaw: draft.roofPitch.rawValue,
            stories: draft.stories,
            sqftEstimate: draft.sqftEstimate,
            yearBuilt: 0
        )
        let insurance = InsuranceRecord(
            carrier: draft.carrier,
            claimNumber: draft.claimNumber,
            adjusterName: draft.adjusterName,
            adjusterPhone: draft.adjusterPhone,
            deductibleCents: draft.deductibleCents
        )
        let job = JobRecord(
            pipelineStageRaw: draft.pipelineStage.rawValue,
            damageScore: 0,
            notes: draft.notes,
            assignedRep: draft.assignedRep,
            stormEventLabel: draft.stormEventLabel
        )
        modelContext.insert(customer)
        modelContext.insert(property)
        modelContext.insert(insurance)
        modelContext.insert(job)
        job.customer = customer
        job.property = property
        job.insurance = insurance
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCreated(job.id)
        dismiss()
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

private struct BigField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

private struct ChipPicker<T: Hashable & Identifiable>: View where T.ID == String {
    let label: String
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(options) { opt in
                    let selected = opt == selection
                    Button {
                        selection = opt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(title(opt))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 56)
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
    var range: ClosedRange<Int> = 0...100
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
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 64)
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

// MARK: - Step views

private struct CustomerStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Who's the customer?",
            subtitle: "Owner contact info — name is required.",
            icon: "person.crop.circle.fill"
        ) {
            BigField(label: "Owner name", text: $draft.customerName,
                     placeholder: "e.g. Coleman Residence")
            BigField(label: "Phone", text: $draft.phone,
                     placeholder: "(555) 555-1234", keyboard: .phonePad)
            BigField(label: "Email", text: $draft.email,
                     placeholder: "owner@example.com", keyboard: .emailAddress)
        }
    }
}

private struct PropertyStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Property address",
            subtitle: "Drop a pin or type the street.",
            icon: "house.fill"
        ) {
            BigField(label: "Street address", text: $draft.addressLine,
                     placeholder: "1247 Oakridge Ln")
            HStack(spacing: 10) {
                BigField(label: "City", text: $draft.city, placeholder: "Plano")
                BigField(label: "State", text: $draft.state, placeholder: "TX")
                    .frame(maxWidth: 96)
                BigField(label: "ZIP", text: $draft.zip,
                         placeholder: "75024", keyboard: .numberPad)
                    .frame(maxWidth: 120)
            }
            mapPreview
        }
    }

    private var mapPreview: some View {
        Color(.secondarySystemBackground)
            .frame(height: 180)
            .overlay {
                ZStack {
                    LinearGradient(colors: [
                        Color(red: 0.86, green: 0.92, blue: 0.96),
                        Color(red: 0.74, green: 0.84, blue: 0.92)
                    ], startPoint: .top, endPoint: .bottom)
                    GeometryReader { p in
                        Path { path in
                            for i in stride(from: 0, to: Int(p.size.width), by: 24) {
                                path.move(to: CGPoint(x: CGFloat(i), y: 0))
                                path.addLine(to: CGPoint(x: CGFloat(i), y: p.size.height))
                            }
                            for i in stride(from: 0, to: Int(p.size.height), by: 24) {
                                path.move(to: CGPoint(x: 0, y: CGFloat(i)))
                                path.addLine(to: CGPoint(x: p.size.width, y: CGFloat(i)))
                            }
                        }
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                    }
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct RoofStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Roof details",
            subtitle: "Used to estimate squares and materials.",
            icon: "house.lodge.fill"
        ) {
            ChipPicker(label: "Material", options: JobRoofMaterial.allCases,
                       selection: $draft.roofMaterial, title: { $0.rawValue })
            ChipPicker(label: "Pitch", options: JobRoofPitch.allCases,
                       selection: $draft.roofPitch, title: { $0.rawValue })
            BigStepper(label: "Stories", value: $draft.stories,
                       step: 1, range: 1...4,
                       format: { "\($0) \($0 == 1 ? "story" : "stories")" })
            BigStepper(label: "Square footage (estimate)",
                       value: $draft.sqftEstimate, step: 100, range: 500...10_000,
                       format: { "\($0.formatted(.number)) sq ft" })
        }
    }
}

private struct InsuranceStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Insurance",
            subtitle: "Optional — fill in what you have.",
            icon: "shield.fill"
        ) {
            BigField(label: "Carrier", text: $draft.carrier, placeholder: "State Farm")
            BigField(label: "Claim number", text: $draft.claimNumber,
                     placeholder: "SF-9087421")
            BigField(label: "Adjuster name", text: $draft.adjusterName,
                     placeholder: "Karen Liu")
            BigField(label: "Adjuster phone", text: $draft.adjusterPhone,
                     placeholder: "(800) 555-0119", keyboard: .phonePad)
            BigStepper(label: "Deductible", value: $draft.deductibleCents,
                       step: 50_000, range: 0...500_000,
                       format: { "$\(($0 / 100).formatted(.number))" })
        }
    }
}

private struct StormEventStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Storm event",
            subtitle: "Tag this job to a known storm.",
            icon: "cloud.bolt.rain.fill"
        ) {
            VStack(spacing: 10) {
                eventCard(
                    label: "Not linked",
                    subtitle: "Skip — no storm tag",
                    icon: "minus.circle.fill",
                    isSelected: draft.stormEventLabel.isEmpty
                ) { draft.stormEventLabel = "" }

                ForEach(MockData.storms.prefix(6)) { storm in
                    let label = "\(storm.type.rawValue) · \(storm.date)"
                    let detail: String = {
                        if storm.type == .hail {
                            let size = String(format: "%.2f", storm.sizeInches ?? 0)
                            return "Hail \(size)\" · \(storm.propertiesAffected) properties"
                        } else {
                            return "Wind \(storm.windMPH ?? 0) mph · \(storm.propertiesAffected) properties"
                        }
                    }()
                    eventCard(
                        label: label,
                        subtitle: detail,
                        icon: storm.type.icon,
                        isSelected: draft.stormEventLabel == label
                    ) { draft.stormEventLabel = label }
                }
            }
        }
    }

    private func eventCard(label: String, subtitle: String, icon: String,
                           isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isSelected ? Theme.ember : Theme.canvas)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Theme.inkSoft)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .padding(.vertical, 8)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Theme.ember : Theme.hairline,
                        lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PipelineStepView: View {
    @Bindable var draft: JobDraft
    static let reps = ["Alex Coleman", "Sarah Jenkins", "Mike Johnson", "Crew B", "Unassigned"]

    var body: some View {
        WizardSection(
            title: "Stage & assignment",
            subtitle: "Where does this job start?",
            icon: "list.bullet.clipboard.fill"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Pipeline stage")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                          spacing: 10) {
                    ForEach(JobPipelineStage.allCases) { stage in
                        let selected = stage == draft.pipelineStage
                        Button {
                            draft.pipelineStage = stage
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: stage.icon)
                                    .font(.system(size: 16, weight: .bold))
                                Text(stage.shortLabel)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.horizontal, 10)
                            .background(selected ? stage.color : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Assigned rep")
                VStack(spacing: 8) {
                    ForEach(Self.reps, id: \.self) { rep in
                        let selected = rep == draft.assignedRep
                        Button {
                            draft.assignedRep = rep
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(selected ? Theme.ember : Theme.canvas)
                                    Text(rep.split(separator: " ")
                                            .compactMap(\.first).map(String.init).joined())
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(selected ? .white : Theme.ink)
                                }
                                .frame(width: 40, height: 40)
                                Text(rep)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(Theme.ember)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 64)
                            .background(Theme.card, in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? Theme.ember : Theme.hairline,
                                        lineWidth: selected ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct NotesStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Notes",
            subtitle: "Anything the crew should know?",
            icon: "note.text"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Notes")
                TextEditor(text: $draft.notes)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 200)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.hairline, lineWidth: 1))
            }

            Button {
                // Voice-note hook (placeholder for future audio capture)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Add voice note")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Theme.ember)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.emberSoft, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ReviewStepView: View {
    @Bindable var draft: JobDraft
    var body: some View {
        WizardSection(
            title: "Review & create",
            subtitle: "Quick check before saving.",
            icon: "checkmark.seal.fill"
        ) {
            reviewRow("Customer",
                      "\(draft.customerName.isEmpty ? "—" : draft.customerName)\n\(contactLine)")
            reviewRow("Property", propertyLine)
            reviewRow("Roof",
                      "\(draft.roofMaterial.rawValue) · \(draft.roofPitch.rawValue)\n\(draft.stories) \(draft.stories == 1 ? "story" : "stories") · \(draft.sqftEstimate.formatted(.number)) sq ft")
            reviewRow("Insurance", insuranceLine)
            reviewRow("Storm event",
                      draft.stormEventLabel.isEmpty ? "Not linked" : draft.stormEventLabel)
            reviewRow("Pipeline",
                      "\(draft.pipelineStage.rawValue) · \(draft.assignedRep)")
            if !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reviewRow("Notes", draft.notes)
            }
        }
    }

    private var contactLine: String {
        let parts = [draft.phone, draft.email].filter { !$0.isEmpty }
        return parts.isEmpty ? "No contact info" : parts.joined(separator: " · ")
    }

    private var propertyLine: String {
        let csz = "\(draft.city) \(draft.state) \(draft.zip)"
            .trimmingCharacters(in: .whitespaces)
        return draft.addressLine.isEmpty ? "—" : "\(draft.addressLine)\n\(csz)"
    }

    private var insuranceLine: String {
        if draft.carrier.isEmpty { return "Not provided" }
        let claim = draft.claimNumber.isEmpty ? "no claim #" : "Claim \(draft.claimNumber)"
        let ded = "Deductible $\((draft.deductibleCents / 100).formatted(.number))"
        return "\(draft.carrier) · \(claim)\n\(ded)"
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.hairline, lineWidth: 1))
    }
}
