import SwiftUI
import PhotosUI
import UIKit

// MARK: - SlopeCaptureView
//
// Single vertical-scroll slope capture screen. Pushed onto the
// JobDetail navigation stack from "Add slope". Saves the slope into
// InspectionStore (which re-runs DecisionEngine.decide) and pops back.

struct SlopeCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared

    let reportId: String
    /// Pass an existing orientation to edit that slope in place.
    var existingOrientation: String? = nil

    // MARK: Form state

    @State private var orientation: String = "North"

    // Hail
    @State private var hailBruise: Int = 0
    @State private var hailFracture: Int = 0
    @State private var hailGranule: Int = 0

    // Wind
    @State private var windCrease: Int = 0
    @State private var windMissing: Int = 0
    @State private var windLifted: Int = 0

    // Wear
    @State private var wearNatural: Bool = false
    @State private var wearFoot: Bool = false
    @State private var wearMfg: Bool = false

    // Cost inputs
    @State private var damagedUnitsPerSquare: Int = 0
    @State private var unitRepairCost: Double = 9.00
    @State private var difficultyFactor: Double = 1.0
    @State private var areaSquares: Int = 10
    @State private var replacementCostSlope: Double = 0

    // Functional toggle (mutually exclusive)
    enum FunctionalChoice { case none, functional, cosmetic }
    @State private var functionalChoice: FunctionalChoice = .none

    // Photos
    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false
    @State private var showCamera: Bool = false
    // Launches the existing polished capture flow (QuickInspectionView).
    // We don't read photos back from it (QuickInspection owns its own @State
    // capturedPhotos and dismisses); the inline Capture / Library buttons below
    // remain the source of truth for photos attached to this slope.
    @State private var showFullCapture: Bool = false
    @State private var fullCaptureCustomerStore = CustomerStore()

    // Misc
    @State private var showDiscardConfirm: Bool = false
    @State private var pitchRiseOver12: Int = 6
    @State private var testSquareCount: Int = 1

    // MARK: Phase 8 (flag-gated) AI confidence chips
    /// Sheet binding for the small “AI confidence” info popover. Only used
    /// when `APIKeys.useStructuredConfidence == true`.
    @State private var showConfidenceInfo: Bool = false

    private let orientationOptions = ["North", "South", "East", "West", "Other"]
    private let difficultyOptions: [(label: String, value: Double)] = [
        ("Easy", 1.0), ("Medium", 1.25), ("Hard", 1.5), ("Severe", 2.0)
    ]

    private var liveRepairCost: Double {
        Double(damagedUnitsPerSquare) * unitRepairCost * difficultyFactor * Double(areaSquares)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoCard
                    orientationCard
                    hailCard
                    windCard
                    wearCard
                    costCard
                    functionalCard
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            stickyBar
        }
        .navigationTitle(existingOrientation == nil ? "Add Slope" : "Edit Slope")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDiscardConfirm = true
                } label: {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .onAppear(perform: prefillIfEditing)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .sheet(isPresented: $showCamera) {
            SlopePhotoCameraPicker { image in
                if let image {
                    photos.append(image)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showConfidenceInfo) {
            confidenceInfoSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showFullCapture) {
            // Reuse the existing polished capture flow as-is. It manages its
            // own state and dismisses itself; we don't bind back into our
            // local photos array (QuickInspectionView doesn't surface them).
            // Phase 9.1.1 — thread reportId + orientation so the analyze loop
            // can write back aiFindings onto this slope.
            QuickInspectionView(analyzeContext: (reportId, orientation))
                .environment(fullCaptureCustomerStore)
        }
        .confirmationDialog("Discard slope?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Anything you've entered on this slope will be lost.")
        }
    }

    // MARK: Prefill

    private func prefillIfEditing() {
        guard let orient = existingOrientation,
              let insp = store.inspection(with: reportId),
              let s = insp.slopes.first(where: { $0.orientation == orient }) else { return }
        orientation = orientationOptions.contains(s.orientation) ? s.orientation : "Other"
        pitchRiseOver12 = s.pitchRiseOver12
        testSquareCount = max(1, s.testSquareCount)
        damagedUnitsPerSquare = s.damagedUnitsPerSquare
        unitRepairCost = s.unitRepairCost > 0 ? s.unitRepairCost : 9.00
        difficultyFactor = s.repairDifficultyFactor > 0 ? s.repairDifficultyFactor : 1.0
        areaSquares = max(1, Int(s.areaSquares.rounded()))
        replacementCostSlope = s.replacementCostSlope
        hailBruise = s.damageTypes.hail.asphaltBruise
        hailFracture = s.damageTypes.hail.asphaltMatFracture
        hailGranule = s.damageTypes.hail.asphaltGranuleLossExposed
        windCrease = s.damageTypes.wind.shingleCrease
        windMissing = s.damageTypes.wind.shingleMissing
        windLifted = s.damageTypes.wind.shingleLiftedUnsealed
        wearNatural = s.damageTypes.wear.naturalWeathering
        wearFoot = s.damageTypes.wear.footTraffic
        wearMfg = s.damageTypes.wear.manufacturingDefect
        if s.functionalDamagePresent { functionalChoice = .functional }
        else if s.cosmeticOnly { functionalChoice = .cosmetic }
        else { functionalChoice = .none }
        photos = store.photos(for: reportId, orientation: s.orientation)
    }

    // MARK: Photo card (thin)
    //
    // Intentionally compact so it doesn't compete with the polished
    // QuickInspectionView capture flow. Primary CTA launches that flow
    // full-screen; inline Capture / Library remain as quick fallbacks.

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                Text("Photos")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
                if !photos.isEmpty {
                    Text("\(photos.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.canvas, in: .capsule)
                }
            }

            // Primary: launch the existing polished capture flow.
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showFullCapture = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .bold))
                    Text("Open Quick Inspection")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 16, weight: .bold))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.ember, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Inline fallbacks — kept so the slope can have its own photos
            // even if QuickInspection isn't used.
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCamera = true
                } label: {
                    miniPhotoButton(icon: "camera.fill", title: "Capture")
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $pickerItems,
                             maxSelectionCount: 0,
                             selectionBehavior: .ordered,
                             matching: .images) {
                    miniPhotoButton(icon: "photo.on.rectangle.angled",
                                    title: isImporting ? "Importing…" : "Library")
                }
                .disabled(isImporting)
            }

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { idx, img in
                            thinPhotoTile(img, index: idx)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14, radius: 16)
    }

    private func miniPhotoButton(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
            Text(title).font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.canvas, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
    }

    private func thinPhotoTile(_ img: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Color(.secondarySystemBackground)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 0.6))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                photos.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.scrim, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    photos.append(img)
                }
            }
            pickerItems = []
            isImporting = false
        }
    }

    // MARK: Orientation card

    private var orientationCard: some View {
        SlopeCard(title: "Orientation", icon: "safari.fill") {
            SegmentedRow(options: orientationOptions, selection: $orientation)
        }
    }

    // MARK: Hail / Wind / Wear

    private var hailCard: some View {
        SlopeCard(title: "Hail Damage", icon: "circle.hexagongrid.fill", tint: Theme.crimson) {
            confidenceChip(for: .hail)
            StepperRow(label: "Bruises",        value: $hailBruise,   range: 0...99)
            StepperRow(label: "Mat Fractures",  value: $hailFracture, range: 0...99)
            StepperRow(label: "Granule Loss with Exposed Mat",
                                                value: $hailGranule,  range: 0...99)
        }
    }

    private var windCard: some View {
        SlopeCard(title: "Wind Damage", icon: "wind", tint: Theme.amber) {
            confidenceChip(for: .wind)
            StepperRow(label: "Creased Shingles", value: $windCrease,  range: 0...99)
            StepperRow(label: "Missing Shingles", value: $windMissing, range: 0...99)
            StepperRow(label: "Lifted / Unsealed", value: $windLifted, range: 0...99)
        }
    }

    private var wearCard: some View {
        SlopeCard(title: "Wear", icon: "clock.arrow.circlepath", tint: Theme.inkSoft) {
            confidenceChip(for: .wear)
            ToggleRow(label: "Natural Weathering",   isOn: $wearNatural)
            ToggleRow(label: "Foot Traffic",         isOn: $wearFoot)
            ToggleRow(label: "Manufacturing Defect", isOn: $wearMfg)
        }
    }

    // MARK: Cost card

    private var costCard: some View {
        SlopeCard(title: "Cost Inputs", icon: "dollarsign.circle.fill", tint: Theme.ember) {
            StepperRow(label: "D — Damaged Units / Square",
                       value: $damagedUnitsPerSquare, range: 0...50)

            CurrencyFieldRow(label: "U — Unit Repair Cost", value: $unitRepairCost)

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "R — Repair Difficulty Factor")
                HStack(spacing: 8) {
                    ForEach(difficultyOptions, id: \.value) { opt in
                        Button {
                            difficultyFactor = opt.value
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Text(opt.label)
                                    .font(.system(size: 15, weight: .heavy))
                                Text(String(format: "%.2f", opt.value))
                                    .font(.system(size: 12, weight: .semibold))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(difficultyFactor == opt.value ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(difficultyFactor == opt.value ? Theme.ember : Theme.card,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(difficultyFactor == opt.value ? .clear : Theme.hairline,
                                        lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            StepperRow(label: "A — Area (Squares)",
                       value: $areaSquares, range: 1...100)

            // Live readonly slope cost
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Repair Cost (D × U × R × A)")
                Text(currency(liveRepairCost))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            CurrencyFieldRow(label: "Replacement Cost (Slope)",
                             value: $replacementCostSlope)
        }
    }

    // MARK: Functional damage

    // MARK: Phase 8 (flag-gated) AI confidence chips

    /// Lightweight category enum used only to label the AI confidence chip.
    /// Mirrors the mapping in the Phase 8 spec.
    private enum AICategory { case hail, wind, wear, missing }

    /// Findings sourced for this slope. Reads from the live `InspectionStore`
    /// where the analyze pipeline writes via `setAIFindings`. Empty until the
    /// inspector runs a Quick Inspection on this slope.
    private var aiFindings: [InspectionFinding] {
        guard let insp = store.inspection(with: reportId),
              let s = insp.slopes.first(where: { $0.orientation == orientation }) else {
            return []
        }
        return s.aiFindings
    }

    private func meanConfidence(for category: AICategory) -> Int? {
        let labels: Set<String>
        switch category {
        case .hail:    labels = ["hail_damage"]
        case .wind:    labels = ["wind_creasing"]
        case .missing: labels = ["missing_shingles"]
        case .wear:    labels = ["granule_loss", "cracking_splitting", "blistering",
                                  "algae_moss", "bruising", "structural_sagging",
                                  "flashing_damage"]
        }
        let matched = aiFindings.filter { labels.contains($0.label) }
        guard !matched.isEmpty else { return nil }
        let total = matched.reduce(0) { $0 + $1.confidence }
        return Int((Double(total) / Double(matched.count)).rounded())
    }

    @ViewBuilder
    private func confidenceChip(for category: AICategory) -> some View {
        if APIKeys.useStructuredConfidence,
           let pct = meanConfidence(for: category) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.sky)
                    Text("AI confidence: \(pct)%")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.canvas, in: .capsule)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
                .cardStyle(padding: 0, radius: 14)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showConfidenceInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }

    private var confidenceInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI confidence")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("NN% is the model’s self-reported confidence for this category on this slope. Low confidence (under 60%) means an inspector should verify the finding directly.")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showConfidenceInfo = false
                } label: {
                    Text("OK")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas)
        }
    }

    private var functionalCard: some View {
        SlopeCard(title: "Functional Damage", icon: "stethoscope") {
            HStack(spacing: 10) {
                FunctionalChip(title: "Functional damage present",
                               systemImage: "exclamationmark.octagon.fill",
                               selected: functionalChoice == .functional,
                               selectedColor: Theme.crimson) {
                    functionalChoice = (functionalChoice == .functional) ? .none : .functional
                }
                FunctionalChip(title: "Cosmetic only",
                               systemImage: "eye.fill",
                               selected: functionalChoice == .cosmetic,
                               selectedColor: Theme.amber) {
                    functionalChoice = (functionalChoice == .cosmetic) ? .none : .cosmetic
                }
            }
        }
    }

    // MARK: Sticky bottom bar

    private var stickyBar: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                showDiscardConfirm = true
            } label: {
                Text("Discard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.crimson)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.crimson.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Save Slope")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.3), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(minHeight: 88)
        .background(
            Theme.canvas
                .overlay(Rectangle().fill(Theme.hairline)
                    .frame(height: 0.5), alignment: .top)
        )
    }

    // MARK: Save

    private func save() {
        let slope = Slope(
            orientation: orientation,
            pitchRiseOver12: pitchRiseOver12,
            areaSquares: Double(areaSquares),
            testSquareCount: testSquareCount,
            damagedUnitsPerSquare: damagedUnitsPerSquare,
            unitRepairCost: unitRepairCost,
            repairDifficultyFactor: difficultyFactor,
            repairCostSlope: liveRepairCost,
            replacementCostSlope: replacementCostSlope,
            functionalDamagePresent: functionalChoice == .functional,
            cosmeticOnly: functionalChoice == .cosmetic,
            slopeReplacementRecommended: false,
            slopeRepairsRecommended: false,
            damageTypes: SlopeDamageTypes(
                hail: SlopeHailDamage(
                    asphaltBruise: hailBruise,
                    asphaltMatFracture: hailFracture,
                    asphaltGranuleLossExposed: hailGranule
                ),
                wind: SlopeWindDamage(
                    shingleCrease: windCrease,
                    shingleMissing: windMissing,
                    shingleLiftedUnsealed: windLifted
                ),
                wear: SlopeWearDamage(
                    naturalWeathering: wearNatural,
                    footTraffic: wearFoot,
                    manufacturingDefect: wearMfg
                )
            )
        )
        // upsertSlope re-runs DecisionEngine.decide on the inspection,
        // so per-slope verdicts and the roof summary stay consistent.
        store.upsertSlope(slope, on: reportId)
        store.setPhotos(photos, for: reportId, orientation: orientation)
        // Activity log + low-confidence training queue.
        if let insp = store.inspection(with: reportId) {
            let kind: ActivityEvent.Kind = existingOrientation == nil ? .slopeAdded : .slopeEdited
            let damage = slope.damageTypes.hail.asphaltBruise
                + slope.damageTypes.hail.asphaltMatFracture
                + slope.damageTypes.hail.asphaltGranuleLossExposed
                + slope.damageTypes.wind.shingleCrease
                + slope.damageTypes.wind.shingleMissing
            ActivityStore.shared.log(
                kind,
                summary: "\(slope.orientation) slope \(existingOrientation == nil ? "added" : "edited")",
                detail: String(format: "%.1f sq \u{00B7} pitch %d/12 \u{00B7} %d damage hits",
                               slope.areaSquares, slope.pitchRiseOver12, damage),
                on: insp
            )
            TrainingQueueStore.shared.enqueueFromSlope(slope, on: reportId)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Reusable subviews

private struct SlopeCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = Theme.ink
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 18)
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Theme.inkSoft)
    }
}

private struct StepperRow: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 12) {
                Button {
                    value = max(range.lowerBound, value - 1)
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

                Text("\(value)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.canvas, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.hairline, lineWidth: 1))

                Button {
                    value = min(range.upperBound, value + 1)
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

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.ember)
                .scaleEffect(1.1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct SegmentedRow: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(opt)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(selection == opt ? .white : Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(selection == opt ? Theme.ember : Theme.card,
                                    in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(selection == opt ? .clear : Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CurrencyFieldRow: View {
    let label: String
    @Binding var value: Double
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                TextField("0.00", value: $value,
                          format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.canvas, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(focused ? Theme.ember : Theme.hairline, lineWidth: focused ? 1.5 : 1))
        }
    }
}

private struct FunctionalChip: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let selectedColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? selectedColor : Theme.card,
                        in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera bridge

private struct SlopePhotoCameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            // Cloud simulator fallback so the flow still completes.
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            Task { @MainActor in self.onPick(image) }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in self.onPick(nil) }
        }
    }
}
