import SwiftUI
import CoreLocation

// MARK: - Steps

private enum CostStep: Int, CaseIterable, Identifiable {
    case address, measure, material, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .address:  return "Property"
        case .measure:  return "Roof Size"
        case .material: return "Material"
        case .review:   return "Estimate"
        }
    }
}

// MARK: - Wizard root

struct CostEstimatorWizard: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step: CostStep = .address
    @State private var showCancel = false
    @State private var showConvertJob = false
    @State private var savedToast = false
    @State private var estimatesStore = EstimatesStore.shared

    /// When set, the wizard opens straight at the Review step using this
    /// snapshot — used by the Saved Estimates strip on Home.
    private let prefilledSaved: SavedEstimate?

    init(prefilledSaved: SavedEstimate? = nil) {
        self.prefilledSaved = prefilledSaved
        if let s = prefilledSaved {
            _step = State(initialValue: .review)
            _picked = State(initialValue: AddressSuggestion(
                title: s.address,
                subtitle: s.region,
                latitude: 0, longitude: 0
            ))
            _squaresOverride = State(initialValue: s.totalSquares)
            _material = State(initialValue: s.material)
            _quality = State(initialValue: s.quality)
            _complexity = State(initialValue: s.complexity)
            _tearOffLayers = State(initialValue: s.tearOffLayers)
            _includePermit = State(initialValue: s.includePermit)
            _includeDisposal = State(initialValue: s.includeDisposal)
        }
    }

    // Step 1
    @State private var picked: AddressSuggestion? = nil
    @State private var showAddressPicker = false

    // Step 2
    @State private var measurements: RoofMeasurements? = nil
    @State private var measureFailed = false
    @State private var measureTask: Task<Void, Never>? = nil
    @State private var squaresOverride: Double? = nil

    // Step 3
    @State private var material: EstimateMaterial = .asphaltArch
    @State private var quality:  EstimateQuality  = .better
    @State private var complexity: EstimateComplexity = .average
    @State private var tearOffLayers: Int = 1
    @State private var includePermit: Bool = true
    @State private var includeDisposal: Bool = true

    private let mapsService: MapsService = MapsServiceFactory.make()
    private let solar: SolarServicing = SolarServiceFactory.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                stepIndicator
                ScrollView {
                    Group {
                        switch step {
                        case .address:
                            AddressStep(picked: $picked,
                                        showPicker: $showAddressPicker)
                        case .measure:
                            MeasureStep(picked: picked,
                                        measurements: $measurements,
                                        measureFailed: $measureFailed,
                                        squaresOverride: $squaresOverride,
                                        startMeasure: scheduleMeasure)
                        case .material:
                            MaterialStep(material: $material,
                                         quality: $quality,
                                         complexity: $complexity,
                                         tearOffLayers: $tearOffLayers,
                                         includePermit: $includePermit,
                                         includeDisposal: $includeDisposal)
                        case .review:
                            ReviewStep(estimate: currentEstimate(),
                                       onJump: { jump(to: $0) })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                footer
            }
            .background(Theme.canvas.ignoresSafeArea())
            .sheet(isPresented: $showAddressPicker) {
                AddressPickerSheet(service: mapsService) { sug in
                    picked = sug
                    measurements = nil
                    measureFailed = false
                    squaresOverride = nil
                }
            }
        }
        .confirmationDialog("Discard this estimate?",
                            isPresented: $showCancel,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Anything you've entered will be lost.")
        }
        .fullScreenCover(isPresented: $showConvertJob) {
            NewJobWizard(
                prefillAddress: picked?.title,
                prefillMaterial: material.roofMaterial,
                prefillDetectedSquares: effectiveSquares > 0 ? effectiveSquares : nil
            )
        }
        .overlay(alignment: .top) {
            if savedToast {
                Text("Estimate saved")
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.mint, in: .capsule)
                    .shadow(color: Theme.mint.opacity(0.35), radius: 12, y: 6)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: header / footer

    private var header: some View {
        HStack {
            Button {
                showCancel = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            Spacer()
            VStack(spacing: 2) {
                Text("Cost Estimator")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Step \(step.rawValue + 1) of \(CostStep.allCases.count) · \(step.title)")
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
        let total = CostStep.allCases.count
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

    @ViewBuilder
    private var footer: some View {
        if step == .review {
            reviewFooter
        } else {
            stepFooter
        }
    }

    private var stepFooter: some View {
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
                advance(by: 1)
            } label: {
                HStack(spacing: 8) {
                    Text("Next")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
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

    private var reviewFooter: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showConvertJob = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.folder.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Convert to New Job")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(picked == nil)

            Button {
                saveCurrentEstimate()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Save estimate")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(picked == nil || effectiveSquares <= 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .background(Theme.canvas)
    }

    private func saveCurrentEstimate() {
        guard let picked, effectiveSquares > 0 else { return }
        let est = currentEstimate()
        let saved = SavedEstimate(from: est, address: picked.title)
        estimatesStore.save(saved)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            savedToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.25)) { savedToast = false }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .address:  return picked != nil
        case .measure:  return effectiveSquares > 0
        case .material: return true
        case .review:   return true
        }
    }

    private func advance(by delta: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = step.rawValue + delta
        guard let s = CostStep(rawValue: next) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = s
        }
        if s == .measure { scheduleMeasure() }
    }

    private func jump(to s: CostStep) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = s }
    }

    private func scheduleMeasure() {
        guard let picked, measurements == nil else { return }
        measureFailed = false
        measureTask?.cancel()
        let coord = picked.coordinate
        measureTask = Task {
            let m = try? await solar.measurements(at: coord)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if let m { self.measurements = m }
                    else { self.measureFailed = true }
                }
            }
        }
    }

    // MARK: derived inputs

    private var effectiveSquares: Double {
        if let s = squaresOverride { return s }
        return measurements?.totalAreaSquares ?? 0
    }

    private var avgPitchRiseOver12: Int {
        guard let segs = measurements?.segments, !segs.isEmpty else { return 6 }
        let avgDeg = segs.map(\.pitchDegrees).reduce(0, +) / Double(segs.count)
        return max(0, Int((tan(avgDeg * .pi / 180.0) * 12.0).rounded()))
    }

    private func currentEstimate() -> CostEstimate {
        let input = CostEstimateInput(
            address: picked?.fullAddress ?? "",
            totalSquares: effectiveSquares,
            detectedSegmentCount: measurements?.segments.count ?? 0,
            avgPitchRiseOver12: avgPitchRiseOver12,
            material: material,
            quality: quality,
            complexity: complexity,
            tearOffLayers: tearOffLayers,
            includePermit: includePermit,
            includeDisposal: includeDisposal
        )
        return CostEstimator.estimate(input)
    }
}

