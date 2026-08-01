import SwiftUI

struct AIInsightsCard: View {
    @Environment(CustomerStore.self) private var store
    @State private var queue = TrainingQueueStore.shared

    private var items: [AIReviewItem] {
        HomeLiveData.aiReviewItems(from: queue)
    }

    private var pendingCount: Int { queue.pendingCount }

    private var insightText: Text {
        let stormTagged = store.customers.filter(\.stormTagged).count
        if pendingCount > 0 {
            return Text("\(pendingCount) detection\(pendingCount == 1 ? "" : "s") need a forensic review. ")
                .foregroundStyle(Theme.ink)
            + Text("Open Train to clear the queue.").foregroundStyle(Theme.ember).underline()
        }
        if stormTagged > 0 {
            return Text("\(stormTagged) lead\(stormTagged == 1 ? "" : "s") sit in storm-tagged zones. ")
                .foregroundStyle(Theme.ink)
            + Text("Prioritize those doors.").foregroundStyle(Theme.ember)
        }
        return Text("Capture and analyze inspection photos — low-confidence hits land here automatically.")
            .foregroundStyle(Theme.ink)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.ember, Theme.amber],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RoofWise · Training Queue")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(pendingCount == 0
                             ? "Queue clear — no reviews waiting"
                             : "\(pendingCount) inspection\(pendingCount == 1 ? "" : "s") need a forensic review")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                Spacer()
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.ember, in: .capsule)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 28, height: 28)
                    .background(Theme.emberSoft, in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Insight")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.ember)
                    insightText
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(12)
            .background(Theme.emberSoft.opacity(0.6), in: .rect(cornerRadius: 14))

            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: queue.pendingCount == 0 && store.customers.isEmpty ? "camera.viewfinder" : "checkmark.seal")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(store.customers.isEmpty ? Theme.inkFaint : Theme.mint)
                    Text(store.customers.isEmpty
                         ? "No jobs yet — analyze inspection photos and low-confidence hits land here."
                         : "No low-confidence detections right now.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(items) { item in
                    AIReviewRow(item: item)
                }
            }
        }
        .cardStyle(padding: 18, radius: 22)
        .padding(.horizontal, 20)
    }
}

private struct AIReviewRow: View {
    let item: AIReviewItem

    var body: some View {
        HStack(spacing: 12) {
            Color(.secondarySystemBackground)
                .frame(width: 56, height: 56)
                .overlay {
                    if let url = URL(string: item.imageURL), !item.imageURL.isEmpty,
                       url.isFileURL, let ui = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: item.damageType.lowercased().contains("wind") ? "wind" : "circle.hexagongrid.fill")
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.damageType)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(item.address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(item.aiTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.canvas, in: .capsule)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(item.confidence)%")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(confidenceColor)
                Text("confidence")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.canvas).frame(width: 56, height: 4)
                    Capsule().fill(confidenceColor)
                        .frame(width: CGFloat(item.confidence) / 100 * 56, height: 4)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var confidenceColor: Color {
        switch item.confidence {
        case 75...: return Theme.mint
        case 60..<75: return Theme.amber
        default: return Theme.crimson
        }
    }
}
