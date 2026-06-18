import SwiftUI

// MARK: - Steps

enum InspectionWizardStep: Int, CaseIterable, Identifiable {
    case customer, insurance, roof, stormPolicy, roofCondition, brittleness, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .customer:      return "Customer & Property"
        case .insurance:     return "Insurance"
        case .roof:          return "Roof System"
        case .stormPolicy:   return "Storm & Policy"
        case .roofCondition: return "Roof Condition"
        case .brittleness:   return "Brittleness Test"
        case .review:        return "Review"
        }
    }
}

// MARK: - Root wizard

struct NewJobWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CustomerStore.self) private var customerStore
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

    init(onCreated: @escaping (String) -> Void = { _ in }) {
        self.onCreated = onCreated
    }

    /// Prefilled initializer used by the Cost Estimator's "Convert to New Job"
    /// CTA. Drops the user straight into Step 1 with the captured address +
    /// detected squares + chosen material already populated.
    init(prefillAddress: String?,
         prefillMaterial: RoofPrimaryMaterial?,
         prefillDetectedSquares: Double?,
         originEstimateId: UUID? = nil,
         onCreated: @escaping (String) -> Void = { _ in }) {
        self.onCreated = onCreated
        var d = InspectionStore.shared.makeDraft()
        if let a = prefillAddress, !a.isEmpty { d.job.propertyAddress = a }
        if let m = prefillMaterial { d.roof.primaryMaterial = m }
        if let sq = prefillDetectedSquares, sq > 0 { d.roof.detectedAreaSquares = sq }
        d.originEstimateId = originEstimateId
        _draft = State(initialValue: d)
    }

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
                        case .stormPolicy:
                            StormPolicyStep(draft: $draft)
                        case .roofCondition:
                            RoofConditionStep(draft: $draft)
                        case .brittleness:
                            BrittlenessStep(draft: $draft)
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
        .confirmationDialog("Discard this lead?",
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
                Text("New Lead")
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
                    Text(step == .review ? "Create Lead" : "Next")
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
        // Mirror the inspection into a Customer so the job is visible and
        // reachable from the Leads list and the customer profile.
        let customerID = customerStore.upsertFromInspection(saved, phone: phone, email: email)
        // Kick off the background roof measurement + repair estimate so the
        // numbers are ready by the time the inspector opens the profile.
        RoofEstimateService.computeInBackground(
            customerID: customerID,
            address: saved.job.propertyAddress,
            material: saved.roof.primaryMaterial,
            store: customerStore
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCreated(saved.job.reportId)
        createdReportId = saved.job.reportId
        // Activity log — job_created (and address_geocoded if we have one).
        ActivityStore.shared.log(
            .jobCreated,
            summary: "Job created",
            detail: saved.job.clientName.isEmpty ? saved.job.reportId
                : "\(saved.job.clientName) \u{00B7} \(saved.job.reportId)",
            on: saved
        )
        if !saved.job.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            ActivityStore.shared.log(
                .addressGeocoded,
                summary: "Address captured",
                detail: saved.job.propertyAddress,
                on: saved
            )
        }
        if saved.roof.detectedAreaSquares != nil {
            ActivityStore.shared.log(
                .roofDetected,
                summary: "Roof measured from satellite",
                detail: String(format: "%.1f sq detected",
                               saved.roof.detectedAreaSquares ?? 0),
                on: saved
            )
        }
        if saved.originEstimateId != nil {
            ActivityStore.shared.log(
                .estimateConverted,
                summary: "Converted from saved estimate",
                detail: nil,
                on: saved
            )
        }
        // Fire-and-forget: geocode the address and try to auto-fill the
        // event{} fields from NOAA storm history.
        Task.detached {
            await InspectionStore.shared.autoPopulateEvent(for: saved.job.reportId)
        }
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
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 34, height: 34)
                    .background(Theme.emberSoft, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .medium))
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
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    // Voice-input stub: hooked up when real dictation lands.
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 48, height: 50)
                        .background(Theme.emberSoft, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, lineWidth: 0.6))
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
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 12)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 0.6))
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
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 12)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 0.6))
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(value <= range.lowerBound ? Theme.inkFaint : Theme.ink)
                        .frame(width: 54, height: 54)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text(format(value))
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.horizontal, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.hairline, lineWidth: 0.6))

                Button {
                    value = min(range.upperBound, value + step)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
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

    @State private var addressSnapshot: WeatherSnapshot? = nil
    @State private var lookupTask: Task<Void, Never>? = nil
    @State private var roofMeasurements: RoofMeasurements? = nil
    @State private var solarTask: Task<Void, Never>? = nil

    private let service: WeatherServicing = WeatherServiceFactory.shared
    private let solar: SolarServicing = SolarServiceFactory.shared

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
            if addressSnapshot != nil || roofMeasurements != nil {
                HStack(spacing: 8) {
                    if let snap = addressSnapshot {
                        HStack(spacing: 6) {
                            Image(systemName: weatherSymbol(for: snap.condition))
                                .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                                .foregroundStyle(Theme.sky)
                            Text("Now: \(snap.temperatureF)° \(snap.condition)")
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.skySoft, in: .capsule)
                    }
                    if let m = roofMeasurements {
                        HStack(spacing: 6) {
                            Image(systemName: "square.3.layers.3d.top.filled")
                                .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                                .foregroundStyle(Theme.amber)
                            Text(String(format: "Roof: ~%.0f sq \u{00B7} %d faces",
                                        m.totalAreaSquares, m.segments.count))
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.amberSoft, in: .capsule)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            MicField(label: "Phone",
                     text: $phone,
                     placeholder: "(555) 555-1234",
                     keyboard: .phonePad)
            MicField(label: "Email",
                     text: $email,
                     placeholder: "owner@example.com",
                     keyboard: .emailAddress)
        }
        .onChange(of: draft.job.propertyAddress) { _, newValue in
            scheduleLookup(for: newValue)
        }
        .onAppear { scheduleLookup(for: draft.job.propertyAddress) }
    }

    private func scheduleLookup(for address: String) {
        lookupTask?.cancel()
        solarTask?.cancel()
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else {
            withAnimation(.easeInOut(duration: 0.2)) {
                addressSnapshot = nil
                roofMeasurements = nil
            }
            return
        }
        let coord = WeatherServiceFactory.mockCoord(forAddress: trimmed)
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            let snap = try? await service.currentConditions(at: coord)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.addressSnapshot = snap
                }
            }
        }
        solarTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            let m = try? await solar.measurements(at: coord)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.roofMeasurements = m
                }
            }
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
            CarrierPickerField(label: "Carrier", carrier: $draft.job.carrierName)
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

    @State private var measurements: RoofMeasurements? = nil
    @State private var detectionFailed: Bool = false
    @State private var didDismissCard: Bool = false
    @State private var loadTask: Task<Void, Never>? = nil

    private let solar: SolarServicing = SolarServiceFactory.shared

    var body: some View {
        WizardSection(
            title: "Roof System",
            subtitle: "Pre-storm baseline used for Haag scoring.",
            icon: "house.lodge.fill"
        ) {
            detectedRoofCard

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
        .onAppear { fetchMeasurements() }
    }

    @ViewBuilder
    private var detectedRoofCard: some View {
        if didDismissCard && draft.roof.detectedAreaSquares == nil {
            EmptyView()
        } else if let m = measurements {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.amberSoft)
                        Image(systemName: "square.3.layers.3d.top.filled")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.amber)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DETECTED ROOF")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                        Text(String(format: "Total: %.1f squares", m.totalAreaSquares))
                            .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Text(SolarServiceFactory.shared.isLive ? "GOOGLE SOLAR" : "ESTIMATE")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(SolarServiceFactory.shared.isLive ? Theme.mint : Theme.inkFaint,
                                    in: .capsule)
                }
                Text("\(m.segments.count) slopes · \(avgPitchLabel(m)) avg pitch")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)

                if draft.roof.detectedAreaSquares == nil {
                    HStack(spacing: 10) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            applyDetection(m)
                        } label: {
                            Text("Use detection")
                                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) { didDismissCard = true }
                        } label: {
                            Text("Enter manually")
                                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(Theme.card, in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            Text("USING DETECTION")
                                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                                .tracking(0.8)
                        }
                        .foregroundStyle(Theme.mint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.mintSoft, in: .capsule)
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draft.roof.detectedAreaSquares = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.emberSoft, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)
            .transition(.opacity)
        } else if detectionFailed {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
                Text("Detection unavailable — enter manually")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14, radius: 16)
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.amber)
                Text("Measuring roof from satellite imagery…")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14, radius: 16)
        }
    }

    private func avgPitchLabel(_ m: RoofMeasurements) -> String {
        guard !m.segments.isEmpty else { return "—" }
        let avgDeg = m.segments.map(\.pitchDegrees).reduce(0, +) / Double(m.segments.count)
        let rise = max(0, Int((tan(avgDeg * .pi / 180.0) * 12.0).rounded()))
        return "\(rise):12"
    }

    private func fetchMeasurements() {
        guard measurements == nil, !detectionFailed else { return }
        let address = draft.job.propertyAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else {
            detectionFailed = true
            return
        }
        let coord = GeocodingServiceFactory.eagerCoord(forAddress: address)
        loadTask?.cancel()
        loadTask = Task {
            let m = try? await solar.measurements(at: coord)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if let m { self.measurements = m }
                    else { self.detectionFailed = true }
                }
            }
        }
    }

    private func applyDetection(_ m: RoofMeasurements) {
        // Stamp the roof-level total — this is what the Haag report will
        // show as the "detected" baseline. Per-slope detected areas are
        // applied later when slopes are added (see SlopeCaptureView).
        draft.roof.detectedAreaSquares = m.totalAreaSquares
        // Heuristic: 3+ segments = hip; otherwise gable, unless inspector
        // already chose something explicit (we don't override material).
        if m.segments.count >= 3 {
            draft.roof.geometry = .hip
        }
    }
}

