import SwiftUI

struct AIInsightsCard: View {
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
                        Text("AI Insights · Training Queue")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("3 inspections need a forensic review")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                Spacer()
                Text("3")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.ember, in: .capsule)
            }

            // AI hint
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
                    (Text("3 recent leads sit within 2 mi of the Apr 18 hail core. ")
                        .foregroundStyle(Theme.ink)
                     + Text("Launch storm canvas?").foregroundStyle(Theme.ember).underline())
                    .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(12)
            .background(Theme.emberSoft.opacity(0.6), in: .rect(cornerRadius: 14))

            ForEach(MockData.aiReview) { item in
                AIReviewRow(item: item)
            }
        }
        .cardStyle(padding: 18, radius: 24)
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
                    AsyncImage(url: URL(string: item.imageURL)) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "house")
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.damageType)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(item.address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
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
