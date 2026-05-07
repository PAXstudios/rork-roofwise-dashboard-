import SwiftUI
import UIKit
import MessageUI

struct ProposalSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProposalStore.shared
    @State private var linkStore = ProposalLinkStore.shared

    let proposal: Proposal
    let onSent: (Proposal) -> Void

    @State private var showShareEmail = false
    @State private var showMessages = false
    @State private var showCopiedToast = false
    @State private var pdfURL: URL? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard

                    sendRow(icon: "envelope.fill",
                            tint: Theme.sky,
                            title: "Email",
                            subtitle: "Attach PDF and open Mail") {
                        preparePDF()
                        showShareEmail = true
                        markSent(channel: .email, to: nil)
                    }

                    sendRow(icon: "message.fill",
                            tint: Theme.mint,
                            title: "SMS",
                            subtitle: "Send link via Messages") {
                        preparePDF()
                        showMessages = true
                        markSent(channel: .sms, to: nil)
                    }

                    sendRow(icon: "link",
                            tint: Theme.amber,
                            title: "Generate Link",
                            subtitle: shareURL().absoluteString) {
                        _ = shareURL()
                        markSent(channel: .link, to: nil)
                    }

                    sendRow(icon: "doc.on.clipboard.fill",
                            tint: Theme.ember,
                            title: "Copy Link",
                            subtitle: "Send anywhere") {
                        UIPasteboard.general.string = shareURL().absoluteString
                        showCopiedToast = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        markSent(channel: .link, to: nil)
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Send Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
            .sheet(isPresented: $showShareEmail) {
                if let url = pdfURL {
                    ProposalShareSheet(items: [
                        "Your roof proposal from RoofWise",
                        "Hi \(proposal.homeownerName.isEmpty ? "there" : proposal.homeownerName), here's the proposal for \(proposal.projectAddress).",
                        url
                    ])
                }
            }
            .sheet(isPresented: $showMessages) {
                MessageComposer(body: messageBody())
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text("Link copied")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.ink, in: .capsule)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showCopiedToast = false }
                        }
                }
            }
            .animation(.spring(response: 0.3), value: showCopiedToast)
        }
    }

    // MARK: Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposal.homeownerName.isEmpty ? "Homeowner" : proposal.homeownerName)
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(proposal.projectAddress.isEmpty ? "—" : proposal.projectAddress)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 6) {
                Text("Total")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                Text(currency(proposal.total))
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func sendRow(icon: String,
                        tint: Color,
                        title: String,
                        subtitle: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .cardStyle(padding: 14, radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func preparePDF() {
        if pdfURL == nil {
            pdfURL = ProposalPDFGenerator.write(proposal)
        }
    }

    private func shareURL() -> URL {
        linkStore.url(for: proposal.id)
    }

    private func messageBody() -> String {
        "Your roof proposal from RoofWise: \(shareURL().absoluteString)"
    }

    private func markSent(channel: ProposalSentChannel, to: String?) {
        store.markSent(id: proposal.id, channel: channel, to: to)
        if let updated = store.proposals.first(where: { $0.id == proposal.id }) {
            onSent(updated)
        }
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Bridges

struct ProposalShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MessageComposer: UIViewControllerRepresentable {
    let body: String

    func makeUIViewController(context: Context) -> UIViewController {
        if MFMessageComposeViewController.canSendText() {
            let vc = MFMessageComposeViewController()
            vc.body = body
            vc.messageComposeDelegate = context.coordinator
            return vc
        }
        // Simulator fallback: present the share sheet so the build / preview
        // is functional even without a real Messages app.
        return UIActivityViewController(activityItems: [body], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                      didFinishWith result: MessageComposeResult) {
            Task { @MainActor in controller.dismiss(animated: true) }
        }
    }
}
