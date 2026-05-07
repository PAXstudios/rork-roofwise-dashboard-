import SwiftUI

struct KPIStrip: View {
    var onQuickInspection: () -> Void = {}
    @State private var showNewJob = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Overview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {} label: {
                    HStack(spacing: 4) {
                        Text("View Report")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ember)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickActionCard(title: "Quick Inspection",
                                    subtitle: "LiDAR + AI capture",
                                    icon: "camera.viewfinder",
                                    tint: Theme.ember,
                                    action: onQuickInspection)
                    QuickActionCard(title: "New Job",
                                    subtitle: "Create a project",
                                    icon: "plus.rectangle.on.folder.fill",
                                    tint: Theme.sky,
                                    action: { showNewJob = true })
                    ForEach(MockData.kpis) { metric in
                        KPICard(metric: metric)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: $showNewJob) {
            NewJobWizard()
        }
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
