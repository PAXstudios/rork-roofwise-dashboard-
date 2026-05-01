import SwiftUI

struct RecentJobsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Jobs")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Inspection captures from the field")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button {} label: {
                    Text("See All")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MockData.recentJobs) { job in
                        RecentJobCard(job: job)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct RecentJobCard: View {
    let job: RecentJob

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image anchor
            Color(.secondarySystemBackground)
                .frame(width: 240, height: 240)
                .overlay {
                    AsyncImage(url: URL(string: job.imageURL)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            ZStack {
                                LinearGradient(colors: [Theme.ink.opacity(0.7), Theme.inkSoft],
                                               startPoint: .top, endPoint: .bottom)
                                Image(systemName: "house.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    // gradient scrim
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(.rect(cornerRadius: 20))
                    .allowsHitTesting(false)
                }

            // Status pill
            HStack {
                Spacer()
                StatusPill(status: job.status)
                    .padding(12)
            }
            .frame(width: 240, alignment: .topTrailing)
            .frame(maxHeight: .infinity, alignment: .top)

            // Address overlay
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(job.address)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(job.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(job.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(14)
        }
        .frame(width: 240, height: 240)
        .shadow(color: Theme.ink.opacity(0.12), radius: 14, x: 0, y: 6)
    }
}

private struct StatusPill: View {
    let status: JobStatus
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 5, height: 5)
            Text(status.rawValue)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(status.color, in: .capsule)
        .shadow(color: status.color.opacity(0.4), radius: 8, y: 3)
    }
}
