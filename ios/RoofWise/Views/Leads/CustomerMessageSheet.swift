import SwiftUI
import UIKit
import MessageUI

/// In-app customer communication. Texts or emails the customer directly
/// (pre-addressed to their phone / email on file) with an optional HAAG
/// report PDF attachment. Falls back to the system share sheet on devices
/// (or the simulator) that can't send mail/messages natively.
struct CustomerMessageSheet: View {
    @Environment(\.dismiss) private var dismiss

    let customer: Customer

    @State private var messageText: String = ""
    @State private var attachReport: Bool = true
    @State private var showMessages = false
    @State private var showMail = false
    @State private var showShareFallback = false
    @State private var reportURL: URL? = nil
    @State private var isPreparing = false
    @State private var toast: String? = nil

    private var hasPhone: Bool { !customer.phone.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasEmail: Bool { !customer.email.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The HAAG inspection linked to this customer, if any.
    private var linkedInspection: Inspection? {
        guard let rid = customer.linkedReportId else { return nil }
        return InspectionStore.shared.inspection(with: rid)
    }

    private var canAttachReport: Bool { linkedInspection != nil }

    private var firstName: String {
        customer.ownerName.split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    recipientCard
                    templatesCard
                    messageCard
                    if canAttachReport {
                        attachmentCard
                    }
                    sendButtons
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Message Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
            .overlay(alignment: .top) { toastView }
            .sheet(isPresented: $showMessages) {
                CustomerMessageComposer(
                    recipients: hasPhone ? [customer.phone] : [],
                    body: messageText,
                    attachmentURL: attachReport ? reportURL : nil
                )
            }
            .sheet(isPresented: $showMail) {
                CustomerMailComposer(
                    recipients: hasEmail ? [customer.email] : [],
                    subject: emailSubject,
                    body: messageText,
                    attachmentURL: attachReport ? reportURL : nil
                )
            }
            .sheet(isPresented: $showShareFallback) {
                if let url = reportURL {
                    ProposalShareSheet(items: [messageText, url])
                } else {
                    ProposalShareSheet(items: [messageText])
                }
            }
        }
        .onAppear {
            if messageText.isEmpty { messageText = defaultMessage }
        }
    }

    // MARK: Recipient

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(customer.stage.color.opacity(0.16))
                    Text(customer.initials)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(customer.stage.color)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.ownerName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(customer.address)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                channelPill(icon: "phone.fill", value: hasPhone ? customer.phone : "No phone on file",
                            active: hasPhone)
                channelPill(icon: "envelope.fill", value: hasEmail ? customer.email : "No email on file",
                            active: hasEmail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func channelPill(icon: String, value: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
            Text(value)
                .font(.system(size: 11, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(active ? Theme.ink : Theme.inkFaint)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background((active ? Theme.canvas : Theme.canvas.opacity(0.5)), in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Templates

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK MESSAGES")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            FlowChips(items: quickMessages.map(\.label)) { idx in
                let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                messageText = quickMessages[idx].text
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var quickMessages: [(label: String, text: String)] {
        [
            ("Intro", defaultMessage),
            ("Send report", "Hi \(firstName), I've attached the full inspection report on your roof. Take a look and let me know if you have any questions — happy to walk you through it."),
            ("Schedule", "Hi \(firstName), I'd like to schedule a quick time to go over your roof inspection. What day works best for you this week?"),
            ("Follow up", "Hi \(firstName), just following up on your roof inspection. Did you get a chance to review everything? Let me know how you'd like to proceed."),
            ("Adjuster", "Hi \(firstName), once you file your claim, send me the adjuster's name and meeting date so I can be there to represent the findings with you.")
        ]
    }

    private var defaultMessage: String {
        "Hi \(firstName), this is your inspector with RoofWise. Thanks for letting me take a look at your roof — here's a summary of what we found."
    }

    // MARK: Message editor

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MESSAGE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            TextEditor(text: $messageText)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(10)
                .background(Theme.canvas, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Attachment

    private var attachmentCard: some View {
        Button {
            attachReport.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Theme.emberSoft)
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attach HAAG Report")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(attachReport ? "PDF will be attached to email · linked via text"
                                      : "Report won't be attached")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: attachReport ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(attachReport ? Theme.ember : Theme.inkFaint)
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(attachReport ? Theme.ember.opacity(0.4) : Theme.hairline,
                        lineWidth: attachReport ? 1.2 : 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: Send buttons

    private var sendButtons: some View {
        VStack(spacing: 10) {
            sendButton(icon: "message.fill",
                       title: "Send Text",
                       tint: Theme.mint,
                       enabled: hasPhone) {
                prepareThenSend { showMessages = true }
            }
            sendButton(icon: "envelope.fill",
                       title: "Send Email",
                       tint: Theme.sky,
                       enabled: hasEmail) {
                prepareThenSend { showMail = true }
            }
            Button {
                prepareThenSend { showShareFallback = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Other (AirDrop, WhatsApp…)")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }

    private func sendButton(icon: String, title: String, tint: Color,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isPreparing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(enabled ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.inkFaint),
                        in: .rect(cornerRadius: 16))
            .shadow(color: enabled ? tint.opacity(0.3) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isPreparing)
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.ink, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: toast)
    }

    private var emailSubject: String {
        "Your Roof Inspection Report" + (customer.address.isEmpty ? "" : " · \(customer.address)")
    }

    // MARK: Actions

    /// Generates the HAAG PDF (if needed/requested) off the main thread, then
    /// presents the chosen composer.
    private func prepareThenSend(_ present: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard attachReport, canAttachReport, reportURL == nil else {
            present()
            return
        }
        isPreparing = true
        let insp = linkedInspection
        let photos = customer.photos
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            if let insp {
                reportURL = HaagReportGenerator.write(inspection: insp, photos: photos)
            }
            isPreparing = false
            if reportURL == nil {
                showToast("Couldn't attach report — sending message only")
            }
            present()
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }
}

// MARK: - Lightweight wrapping chip layout

private struct FlowChips: View {
    let items: [String]
    let onTap: (Int) -> Void

    private struct Chip: Identifiable {
        let id: Int
        let label: String
    }

    private var chips: [Chip] {
        items.enumerated().map { Chip(id: $0.offset, label: $0.element) }
    }

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(chips) { chip in
                Button {
                    onTap(chip.id)
                } label: {
                    Text(chip.label)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.emberSoft, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - SMS bridge (recipients + optional attachment)

struct CustomerMessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let attachmentURL: URL?

    func makeUIViewController(context: Context) -> UIViewController {
        if MFMessageComposeViewController.canSendText() {
            let vc = MFMessageComposeViewController()
            vc.recipients = recipients
            vc.body = body
            if let url = attachmentURL,
               MFMessageComposeViewController.canSendAttachments(),
               let data = try? Data(contentsOf: url) {
                vc.addAttachmentData(data, typeIdentifier: "com.adobe.pdf",
                                     filename: url.lastPathComponent)
            }
            vc.messageComposeDelegate = context.coordinator
            return vc
        }
        // Simulator / no-iMessage fallback.
        var items: [Any] = [body]
        if let url = attachmentURL { items.append(url) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
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

// MARK: - Mail bridge (recipients, subject, body, optional attachment)

struct CustomerMailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL?

    func makeUIViewController(context: Context) -> UIViewController {
        if MFMailComposeViewController.canSendMail() {
            let vc = MFMailComposeViewController()
            vc.setToRecipients(recipients)
            vc.setSubject(subject)
            vc.setMessageBody(body, isHTML: false)
            if let url = attachmentURL, let data = try? Data(contentsOf: url) {
                vc.addAttachmentData(data, mimeType: "application/pdf",
                                     fileName: url.lastPathComponent)
            }
            vc.mailComposeDelegate = context.coordinator
            return vc
        }
        // Simulator / no-Mail fallback.
        var items: [Any] = [subject, body]
        if let url = attachmentURL { items.append(url) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                               didFinishWith result: MFMailComposeResult,
                                               error: Error?) {
            Task { @MainActor in controller.dismiss(animated: true) }
        }
    }
}