// MARK: - Step 1: Address

private struct AddressStep: View {
    @Binding var picked: AddressSuggestion?
    @Binding var showPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CostSectionHeader(
                title: "Where's the roof?",
                subtitle: "Search any U.S. address. We'll measure it from satellite.",
                icon: "mappin.and.ellipse",
                tint: Theme.sky
            )

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showPicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.skySoft)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.sky)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        if let p = picked {
                            Text(p.title)
                                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(p.subtitle)
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        } else {
                            Text("Pick an address")
                                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text("Street, city, ZIP…")
                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .cardStyle(padding: 14, radius: 18)
            }
            .buttonStyle(.plain)

            if picked != nil {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.mint)
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    Text("Address locked. Tap Next to measure the roof.")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: picked)
    }
}

// MARK: - Step 2: Measure

private struct MeasureStep: View {
    let picked: AddressSuggestion?
    @Binding var measurements: RoofMeasurements?
    @Binding var measureFailed: Bool
    @Binding var squaresOverride: Double?
    var startMeasure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CostSectionHeader(
                title: "Roof size",
                subtitle: "Detected from satellite imagery — adjust if you've measured manually.",
                icon: "square.3.layers.3d.top.filled",
                tint: Theme.amber
            )

            if let m = measurements {
                detectedCard(m)
                manualOverrideCard(detected: m.totalAreaSquares)
            } else if measureFailed {
                failureCard
                manualOverrideCard(detected: 0)
            } else {
                loadingCard
            }
        }
        .onAppear { if measurements == nil && !measureFailed { startMeasure() } }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Measuring roof…")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(picked?.fullAddress ?? "")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private var failureCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Detection unavailable")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Enter the roof size manually below.")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func detectedCard(_ m: RoofMeasurements) -> some View {
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
                    Text("DETECTED")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.inkSoft)
                    Text(String(format: "%.1f squares", m.totalAreaSquares))
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Text(m.source.uppercased())
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func manualOverrideCard(detected: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MANUAL OVERRIDE")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                if squaresOverride != nil {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation { squaresOverride = nil }
                    } label: {
                        Text("Reset")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.emberSoft, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }

            let value = squaresOverride ?? detected
            HStack(spacing: 12) {
                Button {
                    let v = max(1.0, value - 1.0)
                    squaresOverride = v
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: Theme.TypeRamp.title, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 64)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Text(String(format: "%.1f sq", value))
                    .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.hairline, lineWidth: 1))

                Button {
                    let v = value + 1.0
                    squaresOverride = v
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.TypeRamp.title, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Theme.ember, in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 16, radius: 18)
    }

    private func avgPitchLabel(_ m: RoofMeasurements) -> String {
        guard !m.segments.isEmpty else { return "—" }
        let avgDeg = m.segments.map(\.pitchDegrees).reduce(0, +) / Double(m.segments.count)
        let rise = max(0, Int((tan(avgDeg * .pi / 180.0) * 12.0).rounded()))
        return "\(rise):12"
    }
}

