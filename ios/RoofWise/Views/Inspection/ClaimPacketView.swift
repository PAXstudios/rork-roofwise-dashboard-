import SwiftUI

struct ClaimPacketView: View {
    let packet: ClaimPacket
    let photoCount: Int
    var photos: [CapturedPhoto] = []
    var findings: [InspectionFinding] = []
    var customer: Customer? = nil
    var onClose: () -> Void
    @State private var showShareSheet: Bool = false
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                gradeHero
                summaryCard
                statsRow
                slopeBreakdown
                methodologyCard
                actions
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
        }
        .safeAreaInset(edge: .top) { topNav }
        .background(Theme.canvas)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func exportPDF() {
        isGeneratingPDF = true
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            let input = PDFReportService.Input(
                customer: customer,
                photos: photos,
                findings: findings.isEmpty ? InspectionMock.findings : findings,
                packet: packet,
                repName: "Sarah Jenkins",
                repPhone: "(214) 555-0142",
                repCompany: "RoofWise · Forensic Field Team"
            )
            if let url = PDFReportService.generate(input: input) {
                pdfURL = url
                showShareSheet = true
            }
            isGeneratingPDF = false
        }
    }

    private var topNav: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            Spacer()
            VStack(spacing: 0) {
                Text("Claim Packet")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("HAAG Standards · \(packet.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button { exportPDF() } label: {
                ZStack {
                    if isGeneratingPDF {
                        ProgressView().scaleEffect(0.6).tint(Theme.ember)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Theme.card, in: .circle)
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var gradeHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text("HAAG GRADE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.18), in: .capsule)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: packet.grade.icon)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(packet.grade.rawValue)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(packet.grade.recommendedAction)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                heroStat(value: packet.perils.isEmpty ? "—" : packet.perils.joined(separator: " + "),
                         label: "Perils")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 36)
                heroStat(value: String(format: "%.1f", packet.affectedSquares),
                         label: "Affected Squares")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 36)
                heroStat(value: "\(photoCount)",
                         label: "Documented Photos")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [packet.grade.color, packet.grade.color.opacity(0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: packet.grade.color.opacity(0.4), radius: 18, x: 0, y: 10)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Forensic Summary")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(packet.summary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(icon: "doc.text.fill", title: "Recommendation", value: packet.recommendation)
            statTile(icon: "square.stack.3d.up.fill",
                     title: "Affected Slopes",
                     value: "\(packet.slopeFindings.count)")
        }
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ember)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var slopeBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documented Findings by Slope")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
            if packet.slopeFindings.isEmpty {
                Text("No slopes captured.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(packet.slopeFindings.enumerated()), id: \.element.id) { idx, entry in
                        slopeRow(entry)
                        if idx < packet.slopeFindings.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 0.6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func slopeRow(_ entry: SlopePacketEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.emberSoft)
                Image(systemName: entry.slope.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.slope.shortName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(entry.photoCount) photo\(entry.photoCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                if entry.topFindings.isEmpty {
                    Text("No defects detected")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mint)
                } else {
                    ForEach(entry.topFindings, id: \.self) { finding in
                        HStack(spacing: 6) {
                            Circle().fill(Theme.ember).frame(width: 4, height: 4)
                            Text(finding)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "scale.3d")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.sky)
                Text("HAAG Methodology")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.sky)
            }
            Text("Hail damage is claimable when functional damage is confirmed: bruising or cracking of the mat, plus granule displacement >30% across multiple impacts. Wind damage is claimable when creasing/folding at the nail line, lifted tabs, or missing shingles are present.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.skySoft.opacity(0.5), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sky.opacity(0.2), lineWidth: 0.6))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { exportPDF() } label: {
                HStack {
                    if isGeneratingPDF {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                    }
                    Text(isGeneratingPDF ? "Generating PDF…" : "Export & Share PDF Packet")
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 14)
                )
                .shadow(color: Theme.ember.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)

            Button { onClose() } label: {
                Text("Back to Inspection")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }
}
