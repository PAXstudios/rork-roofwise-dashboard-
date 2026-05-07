import SwiftUI

/// Horizontal strip of estimates the user has saved from the Cost Estimator.
/// Tapping a card re-opens the EstimatorWizard at Step 4 with the snapshot.
struct SavedEstimatesSection: View {
    @State private var store = EstimatesStore.shared
    @State private var openSaved: SavedEstimate? = nil

    var body: some View {
        if store.estimates.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved Estimates")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(store.estimates.count) saved · tap to re-open")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.estimates) { est in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                openSaved = est
                            } label: {
                                card(est)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(id: est.id)
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                } label: {
                                    Label("Delete estimate", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .fullScreenCover(item: $openSaved) { saved in
                CostEstimatorWizard(prefilledSaved: saved)
            }
        }
    }

    private func card(_ est: SavedEstimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(Theme.sky)
                Text(est.address.isEmpty ? "Untitled" : est.address)
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(est.rangeLabel)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(est.material.displayName)
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.emberSoft, in: .capsule)
                Text(String(format: "%.1f sq", est.totalSquares))
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.amberSoft, in: .capsule)
            }
            Text(est.savedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(width: 200, height: 140, alignment: .topLeading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}