// MARK: - Tri-state chip grid (maps to an optional value)

/// Chip grid where one option (typically "Not sure"/"Skipped") maps to `nil`.
/// Selection is derived purely from the binding so it survives step re-entry.
private struct TriChipGrid<Value: Hashable>: View {
    let label: String
    let options: [(title: String, value: Value?)]
    @Binding var selection: Value?
    var minimum: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    let selected = opt.value == selection
                    Button {
                        selection = opt.value
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(opt.title)
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 12)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Step 4: Storm & Policy

private struct StormPolicyStep: View {
    @Binding var draft: Inspection

    var body: some View {
        WizardSection(
            title: "Storm & Policy",
            subtitle: "Loss date and policy basis for the claim.",
            icon: "calendar.badge.exclamationmark"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Day of loss")
                DatePicker(
                    "Day of loss",
                    selection: Binding(
                        get: { draft.dayOfLoss ?? Date() },
                        set: { draft.dayOfLoss = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Theme.ember)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                if draft.dayOfLoss != nil {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        draft.dayOfLoss = nil
                    } label: {
                        Text("Clear date")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                    }
                    .buttonStyle(.plain)
                }
            }

            TriChipGrid(
                label: "Policy type",
                options: [("ACV", .acv), ("RCV", .rcv), ("Not sure", nil)],
                selection: $draft.policyType,
                minimum: 100
            )

            DeductibleField(amount: $draft.deductibleAmount)
        }
    }
}

private struct DeductibleField: View {
    @Binding var amount: Decimal?
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Deductible (optional)")
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.leading, 16)
                TextField("2,500", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .onChange(of: text) { _, newValue in
                        let cleaned = newValue.filter { $0.isNumber || $0 == "." }
                        amount = cleaned.isEmpty ? nil : Decimal(string: cleaned)
                    }
            }
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
        .onAppear {
            if let a = amount, text.isEmpty {
                text = NSDecimalNumber(decimal: a).stringValue
            }
        }
    }
}

