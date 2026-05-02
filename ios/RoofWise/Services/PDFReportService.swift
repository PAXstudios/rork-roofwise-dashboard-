import UIKit
import SwiftUI

/// Generates a branded RoofWise inspection PDF report, ready to share via
/// email, message, or AirDrop.
enum PDFReportService {
    struct Input {
        var customer: Customer?
        var photos: [CapturedPhoto]
        var findings: [InspectionFinding]
        var packet: ClaimPacket?
        var repName: String
        var repPhone: String
        var repCompany: String
    }

    /// US Letter at 72 dpi: 612 x 792.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static let ember = UIColor(red: 1.00, green: 0.42, blue: 0.18, alpha: 1)
    private static let emberDeep = UIColor(red: 0.91, green: 0.32, blue: 0.10, alpha: 1)
    private static let ink = UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1)
    private static let inkSoft = UIColor(red: 0.27, green: 0.32, blue: 0.43, alpha: 1)
    private static let inkFaint = UIColor(red: 0.55, green: 0.59, blue: 0.67, alpha: 1)
    private static let canvas = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    private static let hairline = UIColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1)

    /// Generates the PDF and writes it to a temp URL. Returns the file URL on success.
    @discardableResult
    static func generate(input: Input) -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "RoofWise Inspection Report",
            kCGPDFContextAuthor as String: input.repCompany.isEmpty ? "RoofWise" : input.repCompany
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let url = tempURL(for: input)
        do {
            try renderer.writePDF(to: url) { ctx in
                drawCoverPage(ctx, input: input)
                if !input.photos.isEmpty {
                    drawPhotoPages(ctx, input: input)
                }
                drawFindingsPage(ctx, input: input)
                if input.packet != nil {
                    drawClaimPage(ctx, input: input)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func tempURL(for input: Input) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let owner = (input.customer?.ownerName ?? "Inspection")
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
            .joined()
        let filename = "RoofWise_\(owner)_\(date).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    // MARK: - Cover Page

    private static func drawCoverPage(_ ctx: UIGraphicsPDFRendererContext, input: Input) {
        ctx.beginPage()
        let cg = ctx.cgContext

        // Branded header band
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 150)
        drawGradient(cg, rect: band, colors: [ember, emberDeep])
        // Subtle dot pattern
        cg.saveGState()
        cg.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        for _ in 0..<60 {
            let x = CGFloat.random(in: 0...band.width)
            let y = CGFloat.random(in: 0...band.height)
            let r = CGFloat.random(in: 1...3)
            cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        cg.restoreGState()

        // Logo / wordmark
        drawLogoMark(cg, origin: CGPoint(x: margin, y: 38))

        // Brand title
        draw("ROOFWISE", at: CGPoint(x: margin + 46, y: 40),
             font: .systemFont(ofSize: 18, weight: .heavy),
             color: .white, kern: 3.0)
        draw("Forensic Roof Inspection · HAAG Standards", at: CGPoint(x: margin + 46, y: 62),
             font: .systemFont(ofSize: 10, weight: .semibold),
             color: UIColor.white.withAlphaComponent(0.85))

        // Date/timestamp upper right
        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long
        let timeFmt = DateFormatter(); timeFmt.timeStyle = .short
        let dateStr = "\(dateFmt.string(from: Date())) · \(timeFmt.string(from: Date()))"
        drawRight("INSPECTION REPORT", origin: CGPoint(x: pageSize.width - margin, y: 40),
                  font: .systemFont(ofSize: 9, weight: .heavy),
                  color: UIColor.white.withAlphaComponent(0.8), kern: 2.0)
        drawRight(dateStr, origin: CGPoint(x: pageSize.width - margin, y: 56),
                  font: .systemFont(ofSize: 11, weight: .heavy),
                  color: .white)

        // Property hero card
        var y: CGFloat = 180
        let cardRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 140)
        drawCard(cg, rect: cardRect, fill: .white)

        draw("PROPERTY", at: CGPoint(x: cardRect.minX + 20, y: cardRect.minY + 16),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.4)
        let owner = input.customer?.ownerName ?? "Property Inspection"
        draw(owner, at: CGPoint(x: cardRect.minX + 20, y: cardRect.minY + 30),
             font: .systemFont(ofSize: 22, weight: .heavy),
             color: ink)
        let addr = input.customer?.address ?? "Address pending"
        draw(addr, at: CGPoint(x: cardRect.minX + 20, y: cardRect.minY + 60),
             font: .systemFont(ofSize: 13, weight: .semibold),
             color: inkSoft)

        // 3-up stat row inside card
        let stats: [(String, String)] = [
            ("PHOTOS", "\(input.photos.count)"),
            ("FINDINGS", "\(input.findings.filter { $0.detected }.count)"),
            ("HAAG GRADE", input.packet?.grade.rawValue.replacingOccurrences(of: "Functional Damage - ", with: "") ?? "Pending")
        ]
        let statW = (cardRect.width - 40) / 3
        for (i, s) in stats.enumerated() {
            let x = cardRect.minX + 20 + statW * CGFloat(i)
            draw(s.0, at: CGPoint(x: x, y: cardRect.minY + 92),
                 font: .systemFont(ofSize: 8, weight: .heavy),
                 color: inkFaint, kern: 1.2)
            draw(s.1, at: CGPoint(x: x, y: cardRect.minY + 105),
                 font: .systemFont(ofSize: 16, weight: .heavy),
                 color: ember)
        }

        // Insurance + adjuster card
        y = cardRect.maxY + 16
        if let c = input.customer {
            let insRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 120)
            drawCard(cg, rect: insRect, fill: .white)
            draw("INSURANCE & CLAIM", at: CGPoint(x: insRect.minX + 20, y: insRect.minY + 16),
                 font: .systemFont(ofSize: 8, weight: .heavy),
                 color: inkFaint, kern: 1.4)
            let leftX = insRect.minX + 20
            let rightX = insRect.minX + insRect.width / 2 + 4
            drawLabelValue("Insurance Co.", c.insuranceCompany.isEmpty ? "—" : c.insuranceCompany,
                           origin: CGPoint(x: leftX, y: insRect.minY + 32))
            drawLabelValue("Policy No.", c.policyNumber.isEmpty ? "—" : c.policyNumber,
                           origin: CGPoint(x: leftX, y: insRect.minY + 60))
            drawLabelValue("Date of Loss",
                           c.dateOfLoss.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—",
                           origin: CGPoint(x: leftX, y: insRect.minY + 88))
            drawLabelValue("Adjuster", c.adjusterName.isEmpty ? "—" : c.adjusterName,
                           origin: CGPoint(x: rightX, y: insRect.minY + 32))
            drawLabelValue("Adjuster Phone", c.adjusterPhone.isEmpty ? "—" : c.adjusterPhone,
                           origin: CGPoint(x: rightX, y: insRect.minY + 60))
            drawLabelValue("Owner Phone", c.phone.isEmpty ? "—" : c.phone,
                           origin: CGPoint(x: rightX, y: insRect.minY + 88))
            y = insRect.maxY + 16
        }

        // Inspector card
        let repRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 100)
        drawCard(cg, rect: repRect, fill: canvas)
        draw("INSPECTED BY", at: CGPoint(x: repRect.minX + 20, y: repRect.minY + 16),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.4)
        draw(input.repName.isEmpty ? "Field Representative" : input.repName,
             at: CGPoint(x: repRect.minX + 20, y: repRect.minY + 32),
             font: .systemFont(ofSize: 16, weight: .heavy),
             color: ink)
        draw(input.repCompany.isEmpty ? "RoofWise" : input.repCompany,
             at: CGPoint(x: repRect.minX + 20, y: repRect.minY + 56),
             font: .systemFont(ofSize: 12, weight: .semibold),
             color: inkSoft)
        if !input.repPhone.isEmpty {
            draw(input.repPhone,
                 at: CGPoint(x: repRect.minX + 20, y: repRect.minY + 74),
                 font: .systemFont(ofSize: 11, weight: .medium),
                 color: inkSoft)
        }

        // Footer
        drawFooter(cg, page: 1)
    }

    // MARK: - Photos pages

    private static func drawPhotoPages(_ ctx: UIGraphicsPDFRendererContext, input: Input) {
        // 4-up grid per page
        let perPage = 4
        let total = input.photos.count
        let pages = (total + perPage - 1) / perPage
        for p in 0..<pages {
            ctx.beginPage()
            drawPageHeader(ctx.cgContext, title: "Inspection Photos", subtitle: "Page \(p + 1) of \(pages) · \(total) total")

            let gridTop: CGFloat = 130
            let gridBottom: CGFloat = pageSize.height - 60
            let gridH = gridBottom - gridTop
            let cellW = (pageSize.width - margin*2 - 14) / 2
            let cellH = (gridH - 14) / 2
            for i in 0..<perPage {
                let idx = p * perPage + i
                guard idx < total else { break }
                let photo = input.photos[idx]
                let row = i / 2
                let col = i % 2
                let rect = CGRect(x: margin + CGFloat(col) * (cellW + 14),
                                  y: gridTop + CGFloat(row) * (cellH + 14),
                                  width: cellW, height: cellH)
                drawPhotoCell(ctx.cgContext, rect: rect, photo: photo, index: idx + 1)
            }
            drawFooter(ctx.cgContext, page: 2 + p)
        }
    }

    private static func drawPhotoCell(_ cg: CGContext, rect: CGRect, photo: CapturedPhoto, index: Int) {
        // Card frame
        drawCard(cg, rect: rect, fill: .white)

        // Image area
        let imageRect = CGRect(x: rect.minX + 8, y: rect.minY + 8,
                               width: rect.width - 16, height: rect.height - 60)
        cg.saveGState()
        let path = UIBezierPath(roundedRect: imageRect, cornerRadius: 8)
        cg.addPath(path.cgPath)
        cg.clip()
        // aspect fill
        let imgSize = photo.image.size
        guard imgSize.width > 0, imgSize.height > 0 else {
            cg.restoreGState()
            return
        }
        let scale = max(imageRect.width / imgSize.width, imageRect.height / imgSize.height)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawX = imageRect.midX - drawW / 2
        let drawY = imageRect.midY - drawH / 2
        photo.image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        cg.restoreGState()

        // Index badge (top-left)
        let badgeRect = CGRect(x: imageRect.minX + 6, y: imageRect.minY + 6, width: 22, height: 22)
        cg.setFillColor(emberDeep.cgColor)
        cg.fillEllipse(in: badgeRect)
        drawCentered("\(index)", in: badgeRect,
                     font: .systemFont(ofSize: 11, weight: .heavy), color: .white)

        // Slope label (bottom of image)
        let slopeRect = CGRect(x: imageRect.minX, y: imageRect.maxY - 22, width: imageRect.width, height: 22)
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: slopeRect, cornerRadius: 0).cgPath)
        cg.clip()
        cg.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        cg.fill(slopeRect)
        cg.restoreGState()
        draw(photo.slope.shortName.uppercased(),
             at: CGPoint(x: slopeRect.minX + 8, y: slopeRect.minY + 5),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: .white, kern: 1.0)
        let modeStr = photo.captureMode == .singleShingle ? "CLOSE-UP" : "10×10 SQ"
        drawRight(modeStr, origin: CGPoint(x: slopeRect.maxX - 8, y: slopeRect.minY + 5),
                  font: .systemFont(ofSize: 9, weight: .heavy),
                  color: UIColor.white.withAlphaComponent(0.85), kern: 1.0)

        // Caption row beneath image
        let capY = imageRect.maxY + 8
        let pitchStr = String(format: "Pitch %.1f°", photo.pitchDegrees)
        let elevStr = "Elev \(Int(photo.elevationFeet))ft"
        draw(photo.slope.rawValue,
             at: CGPoint(x: rect.minX + 12, y: capY),
             font: .systemFont(ofSize: 10, weight: .heavy),
             color: ink)
        draw("\(pitchStr) · \(elevStr) · \(photo.timestamp.formatted(date: .omitted, time: .shortened))",
             at: CGPoint(x: rect.minX + 12, y: capY + 14),
             font: .systemFont(ofSize: 8, weight: .medium),
             color: inkSoft)

        // Hits chip on right
        if !photo.damageMarkers.isEmpty {
            let chipText = "\(photo.damageMarkers.count) hits"
            let chipSize = CGSize(width: 50, height: 16)
            let chipRect = CGRect(x: rect.maxX - chipSize.width - 12, y: capY,
                                  width: chipSize.width, height: chipSize.height)
            cg.saveGState()
            cg.setFillColor(UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 0.14).cgColor)
            cg.addPath(UIBezierPath(roundedRect: chipRect, cornerRadius: 8).cgPath)
            cg.fillPath()
            cg.restoreGState()
            drawCentered(chipText, in: chipRect,
                         font: .systemFont(ofSize: 8, weight: .heavy),
                         color: UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 1))
        }
    }

    // MARK: - Findings page

    private static func drawFindingsPage(_ ctx: UIGraphicsPDFRendererContext, input: Input) {
        ctx.beginPage()
        drawPageHeader(ctx.cgContext, title: "Damage Analysis", subtitle: "AI-confirmed findings · Gemini Vision")

        var y: CGFloat = 130
        let findings = input.findings.isEmpty ? InspectionMock.findings : input.findings

        for f in findings {
            let rowRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 56)
            drawCard(ctx.cgContext, rect: rowRect, fill: .white)
            // tint badge
            let badgeRect = CGRect(x: rowRect.minX + 12, y: rowRect.minY + 12, width: 32, height: 32)
            ctx.cgContext.saveGState()
            ctx.cgContext.setFillColor(uiColor(for: f.severity).withAlphaComponent(0.16).cgColor)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: badgeRect, cornerRadius: 8).cgPath)
            ctx.cgContext.fillPath()
            ctx.cgContext.restoreGState()
            drawCentered(initialsFor(f.display), in: badgeRect,
                         font: .systemFont(ofSize: 11, weight: .heavy),
                         color: uiColor(for: f.severity))

            draw(f.display, at: CGPoint(x: rowRect.minX + 56, y: rowRect.minY + 12),
                 font: .systemFont(ofSize: 13, weight: .heavy), color: ink)
            // severity pill
            let pillText = f.severity.rawValue.uppercased()
            let pillSize = textSize(pillText, font: .systemFont(ofSize: 8, weight: .heavy), kern: 1.0)
            let pillRect = CGRect(x: rowRect.minX + 56, y: rowRect.minY + 30,
                                  width: pillSize.width + 12, height: 14)
            ctx.cgContext.saveGState()
            ctx.cgContext.setFillColor(uiColor(for: f.severity).withAlphaComponent(0.16).cgColor)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: pillRect, cornerRadius: 7).cgPath)
            ctx.cgContext.fillPath()
            ctx.cgContext.restoreGState()
            drawCentered(pillText, in: pillRect,
                         font: .systemFont(ofSize: 8, weight: .heavy),
                         color: uiColor(for: f.severity), kern: 1.0)

            draw(f.value, at: CGPoint(x: rowRect.minX + 56 + pillRect.width + 8, y: rowRect.minY + 32),
                 font: .systemFont(ofSize: 10, weight: .medium), color: inkSoft)

            // Confidence right side
            let confStr = "\(f.confidence)%"
            drawRight(confStr,
                      origin: CGPoint(x: rowRect.maxX - 18, y: rowRect.minY + 16),
                      font: .systemFont(ofSize: 16, weight: .heavy),
                      color: f.detected ? ember : inkFaint)
            drawRight(f.detected ? "confidence" : "not detected",
                      origin: CGPoint(x: rowRect.maxX - 18, y: rowRect.minY + 36),
                      font: .systemFont(ofSize: 9, weight: .semibold),
                      color: inkFaint)

            y += rowRect.height + 8
            if y > pageSize.height - 100 {
                drawFooter(ctx.cgContext, page: 0)
                ctx.beginPage()
                drawPageHeader(ctx.cgContext, title: "Damage Analysis (cont.)", subtitle: "AI-confirmed findings")
                y = 130
            }
        }

        drawFooter(ctx.cgContext, page: 0)
    }

    // MARK: - Claim page

    private static func drawClaimPage(_ ctx: UIGraphicsPDFRendererContext, input: Input) {
        guard let packet = input.packet else { return }
        ctx.beginPage()
        drawPageHeader(ctx.cgContext, title: "HAAG Claim Packet",
                       subtitle: "Forensic recommendation · \(packet.generatedAt.formatted(date: .abbreviated, time: .shortened))")

        let cg = ctx.cgContext

        // Grade hero
        var y: CGFloat = 130
        let heroRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 100)
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: heroRect, cornerRadius: 16).cgPath)
        cg.clip()
        let heroColor = uiColor(for: packet.grade)
        drawGradient(cg, rect: heroRect, colors: [heroColor, heroColor.withAlphaComponent(0.75)])
        cg.restoreGState()
        draw("HAAG GRADE", at: CGPoint(x: heroRect.minX + 20, y: heroRect.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: UIColor.white.withAlphaComponent(0.9), kern: 1.6)
        draw(packet.grade.rawValue, at: CGPoint(x: heroRect.minX + 20, y: heroRect.minY + 32),
             font: .systemFont(ofSize: 20, weight: .heavy),
             color: .white)
        draw(packet.recommendation, at: CGPoint(x: heroRect.minX + 20, y: heroRect.minY + 60),
             font: .systemFont(ofSize: 12, weight: .semibold),
             color: UIColor.white.withAlphaComponent(0.92))
        let stats = "Perils: \(packet.perils.isEmpty ? "—" : packet.perils.joined(separator: " + "))   ·   Affected Squares: \(String(format: "%.1f", packet.affectedSquares))"
        draw(stats, at: CGPoint(x: heroRect.minX + 20, y: heroRect.minY + 78),
             font: .systemFont(ofSize: 10, weight: .heavy),
             color: UIColor.white.withAlphaComponent(0.88))

        // Summary
        y = heroRect.maxY + 16
        let summaryRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 110)
        drawCard(cg, rect: summaryRect, fill: .white)
        draw("FORENSIC SUMMARY", at: CGPoint(x: summaryRect.minX + 16, y: summaryRect.minY + 14),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: inkFaint, kern: 1.2)
        drawWrapped(packet.summary,
                    rect: CGRect(x: summaryRect.minX + 16, y: summaryRect.minY + 30,
                                 width: summaryRect.width - 32, height: summaryRect.height - 38),
                    font: .systemFont(ofSize: 11, weight: .regular),
                    color: inkSoft, lineSpacing: 4)

        // Slope breakdown
        y = summaryRect.maxY + 16
        let slopeHeader = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 22)
        draw("DOCUMENTED FINDINGS BY SLOPE",
             at: CGPoint(x: slopeHeader.minX, y: slopeHeader.minY),
             font: .systemFont(ofSize: 10, weight: .heavy), color: ink, kern: 1.0)
        y += 24
        for entry in packet.slopeFindings {
            let rect = CGRect(x: margin, y: y, width: pageSize.width - margin*2,
                              height: 30 + CGFloat(max(1, entry.topFindings.count)) * 14)
            drawCard(cg, rect: rect, fill: canvas)
            draw(entry.slope.shortName,
                 at: CGPoint(x: rect.minX + 14, y: rect.minY + 10),
                 font: .systemFont(ofSize: 12, weight: .heavy), color: ink)
            drawRight("\(entry.photoCount) photo\(entry.photoCount == 1 ? "" : "s")",
                      origin: CGPoint(x: rect.maxX - 14, y: rect.minY + 10),
                      font: .systemFont(ofSize: 10, weight: .heavy), color: inkFaint)
            if entry.topFindings.isEmpty {
                draw("No defects detected",
                     at: CGPoint(x: rect.minX + 14, y: rect.minY + 28),
                     font: .systemFont(ofSize: 10, weight: .medium),
                     color: UIColor(red: 0.18, green: 0.70, blue: 0.50, alpha: 1))
            } else {
                for (i, f) in entry.topFindings.enumerated() {
                    draw("•  \(f)",
                         at: CGPoint(x: rect.minX + 14, y: rect.minY + 28 + CGFloat(i) * 14),
                         font: .systemFont(ofSize: 10, weight: .regular),
                         color: inkSoft)
                }
            }
            y += rect.height + 6
            if y > pageSize.height - 100 {
                drawFooter(cg, page: 0)
                ctx.beginPage()
                drawPageHeader(cg, title: "HAAG Claim Packet (cont.)", subtitle: "")
                y = 130
            }
        }

        drawFooter(cg, page: 0)
    }

    // MARK: - Drawing helpers

    private static func drawPageHeader(_ cg: CGContext, title: String, subtitle: String) {
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 80)
        cg.setFillColor(canvas.cgColor)
        cg.fill(band)
        // accent stripe
        cg.setFillColor(ember.cgColor)
        cg.fill(CGRect(x: 0, y: band.maxY, width: pageSize.width, height: 2))
        drawLogoMark(cg, origin: CGPoint(x: margin, y: 28))
        draw("ROOFWISE", at: CGPoint(x: margin + 32, y: 26),
             font: .systemFont(ofSize: 11, weight: .heavy), color: ember, kern: 2.4)
        draw(title, at: CGPoint(x: margin + 32, y: 42),
             font: .systemFont(ofSize: 16, weight: .heavy), color: ink)
        if !subtitle.isEmpty {
            drawRight(subtitle,
                      origin: CGPoint(x: pageSize.width - margin, y: 44),
                      font: .systemFont(ofSize: 10, weight: .semibold),
                      color: inkSoft)
        }
    }

    private static func drawFooter(_ cg: CGContext, page: Int) {
        let y = pageSize.height - 32
        cg.setFillColor(hairline.cgColor)
        cg.fill(CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 0.6))
        draw("Generated by RoofWise · Forensic field intelligence",
             at: CGPoint(x: margin, y: y + 8),
             font: .systemFont(ofSize: 8, weight: .semibold),
             color: inkFaint, kern: 0.4)
    }

    private static func drawLogoMark(_ cg: CGContext, origin: CGPoint) {
        // Simple stylized roof "house" mark
        let rect = CGRect(origin: origin, size: CGSize(width: 28, height: 28))
        cg.saveGState()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.midY))
        path.close()
        cg.addPath(path.cgPath)
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillPath()
        cg.addPath(path.cgPath)
        cg.setStrokeColor(ember.cgColor)
        cg.setLineWidth(1.4)
        cg.strokePath()
        // ember flame dot
        cg.setFillColor(ember.cgColor)
        cg.fillEllipse(in: CGRect(x: rect.midX - 3, y: rect.midY + 2, width: 6, height: 6))
        cg.restoreGState()
    }

    private static func drawCard(_ cg: CGContext, rect: CGRect, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        cg.saveGState()
        // shadow
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                     color: UIColor.black.withAlphaComponent(0.06).cgColor)
        cg.setFillColor(fill.cgColor)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.restoreGState()
        cg.setStrokeColor(hairline.cgColor)
        cg.setLineWidth(0.6)
        cg.addPath(path.cgPath)
        cg.strokePath()
    }

    private static func drawGradient(_ cg: CGContext, rect: CGRect, colors: [UIColor]) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let grad = CGGradient(colorsSpace: cs,
                                    colors: colors.map { $0.cgColor } as CFArray,
                                    locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(grad,
                              start: CGPoint(x: rect.minX, y: rect.minY),
                              end: CGPoint(x: rect.maxX, y: rect.maxY),
                              options: [])
        cg.restoreGState()
    }

    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color,
            .kern: kern, .paragraphStyle: style
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    private static func drawRight(_ text: String, origin: CGPoint,
                                  font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        text.draw(at: CGPoint(x: origin.x - size.width, y: origin.y), withAttributes: attrs)
    }

    private static func drawCentered(_ text: String, in rect: CGRect,
                                     font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: p, withAttributes: attrs)
    }

    private static func drawWrapped(_ text: String, rect: CGRect,
                                    font: UIFont, color: UIColor, lineSpacing: CGFloat = 2) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func drawLabelValue(_ label: String, _ value: String, origin: CGPoint) {
        draw(label.uppercased(), at: origin,
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.0)
        draw(value, at: CGPoint(x: origin.x, y: origin.y + 11),
             font: .systemFont(ofSize: 12, weight: .heavy),
             color: ink)
    }

    private static func textSize(_ text: String, font: UIFont, kern: CGFloat = 0) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        return (text as NSString).size(withAttributes: attrs)
    }

    private static func uiColor(for severity: FindingSeverity) -> UIColor {
        switch severity {
        case .none: return UIColor(red: 0.18, green: 0.70, blue: 0.50, alpha: 1)
        case .minor: return UIColor(red: 0.97, green: 0.74, blue: 0.21, alpha: 1)
        case .moderate: return ember
        case .severe: return UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 1)
        }
    }

    private static func uiColor(for grade: HaagGrade) -> UIColor {
        switch grade {
        case .noFunctional: return UIColor(red: 0.18, green: 0.70, blue: 0.50, alpha: 1)
        case .hail: return ember
        case .wind: return UIColor(red: 0.20, green: 0.50, blue: 0.95, alpha: 1)
        case .combined: return UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 1)
        }
    }

    private static func initialsFor(_ str: String) -> String {
        let parts = str.split(separator: " ")
        if parts.count >= 2 { return parts.prefix(2).map { $0.prefix(1) }.joined().uppercased() }
        return str.prefix(2).uppercased()
    }
}

// MARK: - SwiftUI Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
