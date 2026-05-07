import SwiftUI
import PhotosUI
import UIKit

// MARK: - Steps

enum SlopeCaptureStep: Int, CaseIterable, Identifiable {
    case orientation, geometry, photos, damage, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .orientation: return "Orientation"
        case .geometry:    return "Geometry"
        case .photos:      return "Photos"
        case .damage:      return "Damage Counts"
        case .review:      return "Review"
        }
    }
}

private let kOrientations: [String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

// MARK: - Working draft (pre-cost)

private struct SlopeDraft {
    var orientation: String = ""
    var pitchRiseOver12: Int = 6
    // Stored as half-squares so the stepper feels glove-friendly.
    // areaSquares = halfSquares / 2.0
    var halfSquares: Int = 12              // 6.0 squares default
    var testSquareCount: Int = 1
    var damagedUnitsPerSquare: Int = 0
    var unitRepairCost: Double = 45        // typical asphalt unit repair
    var repairDifficultyFactor: Double = 1.2

    // hail
    var hailBruise: Int = 0
    var hailFracture: Int = 0
    var hailGranule: Int = 0
    // wind
    var windCrease: Int = 0
    var windMissing: Int = 0
    var windLifted: Int = 0
    // wear toggles
    var wearNatural: Bool = false
    var wearFoot: Bool = false
    var wearMfg: Bool = false

    var areaSquares: Double { Double(halfSquares) / 2.0 }

    var repairCostSlope: Double {
        Double(damagedUnitsPerSquare) * unitRepairCost * repairDifficultyFactor * areaSquares
    }

    /// Mock asphalt-equivalent replacement cost.
    var replacementCostSlope: Double { areaSquares * 450.0 }

    var functional: Bool {
        // Haag asphalt rule: 8+ damaged units per square = functional.
        damagedUnitsPerSquare >= 8
    }

    var cosmeticOnly: Bool {
        damagedUnitsPerSquare > 0 && damagedUnitsPerSquare < 8
    }

    func toSlope() -> Slope {
        Slope(
            orientation: orientation,
            pitchRiseOver12: pitchRiseOver12,
            areaSquares: areaSquares,
            testSquareCount: testSquareCount,
            damagedUnitsPerSquare: damagedUnitsPerSquare,
            unitRepairCost: unitRepairCost,
            repairDifficultyFactor: repairDifficultyFactor,
            repairCostSlope: repairCostSlope,
            replacementCostSlope: replacementCostSlope,
            functionalDamagePresent: functional,
            cosmeticOnly: cosmeticOnly,
            slopeReplacementRecommended: functional,
            slopeRepairsRecommended: !functional && damagedUnitsPerSquare > 0,
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
    }
}

// MARK: - Sheet

struct SlopeCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared

    let reportId: String

    /// Optional existing slope to edit. If non-nil, prefills the wizard.
    var existingOrientation: String? = nil

    @State private var draft = SlopeDraft()
    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var showCamera = false

    @State private var step: SlopeCaptureStep = .orientation
    @State private var showCancelConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                progress
                ScrollView {
                    Group {
                        switch step {
                        case .orientation: orientationStep
                        case .geometry:    geometryStep
                        case .photos:      photosStep
                        case .damage:      damageStep
                        case .review:      reviewStep
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
        }
        .onAppear(perform: prefillIfEditing)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                if let image {
                    photos.append(image)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Discard slope?",
                            isPresented: $showCancelConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Anything you've entered will be lost.")
        }
    }

    // MARK: prefill (edit mode)

    private func prefillIfEditing() {
        guard let orient = existingOrientation,
              let insp = store.inspection(with: reportId),
              let s = insp.slopes.first(where: { $0.orientation == orient }) else { return }
        draft.orientation = s.orientation
        draft.pitchRiseOver12 = s.pitchRiseOver12
        draft.halfSquares = max(1, Int((s.areaSquares * 2).rounded()))
        draft.testSquareCount = max(1, s.testSquareCount)
        draft.damagedUnitsPerSquare = s.damagedUnitsPerSquare
        draft.unitRepairCost = s.unitRepairCost
        draft.repairDifficultyFactor = s.repairDifficultyFactor
        draft.hailBruise = s.damageTypes.hail.asphaltBruise
        draft.hailFracture = s.damageTypes.hail.asphaltMatFracture
        draft.hailGranule = s.damageTypes.hail.asphaltGranuleLossExposed
        draft.windCrease = s.damageTypes.wind.shingleCrease
        draft.windMissing = s.damageTypes.wind.shingleMissing
        draft.windLifted = s.damageTypes.wind.shingleLiftedUnsealed
        draft.wearNatural = s.damageTypes.wear.naturalWeathering
        draft.wearFoot = s.damageTypes.wear.footTraffic
        draft.wearMfg = s.damageTypes.wear.manufacturingDefect
        photos = store.photos(for: reportId, orientation: s.orientation)
    }

    // MARK: header / progress / footer

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
                Text(existingOrientation == nil ? "Add Slope" : "Edit Slope")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Step \(step.rawValue + 1) of \(SlopeCaptureStep.allCases.count) · \(step.title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: some View {
        let total = SlopeCaptureStep.allCases.count
        let value = CGFloat(step.rawValue + 1) / CGFloat(total)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(LinearGradient(
                    colors: [Theme.ember, Theme.amber],
                    startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * value))
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
                    advance(by: 1)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(step == .review ? "Save Slope" : "Next")
                    Image(systemName: step == .review ? "checkmark" : "arrow.right")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    LinearGradient(
                        colors: canAdvance
                            ? [Theme.ink, Color(red: 0.12, green: 0.20, blue: 0.42)]
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
        case .orientation:
            return !draft.orientation.isEmpty
        default:
            return true
        }
    }

    private func advance(by delta: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = step.rawValue + delta
        guard let s = SlopeCaptureStep(rawValue: next) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step = s
        }
    }

    // MARK: Save

    private func save() {
        let slope = draft.toSlope()
        store.upsertSlope(slope, on: reportId)
        store.setPhotos(photos, for: reportId, orientation: slope.orientation)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: Step 1 — Orientation

    private var orientationStep: some View {
        SlopeSection(
            title: "Slope orientation",
            subtitle: "Which face are you scoring?",
            icon: "safari.fill"
        ) {
            SlopeStringChips(label: "Compass face",
                             options: kOrientations,
                             selection: $draft.orientation,
                             minimum: 90)

            if existingSlopeConflict {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("This face already has a slope — saving will overwrite it.")
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(12)
                .background(Theme.amberSoft, in: .rect(cornerRadius: 12))
            }
        }
    }

    private var existingSlopeConflict: Bool {
        guard !draft.orientation.isEmpty,
              draft.orientation != existingOrientation,
              let insp = store.inspection(with: reportId) else { return false }
        return insp.slopes.contains { $0.orientation == draft.orientation }
    }

    // MARK: Step 2 — Geometry

    private var geometryStep: some View {
        SlopeSection(
            title: "Pitch & area",
            subtitle: "Used for cost roll-up and Haag math.",
            icon: "ruler.fill"
        ) {
            SlopeBigStepper(label: "Pitch (rise / 12)",
                            value: $draft.pitchRiseOver12,
                            step: 1, range: 0...12,
                            format: { "\($0) / 12" })

            SlopeBigStepper(label: "Area (squares)",
                            value: $draft.halfSquares,
                            step: 1, range: 1...80,
                            format: { String(format: "%.1f sq", Double($0) / 2.0) })
        }
    }

    // MARK: Step 3 — Photos

    private var photosStep: some View {
        SlopeSection(
            title: "Reference photos",
            subtitle: "Capture or attach photos of this slope.",
            icon: "camera.fill"
        ) {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showCamera = true
                } label: {
                    photoActionLabel(icon: "camera.fill", title: "Camera",
                                     tintFG: .white, tintBG: Theme.ember)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $pickerItems,
                             maxSelectionCount: 0,
                             selectionBehavior: .ordered,
                             matching: .images) {
                    photoActionLabel(icon: "photo.on.rectangle.angled",
                                     title: isImporting ? "Importing…" : "Library",
                                     tintFG: Theme.ink, tintBG: Theme.card,
                                     bordered: true)
                }
                .disabled(isImporting)
            }

            if photos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    Text("No photos yet")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Photos are optional — you can score the slope without them.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.hairline, lineWidth: 1))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { idx, img in
                        photoTile(img, index: idx)
                    }
                }
            }
        }
    }

    private func photoActionLabel(icon: String, title: String,
                                  tintFG: Color, tintBG: Color,
                                  bordered: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.system(size: 18, weight: .bold))
        }
        .foregroundStyle(tintFG)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(tintBG, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(bordered ? Theme.hairline : .clear, lineWidth: 1)
        )
    }

    private func photoTile(_ img: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.hairline, lineWidth: 0.6))

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                photos.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.65), in: .circle)
            }
            .buttonStyle(.plain)
            .padding(6)
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

    // MARK: Step 4 — Damage counts

    private var damageStep: some View {
        VStack(spacing: 22) {
            SlopeSection(
                title: "Test square",
                subtitle: "Average damage in a 100 sq ft test square.",
                icon: "square.grid.3x3.fill"
            ) {
                SlopeBigStepper(label: "Test squares inspected",
                                value: $draft.testSquareCount,
                                step: 1, range: 1...10,
                                format: { "\($0)" })

                SlopeBigStepper(label: "Damaged units / 100 sq ft",
                                value: $draft.damagedUnitsPerSquare,
                                step: 1, range: 0...30,
                                format: { "\($0)" })

                damageVerdictBanner
            }

            SlopeSection(
                title: "Hail damage",
                subtitle: "Per Haag asphalt indicators.",
                icon: "circle.hexagongrid.fill"
            ) {
                SlopeBigStepper(label: "Bruises",
                                value: $draft.hailBruise,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
                SlopeBigStepper(label: "Mat fractures",
                                value: $draft.hailFracture,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
                SlopeBigStepper(label: "Granule loss (exposed)",
                                value: $draft.hailGranule,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
            }

            SlopeSection(
                title: "Wind damage",
                subtitle: "Tabs creased, missing, or lifted.",
                icon: "wind"
            ) {
                SlopeBigStepper(label: "Creased shingles",
                                value: $draft.windCrease,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
                SlopeBigStepper(label: "Missing shingles",
                                value: $draft.windMissing,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
                SlopeBigStepper(label: "Lifted / unsealed",
                                value: $draft.windLifted,
                                step: 1, range: 0...50,
                                format: { "\($0)" })
            }

            SlopeSection(
                title: "Wear & exclusions",
                subtitle: "Pre-existing conditions, not storm-related.",
                icon: "clock.arrow.circlepath"
            ) {
                SlopeToggleRow(label: "Natural weathering", isOn: $draft.wearNatural)
                SlopeToggleRow(label: "Foot traffic",        isOn: $draft.wearFoot)
                SlopeToggleRow(label: "Manufacturing defect", isOn: $draft.wearMfg)
            }
        }
    }

    private var damageVerdictBanner: some View {
        let functional = draft.functional
        let title = functional ? "Functional damage" : (draft.damagedUnitsPerSquare > 0 ? "Cosmetic only" : "No damage scored")
        let detail = functional
            ? "≥ 8 hits / 100 sq ft — replacement supportable per Haag."
            : (draft.damagedUnitsPerSquare > 0
               ? "Below the 8-hit Haag threshold — repair recommended."
               : "Step up the damaged-unit count once you've inspected the slope.")
        let bg: Color = functional ? Theme.crimson.opacity(0.12)
                                   : (draft.damagedUnitsPerSquare > 0 ? Theme.amberSoft : Theme.canvas)
        let fg: Color = functional ? Theme.crimson
                                   : (draft.damagedUnitsPerSquare > 0 ? Theme.amber : Theme.inkSoft)
        return HStack(spacing: 12) {
            Image(systemName: functional ? "exclamationmark.octagon.fill"
                                         : (draft.damagedUnitsPerSquare > 0 ? "exclamationmark.triangle.fill"
                                                                            : "info.circle.fill"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(fg)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: Step 5 — Review

    private var reviewStep: some View {
        SlopeSection(
            title: "Review & save",
            subtitle: "Looks good? Save to add this slope to the report.",
            icon: "checkmark.seal.fill"
        ) {
            reviewRow(title: "Face",
                      lines: [draft.orientation,
                              "Pitch \(draft.pitchRiseOver12)/12 · \(String(format: "%.1f", draft.areaSquares)) sq"])

            reviewRow(title: "Test square",
                      lines: ["\(draft.testSquareCount) test square\(draft.testSquareCount == 1 ? "" : "s")",
                              "\(draft.damagedUnitsPerSquare) damaged units / 100 sq ft",
                              draft.functional ? "Functional damage — replacement supportable"
                                               : (draft.damagedUnitsPerSquare > 0 ? "Cosmetic only" : "No damage scored")])

            reviewRow(title: "Hail",
                      lines: [
                        "Bruise \(draft.hailBruise) · Fracture \(draft.hailFracture) · Granule \(draft.hailGranule)"
                      ])

            reviewRow(title: "Wind",
                      lines: [
                        "Crease \(draft.windCrease) · Missing \(draft.windMissing) · Lifted \(draft.windLifted)"
                      ])

            reviewRow(title: "Wear",
                      lines: [wearLine])

            reviewRow(title: "Costs",
                      lines: [
                        "Repair: " + currency(draft.repairCostSlope),
                        "Replacement: " + currency(draft.replacementCostSlope),
                        "Photos attached: \(photos.count)"
                      ])
        }
    }

    private var wearLine: String {
        var parts: [String] = []
        if draft.wearNatural { parts.append("Natural weathering") }
        if draft.wearFoot    { parts.append("Foot traffic") }
        if draft.wearMfg     { parts.append("Mfg defect") }
        return parts.isEmpty ? "None noted" : parts.joined(separator: " · ")
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func reviewRow(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
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
}

// MARK: - Reusable slope-form components

private struct SlopeSection<Content: View>: View {
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

private struct SlopeBigStepper: View {
    let label: String
    @Binding var value: Int
    var step: Int = 1
    var range: ClosedRange<Int>
    var format: (Int) -> String = { String($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)

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
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
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

private struct SlopeStringChips: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    var minimum: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { opt in
                    let selected = opt == selection
                    Button {
                        selection = opt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(opt)
                            .font(.system(size: 18, weight: .heavy))
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
        }
    }
}

private struct SlopeToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(isOn ? Theme.ember : Theme.inkFaint)
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isOn ? Theme.ember.opacity(0.4) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera picker (UIImagePickerController bridge)

private struct CameraPickerView: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            // Cloud simulator has no camera — fall back to photo library so the
            // flow still completes without crashing.
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
