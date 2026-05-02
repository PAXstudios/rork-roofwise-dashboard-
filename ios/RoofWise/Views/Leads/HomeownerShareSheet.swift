import SwiftUI

/// Bottom sheet showing a clean preview of the homeowner one-pager + share buttons.
struct HomeownerShareSheet: View {
    let customer: Customer

    @Environment(\.dismiss) private var dismiss
    @State private var nextStep: String = "File a claim with your carrier within 30 days. We'll guide you and your adjuster through every finding."
    @State private var previewImage: UIImage?
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var isRendering = true

    private var input: HomeownerReportService.Input {
        HomeownerReportService.Input(
            customer: customer,
            photos: customer.photos,
            findings: customer.damageFindings.isEmpty ? InspectionMock.findings : customer.damageFindings,
            nextStep: nextStep,
            repName: "Alex Coleman",
            repPhone: "(214) 555-0142",
            repCompany: "RoofWise Field Co."
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                handle
                title
                preview
                nextStepEditor
                shareButtons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .task { renderPreview() }
        .sheet(isPresented: $showShare) {
            if let url = pdfURL {
                ShareSheet(items: [
                    "Hi \(customer.ownerName) — here's the quick recap of your roof inspection. – RoofWise",
                    url
                ])
            }
        }
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
                preparePDFAndShare()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .heavy))
                    Text("Share PDF · Text, Email, AirDrop")
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
                quickShare(label: "Text", icon: "message.fill", tint: Theme.mint) {
                    preparePDFAndShare()
                }
                quickShare(label: "Email", icon: "envelope.fill", tint: Theme.sky) {
                    preparePDFAndShare()
                }
                quickShare(label: "Copy Link", icon: "link", tint: Theme.amber) {
                    preparePDFAndShare()
                }
            }
        }
    }

    private func quickShare(label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: .circle)
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
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

    private func preparePDFAndShare() {
        let payload = input
        Task.detached(priority: .userInitiated) {
            let url = HomeownerReportService.generate(input: payload)
            await MainActor.run {
                self.pdfURL = url
                if url != nil { self.showShare = true }
            }
        }
    }
}
