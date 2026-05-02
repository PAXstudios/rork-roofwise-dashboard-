import UIKit

/// One-page, homeowner-friendly summary suitable for instant text/email share.
/// Designed to be approachable and visually clean — not the forensic claim packet.
enum HomeownerReportService {
    struct Input {
        var customer: Customer
        var photos: [CapturedPhoto]
        var findings: [InspectionFinding]
        var nextStep: String
        var repName: String
        var repPhone: String
        var repCompany: String
    }

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 32
    private static let ember = UIColor(red: 1.00, green: 0.42, blue: 0.18, alpha: 1)
    private static let emberDeep = UIColor(red: 0.91, green: 0.32, blue: 0.10, alpha: 1)
    private static let ink = UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1)
    private static let inkSoft = UIColor(red: 0.27, green: 0.32, blue: 0.43, alpha: 1)
    private static let inkFaint = UIColor(red: 0.55, green: 0.59, blue: 0.67, alpha: 1)
    private static let canvas = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    private static let mint = UIColor(red: 0.18, green: 0.70, blue: 0.50, alpha: 1)
    private static let hairline = UIColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1)

    @discardableResult
    static func generate(input: Input) -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Your Roof Report",
            kCGPDFContextAuthor as String: input.repCompany.isEmpty ? "RoofWise" : input.repCompany
        ] as [String: Any]
        let url = tempURL(for: input)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        do {
            try renderer.writePDF(to: url) { ctx in
                drawPage(ctx, input: input)
            }
            return url
        } catch {
            return nil
        }
    }

    static func renderPreviewImage(input: Input, scale: CGFloat = 1.5) -> UIImage? {
        let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { rctx in
            let cg = rctx.cgContext
            cg.scaleBy(x: scale, y: scale)
            // Background page
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: pageSize))
            drawContent(cg: cg, input: input)
        }
    }

    private static func tempURL(for input: Input) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let owner = input.customer.ownerName
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
            .joined()
        return FileManager.default.temporaryDirectory.appendingPathComponent("RoofWise_Homeowner_\(owner)_\(f.string(from: Date())).pdf")
    }

    // MARK: - Drawing

    private static func drawPage(_ ctx: UIGraphicsPDFRendererContext, input: Input) {
        ctx.beginPage()
        drawContent(cg: ctx.cgContext, input: input)
    }

    private static func drawContent(cg: CGContext, input: Input) {
        // Hero band
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 130)
        drawGradient(cg, rect: band, colors: [ember, emberDeep])
        // soft rain dots
        cg.saveGState()
        cg.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        for _ in 0..<40 {
            let x = CGFloat.random(in: 0...band.width)
            let y = CGFloat.random(in: 0...band.height)
            cg.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
        }
        cg.restoreGState()

        drawLogoMark(cg, origin: CGPoint(x: margin, y: 28))
        draw("ROOFWISE", at: CGPoint(x: margin + 40, y: 28),
             font: .systemFont(ofSize: 12, weight: .heavy),
             color: .white, kern: 2.6)
        draw("Your Roof, Explained",
             at: CGPoint(x: margin + 40, y: 46),
             font: .systemFont(ofSize: 22, weight: .heavy),
             color: .white)
        draw("A quick summary of what we found on your home today.",
             at: CGPoint(x: margin + 40, y: 78),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: UIColor.white.withAlphaComponent(0.9))

        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long
        drawRight(dateFmt.string(from: Date()),
                  origin: CGPoint(x: pageSize.width - margin, y: 30),
                  font: .systemFont(ofSize: 10, weight: .heavy),
                  color: UIColor.white.withAlphaComponent(0.9))

        // Property card
        var y: CGFloat = 150
        let propRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 76)
        drawCard(cg, rect: propRect, fill: .white)
        draw("PREPARED FOR", at: CGPoint(x: propRect.minX + 16, y: propRect.minY + 14),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.4)
        draw(input.customer.ownerName,
             at: CGPoint(x: propRect.minX + 16, y: propRect.minY + 28),
             font: .systemFont(ofSize: 18, weight: .heavy),
             color: ink)
        draw(input.customer.address.isEmpty ? "—" : input.customer.address,
             at: CGPoint(x: propRect.minX + 16, y: propRect.minY + 52),
             font: .systemFont(ofSize: 12, weight: .semibold),
             color: inkSoft)

        // Health score circle (right side of property card)
        let detected = input.findings.filter { $0.detected }.count
        let score = max(20, 100 - detected * 12)
        let scoreColor: UIColor = score >= 75 ? mint : (score >= 50 ? UIColor(red: 0.97, green: 0.74, blue: 0.21, alpha: 1) : UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 1))
        let scoreCenter = CGPoint(x: propRect.maxX - 40, y: propRect.midY)
        cg.saveGState()
        cg.setStrokeColor(canvas.cgColor)
        cg.setLineWidth(5)
        cg.addArc(center: scoreCenter, radius: 22, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        cg.strokePath()
        cg.setStrokeColor(scoreColor.cgColor)
        cg.setLineWidth(5)
        cg.setLineCap(.round)
        let frac = CGFloat(score) / 100.0
        cg.addArc(center: scoreCenter,
                  radius: 22,
                  startAngle: -.pi / 2,
                  endAngle: -.pi / 2 + .pi * 2 * frac,
                  clockwise: false)
        cg.strokePath()
        cg.restoreGState()
        drawCentered("\(score)", in: CGRect(x: scoreCenter.x - 22, y: scoreCenter.y - 8, width: 44, height: 18),
                     font: .systemFont(ofSize: 13, weight: .heavy),
                     color: ink)

        // Photo strip (up to 3)
        y = propRect.maxY + 14
        let stripH: CGFloat = 130
        let stripRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: stripH)
        let cellW = (stripRect.width - 16) / 3
        for i in 0..<3 {
            let cell = CGRect(x: stripRect.minX + CGFloat(i) * (cellW + 8),
                              y: stripRect.minY,
                              width: cellW, height: stripH)
            cg.saveGState()
            cg.addPath(UIBezierPath(roundedRect: cell, cornerRadius: 12).cgPath)
            cg.clip()
            if i < input.photos.count {
                let photo = input.photos[i]
                let imgSize = photo.image.size
                if imgSize.width > 0, imgSize.height > 0 {
                    let scale = max(cell.width / imgSize.width, cell.height / imgSize.height)
                    let drawW = imgSize.width * scale
                    let drawH = imgSize.height * scale
                    photo.image.draw(in: CGRect(x: cell.midX - drawW/2,
                                                y: cell.midY - drawH/2,
                                                width: drawW, height: drawH))
                }
                // Slope label
                let label = photo.slope.rawValue
                let labelRect = CGRect(x: cell.minX, y: cell.maxY - 22, width: cell.width, height: 22)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
                cg.fill(labelRect)
                draw(label,
                     at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 6),
                     font: .systemFont(ofSize: 9, weight: .heavy),
                     color: .white, kern: 0.6)
            } else {
                cg.setFillColor(canvas.cgColor)
                cg.fill(cell)
                drawCentered("Photo",
                             in: cell,
                             font: .systemFont(ofSize: 11, weight: .semibold),
                             color: inkFaint)
            }
            cg.restoreGState()
        }

        // Plain-language findings
        y = stripRect.maxY + 18
        draw("WHAT WE FOUND",
             at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 10, weight: .heavy),
             color: ember, kern: 1.4)
        y += 16

        let detectedFindings = input.findings.filter { $0.detected }.prefix(3)
        if detectedFindings.isEmpty {
            let txt = "Good news — no major functional damage was found during today's inspection. We recommend keeping an eye on the roof after the next storm event."
            let r = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 60)
            drawCard(cg, rect: r, fill: .white)
            drawWrapped(txt,
                        rect: CGRect(x: r.minX + 14, y: r.minY + 12, width: r.width - 28, height: r.height - 24),
                        font: .systemFont(ofSize: 11, weight: .semibold),
                        color: inkSoft, lineSpacing: 4)
            y = r.maxY + 14
        } else {
            for f in detectedFindings {
                let row = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 56)
                drawCard(cg, rect: row, fill: .white)
                // colored severity dot
                let dotColor = severityColor(f.severity)
                cg.setFillColor(dotColor.withAlphaComponent(0.16).cgColor)
                cg.addPath(UIBezierPath(roundedRect: CGRect(x: row.minX + 12, y: row.minY + 12, width: 32, height: 32), cornerRadius: 8).cgPath)
                cg.fillPath()
                drawCentered("•", in: CGRect(x: row.minX + 12, y: row.minY + 12, width: 32, height: 32),
                             font: .systemFont(ofSize: 28, weight: .heavy),
                             color: dotColor)
                draw(f.display,
                     at: CGPoint(x: row.minX + 56, y: row.minY + 12),
                     font: .systemFont(ofSize: 13, weight: .heavy), color: ink)
                drawWrapped(plainLanguage(for: f),
                            rect: CGRect(x: row.minX + 56, y: row.minY + 28,
                                         width: row.width - 70, height: 26),
                            font: .systemFont(ofSize: 10, weight: .regular),
                            color: inkSoft, lineSpacing: 2)
                y = row.maxY + 8
                if y > pageSize.height - 240 { break }
            }
        }

        // Recommended next step
        y += 6
        let nextRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 90)
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: nextRect, cornerRadius: 16).cgPath)
        cg.clip()
        drawGradient(cg, rect: nextRect, colors: [ink, UIColor(red: 0.18, green: 0.25, blue: 0.45, alpha: 1)])
        cg.restoreGState()
        draw("RECOMMENDED NEXT STEP",
             at: CGPoint(x: nextRect.minX + 16, y: nextRect.minY + 14),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: UIColor.white.withAlphaComponent(0.85), kern: 1.4)
        let nextText = input.nextStep.isEmpty
            ? "File a claim with your insurance carrier within 30 days. We'll help you walk the adjuster through every finding."
            : input.nextStep
        drawWrapped(nextText,
                    rect: CGRect(x: nextRect.minX + 16, y: nextRect.minY + 30,
                                 width: nextRect.width - 32, height: nextRect.height - 38),
                    font: .systemFont(ofSize: 12, weight: .semibold),
                    color: .white, lineSpacing: 3)
        y = nextRect.maxY + 14

        // Rep card / signature
        let repRect = CGRect(x: margin, y: y, width: pageSize.width - margin*2, height: 70)
        drawCard(cg, rect: repRect, fill: canvas)
        draw("YOUR INSPECTOR",
             at: CGPoint(x: repRect.minX + 14, y: repRect.minY + 12),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.2)
        draw(input.repName.isEmpty ? "RoofWise Field Rep" : input.repName,
             at: CGPoint(x: repRect.minX + 14, y: repRect.minY + 26),
             font: .systemFont(ofSize: 14, weight: .heavy),
             color: ink)
        draw(input.repCompany.isEmpty ? "RoofWise" : input.repCompany,
             at: CGPoint(x: repRect.minX + 14, y: repRect.minY + 46),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: inkSoft)
        if !input.repPhone.isEmpty {
            drawRight(input.repPhone,
                      origin: CGPoint(x: repRect.maxX - 14, y: repRect.minY + 26),
                      font: .systemFont(ofSize: 14, weight: .heavy), color: ember)
            drawRight("Call or text anytime",
                      origin: CGPoint(x: repRect.maxX - 14, y: repRect.minY + 46),
                      font: .systemFont(ofSize: 10, weight: .semibold), color: inkSoft)
        }

        // Footer
        let footY = pageSize.height - 24
        cg.setFillColor(hairline.cgColor)
        cg.fill(CGRect(x: margin, y: footY - 8, width: pageSize.width - margin*2, height: 0.6))
        draw("Generated with RoofWise — your one-tap roof inspection toolkit",
             at: CGPoint(x: margin, y: footY),
             font: .systemFont(ofSize: 8, weight: .semibold),
             color: inkFaint, kern: 0.4)
    }

    // MARK: - Plain language

    private static func plainLanguage(for f: InspectionFinding) -> String {
        let base = f.value.isEmpty ? "" : "\(f.value). "
        switch f.severity {
        case .severe: return base + "Significant damage that typically warrants a full slope replacement."
        case .moderate: return base + "Visible damage that should be reviewed by your insurance adjuster."
        case .minor: return base + "Minor wear we'll continue to monitor at no cost."
        case .none: return base + "Photo-documented for your records."
        }
    }

    // MARK: - Primitives

    private static func drawCard(_ cg: CGContext, rect: CGRect, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 5,
                     color: UIColor.black.withAlphaComponent(0.06).cgColor)
        cg.setFillColor(fill.cgColor)
        cg.addPath(path.cgPath); cg.fillPath()
        cg.restoreGState()
        cg.setStrokeColor(hairline.cgColor)
        cg.setLineWidth(0.6)
        cg.addPath(path.cgPath); cg.strokePath()
    }

    private static func drawGradient(_ cg: CGContext, rect: CGRect, colors: [UIColor]) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: cs,
                                 colors: colors.map { $0.cgColor } as CFArray,
                                 locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(g,
                              start: CGPoint(x: rect.minX, y: rect.minY),
                              end: CGPoint(x: rect.maxX, y: rect.maxY),
                              options: [])
        cg.restoreGState()
    }

    private static func drawLogoMark(_ cg: CGContext, origin: CGPoint) {
        let rect = CGRect(origin: origin, size: CGSize(width: 28, height: 28))
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
    }

    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        text.draw(at: point, withAttributes: attrs)
    }

    private static func drawRight(_ text: String, origin: CGPoint,
                                  font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let size = (text as NSString).size(withAttributes: attrs)
        text.draw(at: CGPoint(x: origin.x - size.width, y: origin.y), withAttributes: attrs)
    }

    private static func drawCentered(_ text: String, in rect: CGRect,
                                     font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: p, withAttributes: attrs)
    }

    private static func drawWrapped(_ text: String, rect: CGRect,
                                    font: UIFont, color: UIColor, lineSpacing: CGFloat = 2) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func severityColor(_ s: FindingSeverity) -> UIColor {
        switch s {
        case .none: return mint
        case .minor: return UIColor(red: 0.97, green: 0.74, blue: 0.21, alpha: 1)
        case .moderate: return ember
        case .severe: return UIColor(red: 0.86, green: 0.22, blue: 0.31, alpha: 1)
        }
    }
}
