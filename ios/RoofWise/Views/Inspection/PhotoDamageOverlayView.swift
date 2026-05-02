import SwiftUI

/// Full-screen photo viewer that overlays AI-detected damage markers
/// (hail strikes, cracks, missing shingles, etc.) on top of a captured roof photo.
/// Markers are positioned with normalized 0-1 coordinates against the rendered
/// image frame so they stay anchored as the image scales.
struct PhotoDamageOverlayView: View {
    let photo: CapturedPhoto
    var onClose: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var selectedMarker: DamageMarker? = nil
    @State private var showLegend: Bool = true
    @State private var showAllMarkers: Bool = true
    @State private var pulse: Bool = false

    private var grouped: [(type: DamageMarkerType, items: [DamageMarker])] {
        let dict = Dictionary(grouping: photo.damageMarkers, by: \.type)
        return DamageMarkerType.allCases.compactMap { type in
            guard let items = dict[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    private var totalMarkers: Int { photo.damageMarkers.count }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    if showAllMarkers {
                        markersLayer(in: imageRect(for: photo.image, container: geo.size))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if showLegend {
                    legendCard
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .sheet(item: $selectedMarker) { marker in
            markerDetail(marker)
                .presentationDetents([.fraction(0.32), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Damage Map")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                Text("\(photo.slope.rawValue) · \(totalMarkers) marker\(totalMarkers == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showAllMarkers.toggle()
                }
            } label: {
                Image(systemName: showAllMarkers ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showLegend.toggle()
                }
            } label: {
                Image(systemName: showLegend ? "list.bullet.below.rectangle" : "list.bullet")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Markers

    private func markersLayer(in rect: CGRect) -> some View {
        ZStack {
            ForEach(photo.damageMarkers) { marker in
                MarkerPin(marker: marker,
                          pulsing: pulse,
                          isSelected: selectedMarker?.id == marker.id) {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    selectedMarker = marker
                }
                .position(x: rect.minX + marker.x * rect.width,
                          y: rect.minY + marker.y * rect.height)
            }
        }
        .allowsHitTesting(true)
    }

    private func imageRect(for image: UIImage, container: CGSize) -> CGRect {
        let imgRatio = image.size.width / max(image.size.height, 1)
        let conRatio = container.width / max(container.height, 1)
        var w: CGFloat = container.width
        var h: CGFloat = container.height
        if imgRatio > conRatio {
            w = container.width
            h = container.width / imgRatio
        } else {
            h = container.height
            w = container.height * imgRatio
        }
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    // MARK: - Legend

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.amber)
                Text("DAMAGE DETECTED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(totalMarkers)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.amber.opacity(0.25), in: .capsule)
            }

            if grouped.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.mint)
                    Text("No damage points detected by AI")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                ForEach(grouped, id: \.type) { entry in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(entry.type.color.opacity(0.25))
                            Image(systemName: entry.type.icon)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(entry.type.color)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(entry.items.count) \(entry.type.pluralDisplay)")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(severitySummary(entry.items))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Text("\(entry.items.count)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(entry.type.color)
                            .frame(minWidth: 22)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 0.6))
        .environment(\.colorScheme, .dark)
    }

    private func severitySummary(_ markers: [DamageMarker]) -> String {
        let severe = markers.filter { $0.severity == .severe }.count
        let moderate = markers.filter { $0.severity == .moderate }.count
        let minor = markers.filter { $0.severity == .minor }.count
        var parts: [String] = []
        if severe > 0 { parts.append("\(severe) severe") }
        if moderate > 0 { parts.append("\(moderate) moderate") }
        if minor > 0 { parts.append("\(minor) minor") }
        return parts.isEmpty ? "Detected" : parts.joined(separator: " · ")
    }

    // MARK: - Marker Detail Sheet

    private func markerDetail(_ marker: DamageMarker) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(marker.type.color.opacity(0.18))
                    Image(systemName: marker.type.icon)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(marker.type.color)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.type.display)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(marker.severity.rawValue.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(marker.severity.color, in: .capsule)
                }
                Spacer()
            }
            if !marker.note.isEmpty {
                Text(marker.note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
            }
            HStack(spacing: 10) {
                detailStat(label: "X", value: String(format: "%.0f%%", marker.x * 100))
                detailStat(label: "Y", value: String(format: "%.0f%%", marker.y * 100))
                detailStat(label: "Size", value: String(format: "%.1f%%", marker.radius * 100))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

// MARK: - Marker Pin

private struct MarkerPin: View {
    let marker: DamageMarker
    let pulsing: Bool
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        let baseSize: CGFloat = max(22, min(72, marker.radius * 320))
        Button(action: onTap) {
            ZStack {
                Circle()
                    .stroke(marker.type.color.opacity(pulsing ? 0.0 : 0.55),
                            lineWidth: 1.2)
                    .frame(width: baseSize * 1.6, height: baseSize * 1.6)
                    .scaleEffect(pulsing ? 1.15 : 0.85)

                Circle()
                    .stroke(marker.type.color, lineWidth: isSelected ? 3 : 2)
                    .background(Circle().fill(marker.type.color.opacity(0.12)))
                    .frame(width: baseSize, height: baseSize)

                Image(systemName: marker.type.icon)
                    .font(.system(size: max(9, baseSize * 0.35), weight: .heavy))
                    .foregroundStyle(marker.type.color)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
