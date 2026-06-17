import SwiftUI
import CoreLocation

/// Full roof-measurement + cost-estimate surface for a customer property.
///
/// Pipeline: geocode the customer's address → pull Google Solar
/// `buildingInsights` (real per-slope areas, pitch, azimuth) → render a
/// satellite aerial tile of the roof → compute an installed-cost estimate the
/// rep can retune by material. This is the customer-profile twin of the
/// standalone Cost Estimator, pre-seeded with the property on file.
struct RoofMeasureSheet: View {
    @Environment(\.dismiss) private var dismiss

    let ownerName: String
    let address: String
    /// Pre-selected material when the customer already has one on file.
    var initialMaterial: EstimateMaterial = .asphaltArch

    @State private var coord: CLLocationCoordinate2D?
    @State private var measurements: RoofMeasurements?
    @State private var phase: LoadPhase = .loading
    @State private var loadTask: Task<Void, Never>?

    // Cost inputs (live-retunable)
    @State private var material: EstimateMaterial = .asphaltArch
    @State private var quality: EstimateQuality = .better

    private let solar: SolarServicing = SolarServiceFactory.shared
    private let geocoder: GeocodingService = GeocodingServiceFactory.shared

    private enum LoadPhase: Equatable {
        case loading, ready, failed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aerialHero
                    switch phase {
                    case .loading:  loadingCard
                    case .failed:   failureCard
                    case .ready:
                        if let m = measurements {
                            measurementCard(m)
                            slopeBreakdown(m)
                            materialPicker
                            estimateCard(m)
                            disclaimer
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Roof Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            }
        }
        .onAppear {
            material = initialMaterial
            if phase == .loading { startLoad() }
        }
        .onDisappear { loadTask?.cancel() }
    }

    // MARK: Aerial hero

    @ViewBuilder private var aerialHero: some View {
        if let coord {
            RoofAerialMap(coord: coord,
                          areaSqFt: measurements?.totalAreaSqFt ?? 2400,
                          address: address)
        } else {
            Color(.secondarySystemBackground)
                .frame(height: 240)
                .overlay {
                    ZStack {
                        Theme.canvas
                        VStack(spacing: 6) {
                            ProgressView().tint(Theme.amber)
                            Text("Locating roof…")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }

    // MARK: States

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Measuring roof from satellite…")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Google Solar · per-slope area & pitch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aerial measurement unavailable")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("This property may be outside Google's high-resolution coverage.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button {
                phase = .loading
                startLoad()
            } label: {
                Text("Try again")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.ember, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Measurement summary

    private func measurementCard(_ m: RoofMeasurements) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.amberSoft)
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEASURED ROOF AREA")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.inkSoft)
                    Text(String(format: "%.1f squares", m.totalAreaSquares))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Text(SolarServiceFactory.shared.isLive ? "GOOGLE SOLAR" : "ESTIMATE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(SolarServiceFactory.shared.isLive ? Theme.mint : Theme.inkFaint,
                                in: .capsule)
            }
            HStack(spacing: 18) {
                statPill(value: "\(m.segments.count)", label: "slopes")
                statPill(value: "\(avgPitchRise(m)):12", label: "avg pitch")
                statPill(value: String(format: "%,.0f", m.totalAreaSqFt), label: "sq ft")
            }
            if let date = m.imageryDate {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .heavy))
                    Text("Imagery: \(Self.imageryFmt.string(from: date))")
                        .font(.system(size: 10, weight: .semibold))
                    if imageryStale(date) {
                        Text("· >2 yrs old")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.amber)
                    }
                }
                .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Slope breakdown

    private func slopeBreakdown(_ m: RoofMeasurements) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SLOPE-BY-SLOPE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkSoft)
            ForEach(m.segments) { seg in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.emberSoft)
                        Text(seg.orientation)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(seg.orientation)-facing slope")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(seg.pitchRiseOver12):12 pitch · \(Int(seg.azimuthDegrees))° azimuth")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f sq", seg.areaSquares))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                        Text(String(format: "%,.0f sf", seg.areaSqFt))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Theme.canvas, in: .rect(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Material picker

    private var materialPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROOFING MATERIAL")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(EstimateMaterial.allCases) { mat in
                    let selected = material == mat
                    Button {
                        material = mat
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mat.symbol)
                                .font(.system(size: 13, weight: .heavy))
                            Text(mat.displayName)
                                .font(.system(size: 12, weight: .heavy))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selected ? .white : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(selected ? Theme.ember : Theme.canvas,
                                    in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("Quality", selection: $quality) {
                ForEach(EstimateQuality.allCases) { q in
                    Text(q.displayName).tag(q)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Estimate

    private func estimateCard(_ m: RoofMeasurements) -> some View {
        let est = currentEstimate(m)
        return VStack(alignment: .leading, spacing: 12) {
            Text("ESTIMATED REPLACEMENT COST")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkSoft)
            Text(currency(est.subtotal))
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Range: \(est.rangeLabel)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.mint)
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10, weight: .heavy))
                Text(String(format: "%@ / sq · %.1f squares",
                            currency(est.pricePerSquare), est.input.totalSquares))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSoft)

            Rectangle().fill(Theme.hairline).frame(height: 0.6).padding(.vertical, 2)

            ForEach(est.lineItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(item.detail)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Text(currency(item.amount))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LinearGradient(colors: [Theme.mintSoft, Theme.card],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.mint.opacity(0.35), lineWidth: 1))
    }

    private var disclaimer: some View {
        Text("Squares and slope pitch are measured from Google's aerial imagery via the Solar API. Final price depends on site access, decking condition, and code upgrades.")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Derived

    private func currentEstimate(_ m: RoofMeasurements) -> CostEstimate {
        let complexity: EstimateComplexity = {
            switch m.segments.count {
            case 0...2: return .simple
            case 3...4: return .average
            case 5...6: return .complex
            default:    return .custom
            }
        }()
        let input = CostEstimateInput(
            address: address,
            totalSquares: m.totalAreaSquares,
            detectedSegmentCount: m.segments.count,
            avgPitchRiseOver12: avgPitchRise(m),
            material: material,
            quality: quality,
            complexity: complexity,
            tearOffLayers: 1,
            includePermit: true,
            includeDisposal: true
        )
        return CostEstimator.estimate(input)
    }

    private func avgPitchRise(_ m: RoofMeasurements) -> Int {
        guard !m.segments.isEmpty else { return 6 }
        let avgDeg = m.segments.map(\.pitchDegrees).reduce(0, +) / Double(m.segments.count)
        return max(0, Int((tan(avgDeg * .pi / 180.0) * 12.0).rounded()))
    }

    private func imageryStale(_ date: Date) -> Bool {
        guard let years = Calendar.current.dateComponents([.year], from: date, to: .now).year else {
            return false
        }
        return years >= 2
    }

    // MARK: Load

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task {
            let resolved = try? await geocoder.geocode(address)
            let c = resolved ?? GeocodingServiceFactory.eagerCoord(forAddress: address)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { self.coord = c }
            }
            let m = try? await solar.measurements(at: c)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if let m {
                        self.measurements = m
                        self.phase = .ready
                    } else {
                        self.phase = .failed
                    }
                }
            }
        }
    }

    private static let imageryFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()
}
