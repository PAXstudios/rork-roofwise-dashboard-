import SwiftUI
import UIKit

/// Live camera overlays for the 10×10 square, individual shingle tabs, and
/// per-damage boxes. Every rect is a Gemini detection — nothing is invented.
struct LiveARSceneOverlay: View {
    var square: CGRect?
    var squareLocked: Bool
    var shingles: [CGRect]
    var markers: [DamageMarker]
    var showFramingGuide: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showFramingGuide, square == nil {
                    LiveSquareFramingGuide()
                }

                if let square {
                    LiveSquareOverlay(region: square, locked: squareLocked, size: geo.size)
                }

                ForEach(Array(shingles.enumerated()), id: \.offset) { index, rect in
                    LiveShingleOverlay(region: rect, size: geo.size)
                        .detectionBoxAppear(index: index)
                }

                LiveDamageLabeledOverlay(markers: markers, size: geo.size)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Aim aid only — not a detection. Shown until Gemini finds a real 10×10.
struct LiveSquareFramingGuide: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.72
            let frame = CGRect(
                x: (geo.size.width - side) / 2,
                y: (geo.size.height - side) / 2,
                width: side,
                height: side
            )
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [8, 6]))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                Text("FRAME 10×10")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: .capsule)
                    .position(x: frame.midX, y: frame.minY + 16)
            }
        }
    }
}

struct LiveSquareOverlay: View {
    let region: CGRect
    let locked: Bool
    let size: CGSize

    var body: some View {
        let frame = CGRect(
            x: region.minX * size.width,
            y: region.minY * size.height,
            width: max(24, region.width * size.width),
            height: max(24, region.height * size.height)
        )
        let color = locked ? Theme.ember : Theme.amber
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, style: StrokeStyle(lineWidth: locked ? 2.4 : 1.6, dash: locked ? [] : [7, 5]))
                .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.08)))
                .frame(width: frame.width, height: frame.height)

            Text(locked ? "10×10 SQ" : "SQUARE")
                .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color, in: .capsule)
                .offset(x: 6, y: -12)
        }
        .position(x: frame.midX, y: frame.midY)
    }
}

struct LiveShingleOverlay: View {
    let region: CGRect
    let size: CGSize

    var body: some View {
        let frame = CGRect(
            x: region.minX * size.width,
            y: region.minY * size.height,
            width: max(8, region.width * size.width),
            height: max(8, region.height * size.height)
        )
        RoundedRectangle(cornerRadius: 2)
            .stroke(Theme.mint.opacity(0.85), lineWidth: 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Theme.mint.opacity(0.06)))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

/// Damage boxes with type labels. Hail hits stay unlabeled (too dense);
/// other types get a short caption on the box.
struct LiveDamageLabeledOverlay: View {
    let markers: [DamageMarker]
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                let n = marker.overlayRect
                let box = CGRect(
                    x: n.minX * size.width,
                    y: n.minY * size.height,
                    width: max(10, n.width * size.width),
                    height: max(10, n.height * size.height)
                )
                let showLabel = marker.type != .hailHits && box.width >= 28
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(marker.type.color.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(marker.type.color, lineWidth: 1.6)
                        )
                    if showLabel {
                        Text(marker.type.display)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(marker.type.color, in: .rect(cornerRadius: 2))
                            .offset(x: 1, y: -11)
                    }
                }
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .detectionBoxAppear(index: index)
            }
        }
    }
}

// MARK: - Square capture result

/// Still-photo readout after capturing a 10×10: shingle count, damage by type,
/// and overlays on the actual photo.
struct LiveARSquareResultSheet: View {
    let photo: CapturedPhoto
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsRow
                    photoPreview
                    if !grouped.isEmpty {
                        damageList
                    }
                    Text("Live marks what the camera can see. This still is the full square count.")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("10×10 Square")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.heavy)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var grouped: [(type: DamageMarkerType, items: [DamageMarker])] {
        photo.markersByType
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(icon: "square.dashed", tint: Theme.ember,
                     label: "SQUARE", value: photo.squareBox != nil ? "Found" : "Framed")
            statCard(icon: "square.grid.3x3.topleft.filled", tint: Theme.mint,
                     label: "SHINGLES", value: "\(photo.estimatedShingleCount)")
            statCard(icon: "scope", tint: Theme.sky,
                     label: "DAMAGE", value: "\(photo.damageMarkers.count)")
        }
    }

    private func statCard(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var photoPreview: some View {
        Color(.secondarySystemBackground)
            .frame(height: 320)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        if let square = photo.squareBox {
                            LiveSquareOverlay(region: square, locked: true, size: geo.size)
                        }
                        ForEach(Array(photo.shingleBoxes.enumerated()), id: \.offset) { _, rect in
                            LiveShingleOverlay(region: rect, size: geo.size)
                        }
                        LiveDamageLabeledOverlay(markers: photo.damageMarkers, size: geo.size)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 16))
    }

    private var damageList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Damage by type")
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                .foregroundStyle(Theme.ink)
            ForEach(grouped, id: \.type) { group in
                HStack {
                    Circle()
                        .fill(group.type.color)
                        .frame(width: 8, height: 8)
                    Text(group.type.display)
                        .font(.system(size: Theme.TypeRamp.caption, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(group.items.count)")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }
}