// MARK: - Step 5: Roof Condition

private struct RoofConditionStep: View {
    @Binding var draft: Inspection

    var body: some View {
        WizardSection(
            title: "Roof Condition",
            subtitle: "Layers and material availability drive repairability.",
            icon: "square.3.layers.3d"
        ) {
            TriChipGrid(
                label: "Number of layers",
                options: [("1", 1), ("2", 2), ("3", 3), ("4+", 4), ("Not sure", nil)],
                selection: $draft.roofLayers,
                minimum: 90
            )

            TriChipGrid(
                label: "Material discontinued?",
                options: [("No", false), ("Yes", true), ("Not sure", nil)],
                selection: $draft.materialDiscontinued,
                minimum: 100
            )

            if draft.materialDiscontinued == true {
                MicField(
                    label: "Reason / manufacturer notes",
                    text: Binding(
                        get: { draft.materialDiscontinuedReason ?? "" },
                        set: { draft.materialDiscontinuedReason = $0.isEmpty ? nil : $0 }
                    ),
                    placeholder: "e.g. CertainTeed Independence line retired 2019"
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: draft.materialDiscontinued)
    }
}

// MARK: - Step 6: Brittleness Test

private struct BrittlenessStep: View {
    @Binding var draft: Inspection

    var body: some View {
        WizardSection(
            title: "Brittleness Test",
            subtitle: "Field test that proves shingles can't be repaired.",
            icon: "hand.raised.fingers.spread.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.amberSoft)
                        Image(systemName: "arrow.uturn.up")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(Theme.amber)
                    }
                    .frame(width: 56, height: 56)
                    Text("Bend a shingle tab 90°. Cracks on the first bend = FAIL. Holds up without cracking = PASS.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 16)

            TriChipGrid(
                label: "Result",
                options: [("Pass", .pass), ("Fail", .fail), ("Borderline", .borderline), ("Skipped", nil)],
                selection: $draft.brittlenessResult,
                minimum: 110
            )
        }
    }
}

// MARK: - Step 7: Review

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
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .cardStyle(padding: 16, radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
    }
}
