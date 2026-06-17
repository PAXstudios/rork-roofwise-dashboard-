import SwiftUI

// MARK: - Safety rating color mapping

private extension SafetyRating {
    var tint: Color {
        switch self {
        case .safe: return Theme.mint
        case .useCaution: return Theme.amber
        case .unsafe: return Theme.crimson
        }
    }

    var softTint: Color {
        switch self {
        case .safe: return Theme.mintSoft
        case .useCaution: return Theme.amberSoft
        case .unsafe: return Theme.crimson.opacity(0.14)
        }
    }
}

// MARK: - Pill (header surface)

/// Compact tappable pill showing the RoofWise Safety Engine roof-walk rating.
struct SafetyRatingPill: View {
    let assessment: SafetyAssessment?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.inkSoft)
                    Text("Safety")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .lineLimit(1)
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    let rating = assessment?.rating ?? .useCaution
                    Image(systemName: rating.symbolName)
                        .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                    Text(rating.shortLabel)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isLoading ? Theme.inkSoft : (assessment?.rating.tint ?? Theme.inkSoft))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isLoading ? Theme.card : (assessment?.rating.softTint ?? Theme.card),
                        in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Detail sheet

struct SafetyDetailSheet: View {
    let assessment: SafetyAssessment?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rating = assessment?.rating ?? .useCaution
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard(rating)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONDITIONS")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(Theme.inkSoft)
                        ForEach(Array((assessment?.reasons ?? []).enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(rating.tint)
                                    .padding(.top, 7)
                                Text(reason)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 18, radius: 18)

                    if let computedAt = assessment?.computedAt {
                        Text("Updated \(computedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Roof-Walk Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onRefresh) {
                    HStack(spacing: 8) {
                        if isRefreshing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .bold))
                        }
                        Text(isRefreshing ? "Refreshing…" : "Refresh")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func headerCard(_ rating: SafetyRating) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(rating.tint.opacity(0.16))
                    Image(systemName: rating.symbolName)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(rating.tint)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("RoofWise Safety Engine")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Text(rating.label)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
            Text(rating.recommendation)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18, radius: 20)
    }
}
