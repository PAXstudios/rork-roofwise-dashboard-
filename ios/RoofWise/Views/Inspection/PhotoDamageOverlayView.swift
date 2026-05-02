import SwiftUI

/// Full-screen photo viewer that overlays AI-detected damage markers
/// (hail strikes, cracks, missing shingles, etc.) on top of a captured roof photo.
/// Markers are positioned with normalized 0-1 coordinates against the rendered
/// image frame so they stay anchored as the image scales.
struct PhotoDamageOverlayView: View {
    let photo: CapturedPhoto
    var onClose: () -> Void
    var onDelete: (() -> Void)? = nil
    /// Async retry of AI analysis for this photo. If provided and the photo's
    /// previous analysis failed (`analyzed == false`), a "Retry AI Analysis"
    /// button is shown.
    var onRetry: (() async -> Void)? = nil

    @State private var selectedMarker: DamageMarker? = nil
    @State private var showLegend: Bool = true
    @State private var showAllMarkers: Bool = true
    @State private var pulse: Bool = false
    @State private var isRetrying: Bool = false
    @State private var showInfo: Bool = false

    private var grouped: [(type: DamageMarkerType, items: [DamageMarker])] {
        let dict = Dictionary(grouping: photo.damageMarkers, by: \.type)
        return DamageMarkerType.allCases.compactMap { type in
            guard let items = dict[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    private var totalMarkers: Int { photo.damageMarkers.count }

    /// Compact comma-joined summary like "12 hail strikes, 3 wind creases, 1 crack"
    /// computed by grouping `photo.damageMarkers` by type. Empty when no markers.
    private var compactSummary: String {
        grouped.map { "\($0.items.count) \($0.type.pluralDisplay)" }
            .joined(separator: ", ")
    }

    private var analysisFailed: Bool {
        !photo.analyzed || photo.findings.contains { $0.label == "ai_unavailable" }
    }

    /// True when the photo has never been analyzed (fresh capture) versus
    /// a prior attempt that explicitly failed. Drives the banner copy/CTA.
    private var notYetAnalyzed: Bool {
        !photo.analyzed
            && photo.damageMarkers.isEmpty
            && !photo.findings.contains { $0.label == "ai_unavailable" }
    }

    private var failureMessage: String? {
        photo.findings.first { $0.label == "ai_unavailable" }?.value
    }

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
                if analysisFailed && onRetry != nil {
                    retryBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, showLegend ? 8 : 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showLegend {
                    legendCard
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            photoInfoSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

            Button {
                let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                showInfo = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
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

    // MARK: - Retry Banner

    private var retryBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: notYetAnalyzed ? "sparkles" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                Text(notYetAnalyzed ? "AI ANALYSIS PENDING" : "AI ANALYSIS FAILED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                Spacer()
            }
            if notYetAnalyzed {
                Text("Run Gemini Vision on this photo to detect hail strikes, wind damage, granule loss, and overlay markers directly on the image.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
            } else if let msg = failureMessage, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(2)
            } else {
                Text("This photo couldn’t be analyzed. Tap retry to run Gemini Vision again.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Button {
                guard let onRetry, !isRetrying else { return }
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                isRetrying = true
                Task {
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isRetrying {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: notYetAnalyzed ? "sparkles" : "arrow.clockwise")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    Text(isRetrying
                         ? (notYetAnalyzed ? "Analyzing with Gemini…" : "Re-analyzing…")
                         : (notYetAnalyzed ? "Analyze with AI" : "Retry AI Analysis"))
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Theme.ember, in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6))
                .shadow(color: Theme.ember.opacity(0.45), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.ember.opacity(0.4), lineWidth: 0.8))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Legend

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Photo metadata strip — slope, shingle type, # shingles
            HStack(spacing: 8) {
                metaChip(icon: photo.slope.icon, tint: Theme.ember,
                         label: photo.slope.shortName)
                if let type = photo.shingleType {
                    metaChip(icon: "square.stack.3d.down.right.fill",
                             tint: Theme.sky, label: type)
                }
                metaChip(icon: "square.grid.3x3.fill",
                         tint: Theme.amber,
                         label: "~\(photo.estimatedShingleCount) shingle\(photo.estimatedShingleCount == 1 ? "" : "s")")
                Spacer(minLength: 0)
                Button {
                    showInfo = true
                } label: {
                    HStack(spacing: 4) {
                        Text("More")
                            .font(.system(size: 10, weight: .heavy))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
            }

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

            if !compactSummary.isEmpty {
                Text(compactSummary)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func metaChip(icon: String, tint: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.white.opacity(0.12), in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.6))
    }

    // MARK: - Photo info sheet (shingle type, count, captured details, findings)

    private var photoInfoSheet: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Header card
                    HStack(spacing: 12) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(photo.slope.rawValue)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                            HStack(spacing: 6) {
                                Image(systemName: photo.captureMode.icon)
                                    .font(.system(size: 9, weight: .heavy))
                                Text(photo.captureMode.rawValue)
                                    .font(.system(size: 10, weight: .heavy))
                            }
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.emberSoft, in: .capsule)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        infoStat(icon: "square.stack.3d.down.right.fill",
                                 tint: Theme.sky,
                                 label: "Shingle Type",
                                 value: photo.shingleType ?? "Pending AI")
                        infoStat(icon: "square.grid.3x3.fill",
                                 tint: Theme.amber,
                                 label: "Shingles in Frame",
                                 value: "~\(photo.estimatedShingleCount)")
                        infoStat(icon: "angle",
                                 tint: Theme.ember,
                                 label: "Pitch",
                                 value: String(format: "%.0f°", photo.pitchDegrees))
                        infoStat(icon: "mountain.2.fill",
                                 tint: Theme.mint,
                                 label: "Elevation",
                                 value: "\(Int(photo.elevationFeet)) ft")
                        infoStat(icon: "scope",
                                 tint: Theme.crimson,
                                 label: "AI Markers",
                                 value: "\(photo.damageMarkers.count)")
                        infoStat(icon: "square.dashed.inset.filled",
                                 tint: Theme.ember,
                                 label: "Test Squares",
                                 value: "\(photo.squaresCovered)")
                    }

                    if let typeNote = photo.shingleTypeNote, !typeNote.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI EVIDENCE")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkFaint)
                            Text(typeNote)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkSoft)
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
                    }

                    // Findings list
                    if !photo.topDetectedFindings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DETECTED ON THIS PHOTO")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkFaint)
                            VStack(spacing: 0) {
                                ForEach(Array(photo.topDetectedFindings.enumerated()), id: \.element.id) { idx, f in
                                    findingRow(f)
                                    if idx < photo.topDetectedFindings.count - 1 {
                                        Rectangle().fill(Theme.hairline).frame(height: 0.6)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
                    }

                    if onDelete != nil {
                        Button {
                            onDelete?()
                        } label: {
                            Label("Delete Photo", systemImage: "trash.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.crimson)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 1.0, green: 0.94, blue: 0.94), in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.crimson.opacity(0.3), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Photo Details")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showInfo = false }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private func infoStat(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func findingRow(_ f: InspectionFinding) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(f.tint.opacity(0.14))
                Image(systemName: f.icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(f.tint)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.display)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(f.value)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(f.severity.rawValue.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(f.severity.color, in: .capsule)
        }
        .padding(.vertical, 8)
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
                detailStat(label: "Type", value: marker.type.display)
                detailStat(label: "Severity", value: marker.severity.rawValue)
                detailStat(label: "Confidence",
                           value: marker.confidence > 0 ? "\(marker.confidence)%" : "—")
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
