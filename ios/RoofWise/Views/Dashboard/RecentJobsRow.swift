import SwiftUI

struct RecentJobsRow: View {
    @Environment(CustomerStore.self) private var store
    var onOpenCustomer: (UUID) -> Void = { _ in }

    private var jobs: [RecentJob] {
        HomeLiveData.recentJobs(customers: store.customers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Jobs")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(jobs.isEmpty
                         ? "Jobs you create will land here"
                         : "Inspection captures from the field")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            if jobs.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(jobs) { job in
                            Button {
                                let id = store.resolveCustomer(for: job)
                                store.setActive(id)
                                let g = UIImpactFeedbackGenerator(style: .soft)
                                g.impactOccurred()
                                onOpenCustomer(id)
                            } label: {
                                RecentJobCard(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("No jobs yet — start your first inspection")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Create a New Lead or finish an inspection and it will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

struct RecentJobCard: View {
    let job: RecentJob

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.secondarySystemBackground)
                .frame(width: 240, height: 240)
                .overlay {
                    if let url = URL(string: job.imageURL), !job.imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                placeholder
                            }
                        }
                        .allowsHitTesting(false)
                    } else {
                        placeholder
                    }
                }
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(.rect(cornerRadius: 20))
                    .allowsHitTesting(false)
                }

            HStack {
                Spacer()
                StatusPill(status: job.status)
                    .padding(12)
            }
            .frame(width: 240, alignment: .topTrailing)
            .frame(maxHeight: .infinity, alignment: .top)

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

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink.opacity(0.7), Theme.inkSoft],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "house.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.4))
        }
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
