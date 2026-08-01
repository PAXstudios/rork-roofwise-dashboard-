import SwiftUI

struct KPIStrip: View {
    @Environment(CustomerStore.self) private var store
    @State private var showNewJob = false
    @State private var showCostEstimator = false
    @State private var alertStore = StormAlertStore.shared
    @State private var estimatesStore = EstimatesStore.shared
    @State private var proposalStore = ProposalStore.shared

    private var metrics: [KPIMetric] {
        HomeLiveData.kpis(
            customers: store.customers,
            alerts: alertStore.alerts,
            estimates: estimatesStore.estimates,
            proposals: proposalStore.proposals
        )
    }

    private var isEmpty: Bool {
        HomeLiveData.kpisAreEmpty(
            customers: store.customers,
            alerts: alertStore.alerts,
            estimates: estimatesStore.estimates,
            proposals: proposalStore.proposals
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Overview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickActionCard(title: "New Lead",
                                    subtitle: "Capture a prospect",
                                    icon: "person.crop.circle.badge.plus",
                                    tint: Theme.ember,
                                    action: { showNewJob = true })
                    QuickActionCard(title: "Cost Estimator",
                                    subtitle: "Address → squares → $",
                                    icon: "dollarsign.circle.fill",
                                    tint: Theme.mint,
                                    action: { showCostEstimator = true })
                    if isEmpty {
                        KPIEmptyInvite(onStart: { showNewJob = true })
                    } else {
                        ForEach(metrics) { metric in
                            KPICard(metric: metric)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: $showNewJob) {
            NewJobWizard()
        }
        .fullScreenCover(isPresented: $showCostEstimator) {
            CostEstimatorWizard()
        }
    }
}

/// Genuine empty state — not zeros rendered as data.
private struct KPIEmptyInvite: View {
    var onStart: () -> Void = {}

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 40, height: 40)
                    .background(Theme.emberSoft, in: .rect(cornerRadius: 12))
                Text("No jobs yet")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Start your first inspection to fill Overview with live numbers.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start inspection")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.ember, in: .capsule)
            }
            .frame(width: 200, height: 168, alignment: .topLeading)
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }

                HStack(spacing: 6) {
                    Text("Tap to start")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: .capsule)
            }
            .frame(width: 168, height: 168, alignment: .topLeading)
            .padding(16)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.18), lineWidth: 0.6)
            )
            .shadow(color: tint.opacity(0.28), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct KPICard: View {
    let metric: KPIMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(metric.tint.opacity(0.14))
                    Image(systemName: metric.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(metric.tint)
                }
                .frame(width: 32, height: 32)

                Spacer()

                Text(metric.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            Text(metric.value)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 4) {
                Image(systemName: metric.deltaPositive ? "arrow.up.right" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(metric.delta)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(metric.deltaPositive ? Theme.mint : Theme.crimson)
        }
        .frame(width: 168, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}
