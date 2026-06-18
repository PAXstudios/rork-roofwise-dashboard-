import SwiftUI

// MARK: - Map legend sheet
//
// Opened from the bottom-leading legend chip. A glanceable key for everything
// the map renders: storm pins (type glyph + severity colour + recency badge),
// the footprint pins (lead / inspection / signed job), and the toggleable map
// layers (service area, impact radius, heat density). All Theme tokens.

struct StormLegendSheet: View {
    private enum LegendStorm { case hail, wind, tornado }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                title
                stormsSection
                footprintSection
                layersSection
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .background(Theme.canvas)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Map Legend")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("What every pin, ring and colour means.")
                .font(.system(size: Theme.TypeRamp.metaSm))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: Storms

    private var stormsSection: some View {
        section(title: "Storms", icon: "cloud.bolt.rain.fill", tint: Theme.crimson) {
            VStack(spacing: 14) {
                stormTypeRow(.hail, title: "Hail", caption: "White H")
                stormTypeRow(.wind, title: "Wind", caption: "Chevron + W")
                stormTypeRow(.tornado, title: "Tornado", caption: "Funnel icon")
                Divider().overlay(Theme.hairline)
                scaleRow(title: "Severity",
                         items: [("Severe", Theme.crimson),
                                 ("Moderate", Theme.amber),
                                 ("Minor", Theme.inkFaint)])
                scaleRow(title: "Recency badge",
                         items: [("≤30d", Theme.mint),
                                 ("31–90d", Theme.amber),
                                 (">90d", Theme.inkFaint)])
            }
        }
    }

    /// One storm type: the glyph rendered in all three severity colours, plus
    /// the type name and a short description of its mark.
    private func stormTypeRow(_ kind: LegendStorm, title: String, caption: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                pinSwatch(kind, color: Theme.crimson)
                pinSwatch(kind, color: Theme.amber)
                pinSwatch(kind, color: Theme.inkFaint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(caption)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
    }

    private func scaleRow(title: String, items: [(String, Color)]) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 96, alignment: .leading)
            HStack(spacing: 10) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 5) {
                        Circle().fill(item.1).frame(width: 11, height: 11)
                        Text(item.0)
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: Footprint

    private var footprintSection: some View {
        section(title: "Footprint", icon: "person.2.fill", tint: Theme.sky) {
            VStack(spacing: 14) {
                footprintRow(kind: .lead, title: "Lead",
                             subtitle: "Open ring — still chasing")
                footprintRow(kind: .scheduledInspection, title: "Inspection scheduled",
                             subtitle: "Filled + calendar")
                footprintRow(kind: .signedJob, title: "Signed job",
                             subtitle: "Filled + check")
            }
        }
    }

    private func footprintRow(kind: FootprintPin.Kind, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            FootprintPinView(kind: kind)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
    }

    // MARK: Map layers

    private var layersSection: some View {
        section(title: "Map Layers", icon: "square.3.layers.3d", tint: Theme.ink) {
            VStack(spacing: 14) {
                layerRow(title: "Service area",
                         subtitle: "Your saved ZIPs & cities") { serviceAreaSwatch }
                layerRow(title: "Storm impact radius",
                         subtitle: "Likely-hit homes around a storm") { impactRingSwatch }
                layerRow(title: "Heat density grid",
                         subtitle: "Storm concentration by cell") { heatGridSwatch }
            }
        }
    }

    private func layerRow<S: View>(title: String, subtitle: String,
                                   @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 14) {
            swatch().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
    }

    private var serviceAreaSwatch: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Theme.ink.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ink, lineWidth: 1.5))
    }

    private var impactRingSwatch: some View {
        Circle()
            .fill(Theme.ember.opacity(0.12))
            .overlay(Circle().stroke(Theme.ember.opacity(0.55), lineWidth: 2))
    }

    private var heatGridSwatch: some View {
        // 2×2 mini grid ramping ember → crimson, mirroring the live heat overlay.
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                cell(Theme.ember.opacity(0.30)); cell(Theme.ember.opacity(0.55))
            }
            HStack(spacing: 2) {
                cell(Theme.crimson.opacity(0.45)); cell(Theme.crimson.opacity(0.70))
            }
        }
        .clipShape(.rect(cornerRadius: 7))
    }

    private func cell(_ color: Color) -> some View {
        Rectangle().fill(color).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Building blocks

    /// White-haloed pin disc with a type glyph — matches `StormPinView` styling.
    private func pinSwatch(_ kind: LegendStorm, color: Color) -> some View {
        let size: CGFloat = 26
        return ZStack {
            Circle().fill(.white).frame(width: size + 6, height: size + 6)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            Circle().fill(color).frame(width: size, height: size)
            stormGlyph(kind, size: size)
        }
    }

    @ViewBuilder
    private func stormGlyph(_ kind: LegendStorm, size: CGFloat) -> some View {
        switch kind {
        case .hail:
            Text("H")
                .font(.system(size: size * 0.46, weight: .black))
                .foregroundStyle(.white)
        case .wind:
            VStack(spacing: -size * 0.08) {
                Image(systemName: "chevron.up")
                    .font(.system(size: size * 0.26, weight: .black))
                Text("W")
                    .font(.system(size: size * 0.40, weight: .black))
            }
            .foregroundStyle(.white)
        case .tornado:
            Image(systemName: "tornado")
                .font(.system(size: size * 0.5, weight: .black))
                .foregroundStyle(.white)
        }
    }

    private func section<Content: View>(title: String, icon: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)
                Text(title)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }
}