// MARK: - Step 3: Material

private struct MaterialStep: View {
    @Binding var material: EstimateMaterial
    @Binding var quality:  EstimateQuality
    @Binding var complexity: EstimateComplexity
    @Binding var tearOffLayers: Int
    @Binding var includePermit: Bool
    @Binding var includeDisposal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CostSectionHeader(
                title: "Material & job scope",
                subtitle: "Pick the system and how complex the roof is.",
                icon: "hammer.fill",
                tint: Theme.ember
            )

            CostFieldLabel(text: "Material")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(EstimateMaterial.allCases) { mat in
                    chip(for: mat)
                }
            }

            CostFieldLabel(text: "Quality tier")
            VStack(spacing: 10) {
                ForEach(EstimateQuality.allCases) { q in
                    qualityRow(q)
                }
            }

            CostFieldLabel(text: "Roof complexity")
            VStack(spacing: 10) {
                ForEach(EstimateComplexity.allCases) { c in
                    complexityRow(c)
                }
            }

            CostFieldLabel(text: "Tear-off layers")
            HStack(spacing: 10) {
                ForEach(1...3, id: \.self) { n in
                    let selected = tearOffLayers == n
                    Button {
                        tearOffLayers = n
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("\(n) layer\(n == 1 ? "" : "s")")
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                            .foregroundStyle(selected ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(selected ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            CostFieldLabel(text: "Add-ons")
            VStack(spacing: 10) {
                toggleRow(title: "City permit",
                          subtitle: "$285 flat — required in most jurisdictions",
                          isOn: $includePermit)
                toggleRow(title: "Dumpster & disposal",
                          subtitle: "Hauling + landfill fees",
                          isOn: $includeDisposal)
            }
        }
    }

    private func chip(for mat: EstimateMaterial) -> some View {
        let selected = material == mat
        return Button {
            material = mat
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mat.symbol)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                Text(mat.displayName)
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 12)
            .background(selected ? Theme.ember : Theme.card,
                        in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func qualityRow(_ q: EstimateQuality) -> some View {
        let selected = quality == q
        return Button {
            quality = q
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selected ? Theme.ember : Theme.card)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .black))
                            .foregroundStyle(.white)
                            .opacity(selected ? 1 : 0)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(q.displayName)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(q.subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text(String(format: "×%.2f", q.multiplier))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 14)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Theme.ember : Theme.hairline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func complexityRow(_ c: EstimateComplexity) -> some View {
        let selected = complexity == c
        return Button {
            complexity = c
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selected ? Theme.ember : Theme.card)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .black))
                            .foregroundStyle(.white)
                            .opacity(selected ? 1 : 0)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(c.subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text(String(format: "×%.2f", c.multiplier))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 14)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Theme.ember : Theme.hairline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.ember)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Step 4: Review

private struct ReviewStep: View {
    let estimate: CostEstimate
    var onJump: (CostStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CostSectionHeader(
                title: "Estimate",
                subtitle: "Tap a section to adjust.",
                icon: "dollarsign.circle.fill",
                tint: Theme.mint
            )

            heroCard
            lineItemsCard
            jumpRow(label: "Property",
                    value: estimate.input.address.isEmpty ? "—" : estimate.input.address,
                    step: .address)
            jumpRow(label: "Roof size",
                    value: String(format: "%.1f squares · ~%d:12 pitch",
                                  estimate.input.totalSquares,
                                  estimate.input.avgPitchRiseOver12),
                    step: .measure)
            jumpRow(label: "Material",
                    value: "\(estimate.input.material.displayName) · \(estimate.input.quality.displayName.lowercased())",
                    step: .material)
            disclaimer
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ESTIMATED INSTALLED COST")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
            Text(currency(estimate.subtotal))
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Range: \(estimate.rangeLabel)")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.mint)
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                Text(String(format: "%@ / sq · %.1f squares",
                            currency(estimate.pricePerSquare),
                            estimate.input.totalSquares))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [Theme.mintSoft, Theme.card],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(Theme.mint.opacity(0.35), lineWidth: 1))
        .shadow(color: Theme.mint.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var lineItemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(estimate.lineItems.enumerated()), id: \.element.id) { idx, item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(item.detail)
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Text(currency(item.amount))
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
                if idx < estimate.lineItems.count - 1 {
                    Rectangle().fill(Theme.hairline).frame(height: 0.6)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.6)
            HStack {
                Text("Subtotal")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(currency(estimate.subtotal))
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func jumpRow(label: String, value: String, step: CostStep) -> some View {
        Button { onJump(step) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.inkSoft)
                    Text(value)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .cardStyle(padding: 14, radius: 16)
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Range reflects ±10% local labor variance. Final price depends on site access, decking condition, and code upgrades.")
            .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

// MARK: - Shared chrome

private struct CostSectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CostFieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
            .foregroundStyle(Theme.inkSoft)
            .tracking(0.6)
    }
}
