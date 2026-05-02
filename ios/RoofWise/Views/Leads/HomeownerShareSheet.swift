import SwiftUI

/// Bottom sheet showing a clean preview of the homeowner one-pager + share buttons.
struct HomeownerShareSheet: View {
    let customer: Customer
    var onShared: ((HomeownerShareChannel) -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("roofwise.homeowner.lastShareChannel") private var lastChannelRaw: String = HomeownerShareChannel.messages.rawValue
    @State private var nextStep: String = "File a claim with your carrier within 30 days. We'll guide you and your adjuster through every finding."
    @State private var previewImage: UIImage?
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var isRendering = true
    @State private var pendingChannel: HomeownerShareChannel = .shareSheet

    private var lastChannel: HomeownerShareChannel {
        HomeownerShareChannel(rawValue: lastChannelRaw) ?? .messages
    }

    private var input: HomeownerReportService.Input {
        HomeownerReportService.Input(
            customer: customer,
            photos: customer.photos,
            findings: customer.damageFindings,
            nextStep: nextStep,
            repName: "Alex Coleman",
            repPhone: "(214) 555-0142",
            repCompany: "RoofWise Field Co."
        )
    }

    private var contactSummary: String? {
        let pieces = [customer.phone, customer.email]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? nil : pieces.joined(separator: "  ·  ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                handle
                title
                if let summary = contactSummary {
                    contactPill(summary)
                }
                preview
                nextStepEditor
                shareButtons
                if onSkip != nil {
                    skipButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .task { renderPreview() }
        .sheet(isPresented: $showShare, onDismiss: {
            // Treat sheet dismissal as a successful share for activity logging.
            persistAndNotify(channel: pendingChannel)
        }) {
            if let url = pdfURL {
                ShareSheet(items: [
                    "Hi \(customer.ownerName) — here's the quick recap of your roof inspection. – RoofWise",
                    url
                ])
            }
        }
    }

    private func contactPill(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.mint)
            Text("Auto-filled — \(summary)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mintSoft.opacity(0.55), in: .capsule)
        .overlay(Capsule().stroke(Theme.mint.opacity(0.35), lineWidth: 0.6))
    }

    private var skipButton: some View {
        Button {
            onSkip?()
            dismiss()
        } label: {
            Text("Skip for now")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
                .underline()
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var handle: some View {
        Capsule().fill(Theme.hairline)
            .frame(width: 40, height: 4)
            .padding(.top, 6)
    }

    private var title: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                       startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 8)
                    )
                Text("Send Homeowner Recap")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Text("A clean one-page summary the homeowner can keep, forward to family, or share with their carrier.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var preview: some View {
        ZStack {
            Theme.card
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
            } else if isRendering {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.ember)
            }
        }
        .frame(height: 460)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.10), radius: 16, y: 6)
    }

    private var nextStepEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ember)
                Text("RECOMMENDED NEXT STEP")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            TextEditor(text: $nextStep)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 90)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
                .onChange(of: nextStep) { _, _ in
                    // Re-render lightly debounced
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        renderPreview()
                    }
                }
        }
    }

    private var shareButtons: some View {
        VStack(spacing: 10) {
            Button {
                preparePDFAndShare(channel: .shareSheet)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .heavy))
                    Text(primaryButtonLabel)
                        .font(.system(size: 14, weight: .heavy))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                ForEach(orderedChannels) { ch in
                    quickShare(channel: ch, isDefault: ch == lastChannel) {
                        preparePDFAndShare(channel: ch)
                    }
                }
            }
        }
    }

    private var primaryButtonLabel: String {
        "Share PDF · Default: \(lastChannel.shortLabel)"
    }

    /// Surface the user's last-used channel first so it acts as the default.
    private var orderedChannels: [HomeownerShareChannel] {
        let visible: [HomeownerShareChannel] = [.messages, .mail, .airdrop]
        if visible.contains(lastChannel) {
            return [lastChannel] + visible.filter { $0 != lastChannel }
        }
        return visible
    }

    private func quickShare(channel: HomeownerShareChannel, isDefault: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: channel.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(channel.tint)
                    .frame(width: 36, height: 36)
                    .background(channel.tint.opacity(0.14), in: .circle)
                Text(channel.shortLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(channel.tint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(channel.tint.opacity(0.14), in: .capsule)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isDefault ? channel.tint.opacity(0.55) : Theme.hairline,
                        lineWidth: isDefault ? 1.2 : 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func renderPreview() {
        isRendering = true
        let payload = input
        Task.detached(priority: .userInitiated) {
            let img = HomeownerReportService.renderPreviewImage(input: payload)
            await MainActor.run {
                self.previewImage = img
                self.isRendering = false
            }
        }
    }

    private func preparePDFAndShare(channel: HomeownerShareChannel) {
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
        pendingChannel = channel
        let payload = input
        Task.detached(priority: .userInitiated) {
            let url = HomeownerReportService.generate(input: payload)
            await MainActor.run {
                self.pdfURL = url
                if url != nil { self.showShare = true }
            }
        }
    }

    private func persistAndNotify(channel: HomeownerShareChannel) {
        lastChannelRaw = channel.rawValue
        onShared?(channel)
    }
}
