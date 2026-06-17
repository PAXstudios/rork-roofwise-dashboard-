import SwiftUI
import PhotosUI

/// Bottom sheet that lists every photo taken on a single slope, each tappable
/// to open the full damage-overlay viewer. Used from the inspection report and
/// claim packet so the user can drill from "Front Slope" down to the actual
/// photos with AI markers, shingle type, and shingle count.
struct SlopePhotosSheet: View {
    let slope: SlopeType
    let photos: [CapturedPhoto]
    var onSelect: (CapturedPhoto) -> Void
    var onClose: () -> Void
    /// When provided, an "Add Photos & Analyze" CTA appears at the bottom.
    /// Imported photos are run through Gemini Vision, then handed back so the
    /// caller can persist the analyzed `CapturedPhoto`s.
    var onAddPhotos: (([CapturedPhoto]) -> Void)? = nil

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false

    private var totalMarkers: Int {
        photos.reduce(0) { $0 + $1.damageMarkers.count }
    }

    private var totalShingles: Int {
        photos.reduce(0) { $0 + $1.estimatedShingleCount }
    }

    private var dominantShingleType: String? {
        let names = photos.compactMap { $0.shingleType }
        guard !names.isEmpty else { return nil }
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    if photos.isEmpty {
                        emptyPhotosHint
                    } else {
                        photoGrid
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) { addPhotosBar }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                importPhotos(newItems)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(slope.rawValue)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(totalMarkers) AI marker\(totalMarkers == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var emptyPhotosHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text("No photos on this slope yet")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Add photos below and they'll be analyzed for hail, wind, and wear damage automatically.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    @ViewBuilder
    private var addPhotosBar: some View {
        if onAddPhotos != nil {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                PhotosPicker(selection: $pickerItems,
                             maxSelectionCount: 10,
                             matching: .images,
                             photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text("Analyzing\u{2026}")
                                .font(.system(size: 16, weight: .heavy))
                        } else {
                            Image(systemName: "plus.viewfinder")
                                .font(.system(size: 17, weight: .heavy))
                            Text("Add Photos & Analyze")
                                .font(.system(size: 16, weight: .heavy))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                    .shadow(color: Theme.ink.opacity(0.22), radius: 12, y: 4)
                }
                .disabled(isImporting)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Theme.canvas)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard let onAddPhotos else { pickerItems = []; return }
        isImporting = true
        let slope = slope
        Task { @MainActor in
            var analyzed: [CapturedPhoto] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { continue }
                var photo = CapturedPhoto(image: img, slope: slope,
                                          pitchDegrees: 0, elevationFeet: 0,
                                          captureMode: .square, squaresCovered: 1)
                let result = await GeminiAnalysisService.analyzeFull(
                    image: img, slope: slope, mode: .square, squaresCovered: 1)
                photo.findings = result.findings
                photo.damageMarkers = result.markers
                photo.analyzed = !result.failed
                analyzed.append(photo)
            }
            pickerItems = []
            isImporting = false
            guard !analyzed.isEmpty else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onAddPhotos(analyzed)
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.emberSoft)
                    Image(systemName: slope.icon)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slope.shortName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Tap any photo to inspect AI damage map")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                statTile(icon: "camera.fill", tint: Theme.ember,
                         value: "\(photos.count)", label: "Photos")
                statTile(icon: "scope", tint: Theme.crimson,
                         value: "\(totalMarkers)", label: "AI Markers")
                statTile(icon: "square.grid.3x3.fill", tint: Theme.amber,
                         value: "\(totalShingles)", label: "Shingles")
            }

            if let type = dominantShingleType {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.sky)
                    Text("Shingle Type: \(type)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.skySoft.opacity(0.6), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sky.opacity(0.2), lineWidth: 0.6))
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func statTile(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvas, in: .rect(cornerRadius: 12))
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(photos) { photo in
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    onSelect(photo)
                } label: {
                    photoCard(photo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func photoCard(_ photo: CapturedPhoto) -> some View {
        let markerCount = photo.damageMarkers.count
        let worst = photo.worstSeverity
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(.secondarySystemBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(uiImage: photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .bottomLeading) {
                        // Inline marker dots so user sees damage even before opening
                        GeometryReader { geo in
                            ForEach(photo.damageMarkers) { marker in
                                Circle()
                                    .fill(marker.type.color.opacity(0.9))
                                    .overlay(Circle().stroke(.white, lineWidth: 1))
                                    .frame(width: 10, height: 10)
                                    .position(x: marker.x * geo.size.width,
                                              y: marker.y * geo.size.height)
                            }
                        }
                        .allowsHitTesting(false)
                    }

                HStack(spacing: 4) {
                    if markerCount > 0 {
                        Label("\(markerCount)", systemImage: "scope")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(worst == .none ? Theme.ember : worst.color, in: .capsule)
                    } else if photo.analyzed {
                        Label("Clean", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.mint, in: .capsule)
                    } else {
                        Label("Pending", systemImage: "clock")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.amber, in: .capsule)
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: photo.captureMode.icon)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                    Text(photo.captureMode.shortLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("~\(photo.estimatedShingleCount) shingle\(photo.estimatedShingleCount == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                }
                if let type = photo.shingleType {
                    Text(type)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                } else {
                    Text("Type pending AI")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
                if let top = photo.topDetectedFindings.first {
                    HStack(spacing: 4) {
                        Circle().fill(top.severity.color).frame(width: 5, height: 5)
                        Text(top.display)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
        }
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }
}
