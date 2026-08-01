import SwiftUI
import SafariServices

/// In-app Safari sheet for Privacy / Terms. App Review prefers this over
/// handing the user off to Safari for legal docs.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Theme.ember)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Tiny helper so rows/buttons can present a legal URL as a sheet.
struct LegalSafariLink: View {
    let title: String
    let url: URL
    var icon: String? = nil
    var style: Style = .row

    enum Style { case row, inline }

    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            switch style {
            case .row:
                HStack(spacing: 14) {
                    if let icon {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.ink.opacity(0.06))
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(width: 40, height: 40)
                    }
                    Text(title)
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(14)
                .frame(minHeight: 56)
                .contentShape(.rect)
            case .inline:
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .underline()
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
}
