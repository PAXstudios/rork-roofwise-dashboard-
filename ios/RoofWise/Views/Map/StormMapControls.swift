import SwiftUI

// MARK: - Filter bar (Step 5)
//
// Hail / Wind / Both chips, contextual intensity sliders, and a date-range pill
// that opens the presets sheet. All touch targets ≥56pt for gloved hands.

struct StormFilterBar: View {
    @Binding var kindFilter: StormKindFilter
    @Binding var hailSizeMin: Double
    @Binding var windMphMin: Double
    let dateRangeLabel: String
    var onDatePill: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StormKindFilter.allCases) { k in
                            chip(k)
                        }
                    }
                    .padding(.vertical, 2)
                }
                datePill
            }

            if kindFilter == .hail || kindFilter == .both {
                slider(
                    icon: "cloud.hail.fill",
                    title: "Hail ≥",
                    value: $hailSizeMin,
                    range: 0.5...3.0,
                    step: 0.25,
                    tint: Theme.sky,
                    valueLabel: String(format: "%.2f\"", hailSizeMin)
                )
            }
            if kindFilter == .wind || kindFilter == .both {
                slider(
                    icon: "wind",
                    title: "Wind ≥",
                    value: $windMphMin,
                    range: 40...120,
                    step: 5,
                    tint: Theme.ember,
                    valueLabel: "\(Int(windMphMin)) mph"
                )
            }
            if kindFilter == .tornado {
                tornadoNote
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func accent(_ k: StormKindFilter) -> Color {
        switch k {
        case .hail:    return Theme.sky
        case .wind:    return Theme.ember
        case .tornado: return Theme.crimson
        case .both:    return Theme.ink
        }
    }

    /// Tornadoes carry no user-tunable magnitude slider — they always surface.
    private var tornadoNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "tornado")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                .foregroundStyle(Theme.crimson)
                .frame(width: 22)
            Text("All tornado reports shown")
                .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 4)
    }

    private func chip(_ k: StormKindFilter) -> some View {
        let selected = kindFilter == k
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(Theme.Motion.snappy) { kindFilter = k }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: k.icon)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .bold))
                Text(k.label)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(selected ? AnyShapeStyle(accent(k)) : AnyShapeStyle(.ultraThinMaterial), in: .capsule)
            .overlay(Capsule().stroke(selected ? .clear : Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private var datePill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDatePill()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: Theme.TypeRamp.meta, weight: .bold))
                Text(dateRangeLabel)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func slider(icon: String, title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        tint: Color, valueLabel: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
            Slider(value: value, in: range, step: step)
                .tint(tint)
            Text(valueLabel)
                .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 4)
    }
}

// MARK: - Layer popover (Step 9)

struct StormLayerPopover: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showStorms: Bool
    @Binding var showImpactRadius: Bool
    @Binding var showServiceArea: Bool
    @Binding var showFootprint: Bool
    @Binding var showHeat: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Map Layers")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    row(icon: "cloud.bolt.rain.fill", tint: Theme.crimson,
                        title: "Storms", subtitle: "Hail & wind events",
                        isOn: $showStorms)
                    row(icon: "circle.dashed", tint: Theme.ember,
                        title: "Impact Radius", subtitle: "Likely-hit homes around each storm",
                        isOn: $showImpactRadius)
                    row(icon: "map.fill", tint: Theme.ink,
                        title: "Service Area", subtitle: "Your saved ZIPs & cities",
                        isOn: $showServiceArea)
                    row(icon: "person.2.fill", tint: Theme.sky,
                        title: "Footprint", subtitle: "Leads, inspections & signed jobs",
                        isOn: $showFootprint)
                    row(icon: "flame.fill", tint: Theme.amber,
                        title: "Heat Density", subtitle: "Storm concentration grid",
                        isOn: $showHeat)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.canvas)
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String,
                     isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(12)
        .frame(minHeight: 64)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

// MARK: - Map FAB (Step 9)

struct MapFAB: View {
    let symbol: String
    var tint: Color = Theme.ink
    var filled: Bool = false
    var diameter: CGFloat = 64
    var action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                .foregroundStyle(filled ? .white : tint)
                .frame(width: diameter, height: diameter)
                .background(
                    filled ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial),
                    in: .rect(cornerRadius: 18)
                )
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(filled ? .clear : Theme.hairline, lineWidth: 0.6))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}
