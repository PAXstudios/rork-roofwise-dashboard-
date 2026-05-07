import UIKit
import PDFKit

/// Generates a branded multi-page PDF for a `Proposal`. Letter @ 72dpi,
/// 0.5" margins. Pure: takes a Proposal in, returns Data, and writes to disk.
nonisolated enum ProposalPDFGenerator {

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // Theme mirrors
    private static let ink       = UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1)
    private static let inkSoft   = UIColor(red: 0.27,  green: 0.32,  blue: 0.43,  alpha: 1)
    private static let inkFaint  = UIColor(red: 0.55,  green: 0.59,  blue: 0.67,  alpha: 1)
    private static let canvas    = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    private static let hairline  = UIColor(red: 0.91,  green: 0.90,  blue: 0.88,  alpha: 1)
    private static let ember     = UIColor(red: 1.00,  green: 0.42,  blue: 0.18,  alpha: 1)
    private static let emberDeep = UIColor(red: 0.91,  green: 0.32,  blue: 0.10,  alpha: 1)
    private static let mint      = UIColor(red: 0.18,  green: 0.70,  blue: 0.50,  alpha: 1)

    // MARK: Public

    static func generate(_ proposal: Proposal) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "RoofWise Proposal — \(proposal.originJobId)",
            kCGPDFContextAuthor as String: "RoofWise"
        ] as [String: Any]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )
        return renderer.pdfData { ctx in
            drawCover(ctx, proposal)
            drawScope(ctx, proposal)
            drawLineItems(ctx, proposal)
            drawTerms(ctx, proposal)
            drawSignature(ctx, proposal)
        }
    }

    @discardableResult
    static func write(_ proposal: Proposal) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        let url = docs.appendingPathComponent("Proposal-\(proposal.originJobId).pdf")
        do {
            try generate(proposal).write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    // MARK: Pages

    private static func drawCover(_ ctx: UIGraphicsPDFRendererContext, _ p: Proposal) {
        ctx.beginPage()
        let cg = ctx.cgContext
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 180)
        drawGradient(cg, rect: band, colors: [ember, emberDeep])

        draw("ROOFWISE",
             at: CGPoint(x: margin, y: 50),
             font: .systemFont(ofSize: 18, weight: .heavy),
             color: .white, kern: 3.0)
        draw("PROPOSAL",
             at: CGPoint(x: margin, y: 76),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: UIColor.white.withAlphaComponent(0.92), kern: 2.0)

        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long
        drawRight("VALID UNTIL",
                  origin: CGPoint(x: pageSize.width - margin, y: 50),
                  font: .systemFont(ofSize: 9, weight: .heavy),
                  color: UIColor.white.withAlphaComponent(0.8), kern: 1.4)
        drawRight(dateFmt.string(from: p.validUntil),
                  origin: CGPoint(x: pageSize.width - margin, y: 64),
                  font: .systemFont(ofSize: 14, weight: .heavy),
                  color: .white)
        drawRight("Job \(p.originJobId)",
                  origin: CGPoint(x: pageSize.width - margin, y: 86),
                  font: .systemFont(ofSize: 10, weight: .semibold),
                  color: UIColor.white.withAlphaComponent(0.9))

        // Hero
        var y: CGFloat = 220
        let hero = CGRect(x: margin, y: y, width: contentWidth, height: 150)
        drawCard(cg, rect: hero, fill: .white)
        draw("PREPARED FOR",
             at: CGPoint(x: hero.minX + 18, y: hero.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: inkFaint, kern: 1.4)
        draw(showOrDash(p.homeownerName),
             at: CGPoint(x: hero.minX + 18, y: hero.minY + 30),
             font: .systemFont(ofSize: 22, weight: .heavy),
             color: ink)
        draw(showOrDash(p.projectAddress),
             at: CGPoint(x: hero.minX + 18, y: hero.minY + 64),
             font: .systemFont(ofSize: 13, weight: .semibold),
             color: inkSoft)

        // Total callout
        y = hero.maxY + 16
        let totalCard = CGRect(x: margin, y: y, width: contentWidth, height: 130)
        drawCard(cg, rect: totalCard, fill: canvas)
        draw("PROJECT TOTAL",
             at: CGPoint(x: totalCard.minX + 18, y: totalCard.minY + 16),
             font: .systemFont(ofSize: 10, weight: .heavy),
             color: inkSoft, kern: 1.4)
        draw(currency(p.total),
             at: CGPoint(x: totalCard.minX + 18, y: totalCard.minY + 32),
             font: .systemFont(ofSize: 32, weight: .heavy),
             color: ink)
        draw("Deposit due on signing: \(currency(p.depositAmount))",
             at: CGPoint(x: totalCard.minX + 18, y: totalCard.minY + 84),
             font: .systemFont(ofSize: 12, weight: .semibold),
             color: inkSoft)

        drawFooter(cg, page: 1, proposal: p)
    }

    private static func drawScope(_ ctx: UIGraphicsPDFRendererContext, _ p: Proposal) {
        ctx.beginPage()
        drawHeader(ctx.cgContext, title: "Scope of Work")
        let card = CGRect(x: margin, y: 130, width: contentWidth,
                          height: pageSize.height - 130 - 80)
        drawCard(ctx.cgContext, rect: card, fill: .white)
        drawWrapped(p.scopeNarrative,
                    rect: CGRect(x: card.minX + 20, y: card.minY + 20,
                                 width: card.width - 40, height: card.height - 40),
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: ink, lineSpacing: 4)
        drawFooter(ctx.cgContext, page: 2, proposal: p)
    }

    private static func drawLineItems(_ ctx: UIGraphicsPDFRendererContext, _ p: Proposal) {
        ctx.beginPage()
        drawHeader(ctx.cgContext, title: "Line Items")

        var y: CGFloat = 130
        let cg = ctx.cgContext

        // Column header strip
        let header = CGRect(x: margin, y: y, width: contentWidth, height: 28)
        cg.setFillColor(canvas.cgColor)
        cg.fill(header)
        draw("LABEL",
             at: CGPoint(x: header.minX + 14, y: header.minY + 10),
             font: .systemFont(ofSize: 9, weight: .heavy), color: inkSoft, kern: 1.2)
        drawRight("QTY",
                  origin: CGPoint(x: header.minX + contentWidth * 0.62, y: header.minY + 10),
                  font: .systemFont(ofSize: 9, weight: .heavy), color: inkSoft, kern: 1.2)
        drawRight("UNIT $",
                  origin: CGPoint(x: header.minX + contentWidth * 0.80, y: header.minY + 10),
                  font: .systemFont(ofSize: 9, weight: .heavy), color: inkSoft, kern: 1.2)
        drawRight("TOTAL",
                  origin: CGPoint(x: header.maxX - 14, y: header.minY + 10),
                  font: .systemFont(ofSize: 9, weight: .heavy), color: inkSoft, kern: 1.2)
        y += 36

        for item in p.lineItems {
            if y > pageSize.height - 220 {
                drawFooter(cg, page: 3, proposal: p)
                ctx.beginPage()
                drawHeader(cg, title: "Line Items (cont.)")
                y = 130
            }
            let row = CGRect(x: margin, y: y, width: contentWidth, height: 36)
            cg.setStrokeColor(hairline.cgColor)
            cg.setLineWidth(0.6)
            cg.move(to: CGPoint(x: row.minX, y: row.maxY))
            cg.addLine(to: CGPoint(x: row.maxX, y: row.maxY))
            cg.strokePath()

            draw(item.label,
                 at: CGPoint(x: row.minX + 14, y: row.minY + 12),
                 font: .systemFont(ofSize: 11, weight: .heavy), color: ink)
            drawRight(String(format: "%.1f %@", item.quantity, item.unit),
                      origin: CGPoint(x: row.minX + contentWidth * 0.62, y: row.minY + 12),
                      font: .systemFont(ofSize: 11, weight: .semibold), color: inkSoft)
            drawRight(currency(item.unitPrice),
                      origin: CGPoint(x: row.minX + contentWidth * 0.80, y: row.minY + 12),
                      font: .systemFont(ofSize: 11, weight: .semibold), color: inkSoft)
            drawRight(currency(item.totalPrice),
                      origin: CGPoint(x: row.maxX - 14, y: row.minY + 12),
                      font: .systemFont(ofSize: 12, weight: .heavy), color: ink)
            y += 36
        }

        // Totals card
        y += 16
        let totalsCard = CGRect(x: margin + contentWidth * 0.45, y: y,
                                width: contentWidth * 0.55, height: 140)
        drawCard(cg, rect: totalsCard, fill: canvas)
        let labelX = totalsCard.minX + 18
        let valueRX = totalsCard.maxX - 18
        let rowH: CGFloat = 26
        var ry = totalsCard.minY + 18
        let totalRows: [(String, String, Bool)] = [
            ("Subtotal", currency(p.subtotal), false),
            (String(format: "Tax (%.2f%%)", p.taxRate * 100), currency(p.tax), false),
            ("Total", currency(p.total), true),
            (String(format: "Deposit (%.0f%%)", p.depositPct * 100),
             currency(p.depositAmount), false)
        ]
        for (label, value, emphasis) in totalRows {
            let weight: UIFont.Weight = emphasis ? .heavy : .semibold
            let size: CGFloat = emphasis ? 14 : 11
            let color: UIColor = emphasis ? ink : inkSoft
            draw(label,
                 at: CGPoint(x: labelX, y: ry),
                 font: .systemFont(ofSize: size, weight: weight), color: color)
            drawRight(value,
                      origin: CGPoint(x: valueRX, y: ry),
                      font: .systemFont(ofSize: size, weight: .heavy),
                      color: emphasis ? ink : inkSoft)
            ry += rowH
        }

        drawFooter(cg, page: 3, proposal: p)
    }

    private static func drawTerms(_ ctx: UIGraphicsPDFRendererContext, _ p: Proposal) {
        ctx.beginPage()
        drawHeader(ctx.cgContext, title: "Terms")

        var y: CGFloat = 130
        let cg = ctx.cgContext
        let warranty = CGRect(x: margin, y: y, width: contentWidth, height: 130)
        drawCard(cg, rect: warranty, fill: .white)
        draw("WARRANTY",
             at: CGPoint(x: warranty.minX + 18, y: warranty.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy), color: inkFaint, kern: 1.4)
        drawWrapped(p.warrantyTerms,
                    rect: CGRect(x: warranty.minX + 18, y: warranty.minY + 32,
                                 width: warranty.width - 36, height: warranty.height - 40),
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: ink, lineSpacing: 3)
        y += 146

        let payment = CGRect(x: margin, y: y, width: contentWidth, height: 130)
        drawCard(cg, rect: payment, fill: .white)
        draw("PAYMENT SCHEDULE",
             at: CGPoint(x: payment.minX + 18, y: payment.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy), color: inkFaint, kern: 1.4)
        drawWrapped(p.paymentSchedule,
                    rect: CGRect(x: payment.minX + 18, y: payment.minY + 32,
                                 width: payment.width - 36, height: payment.height - 40),
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: ink, lineSpacing: 3)

        drawFooter(cg, page: 4, proposal: p)
    }

    private static func drawSignature(_ ctx: UIGraphicsPDFRendererContext, _ p: Proposal) {
        ctx.beginPage()
        drawHeader(ctx.cgContext, title: "Acceptance & Signature")

        let cg = ctx.cgContext
        let card = CGRect(x: margin, y: 140, width: contentWidth, height: 230)
        drawCard(cg, rect: card, fill: .white)
        draw("HOMEOWNER SIGNATURE",
             at: CGPoint(x: card.minX + 18, y: card.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy), color: inkFaint, kern: 1.4)

        let sigRect = CGRect(x: card.minX + 18, y: card.minY + 36,
                             width: card.width - 36, height: 130)
        cg.setFillColor(canvas.cgColor)
        cg.addPath(UIBezierPath(roundedRect: sigRect, cornerRadius: 10).cgPath)
        cg.fillPath()
        if let data = p.homeownerSignaturePng, let img = UIImage(data: data) {
            let inset = sigRect.insetBy(dx: 8, dy: 8)
            let imgSize = img.size
            if imgSize.width > 0, imgSize.height > 0 {
                let scale = min(inset.width / imgSize.width, inset.height / imgSize.height)
                let drawW = imgSize.width * scale
                let drawH = imgSize.height * scale
                img.draw(in: CGRect(x: inset.midX - drawW / 2,
                                    y: inset.midY - drawH / 2,
                                    width: drawW, height: drawH))
            }
        } else {
            cg.setStrokeColor(hairline.cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: sigRect.minX + 16, y: sigRect.maxY - 18))
            cg.addLine(to: CGPoint(x: sigRect.maxX - 16, y: sigRect.maxY - 18))
            cg.strokePath()
        }

        let lineY = card.maxY - 36
        draw(showOrDash(p.homeownerName),
             at: CGPoint(x: card.minX + 18, y: lineY),
             font: .systemFont(ofSize: 11, weight: .heavy), color: ink)
        draw("PRINTED NAME",
             at: CGPoint(x: card.minX + 18, y: lineY + 14),
             font: .systemFont(ofSize: 8, weight: .heavy), color: inkFaint, kern: 1.2)
        let dateText = (p.signedAt ?? .now).formatted(date: .abbreviated, time: .omitted)
        drawRight(dateText,
                  origin: CGPoint(x: card.maxX - 18, y: lineY),
                  font: .systemFont(ofSize: 11, weight: .heavy), color: ink)
        drawRight("DATE",
                  origin: CGPoint(x: card.maxX - 18, y: lineY + 14),
                  font: .systemFont(ofSize: 8, weight: .heavy), color: inkFaint, kern: 1.2)

        if p.status == .signed {
            let pill = CGRect(x: card.minX + 18, y: card.minY + 16 + 0,
                              width: 80, height: 0)
            _ = pill
            let badgeRect = CGRect(x: card.maxX - 110, y: card.minY + 12,
                                   width: 92, height: 22)
            cg.setFillColor(mint.withAlphaComponent(0.18).cgColor)
            cg.addPath(UIBezierPath(roundedRect: badgeRect, cornerRadius: 11).cgPath)
            cg.fillPath()
            drawCentered("SIGNED", in: badgeRect,
                         font: .systemFont(ofSize: 10, weight: .heavy),
                         color: mint, kern: 1.4)
        }

        drawFooter(cg, page: 5, proposal: p)
    }

    // MARK: Primitives

    private static func drawHeader(_ cg: CGContext, title: String) {
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 80)
        cg.setFillColor(canvas.cgColor)
        cg.fill(band)
        cg.setFillColor(ember.cgColor)
        cg.fill(CGRect(x: 0, y: band.maxY, width: pageSize.width, height: 2))
        draw("ROOFWISE",
             at: CGPoint(x: margin, y: 26),
             font: .systemFont(ofSize: 11, weight: .heavy), color: ember, kern: 2.4)
        draw(title,
             at: CGPoint(x: margin, y: 42),
             font: .systemFont(ofSize: 16, weight: .heavy), color: ink)
    }

    private static func drawFooter(_ cg: CGContext, page: Int, proposal p: Proposal) {
        let y = pageSize.height - 32
        cg.setFillColor(hairline.cgColor)
        cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.6))
        draw("RoofWise · Proposal · \(p.originJobId) · Page \(page)",
             at: CGPoint(x: margin, y: y + 8),
             font: .systemFont(ofSize: 8, weight: .semibold), color: inkFaint, kern: 0.4)
    }

    private static func drawCard(_ cg: CGContext, rect: CGRect, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        cg.saveGState()
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
        guard let g = CGGradient(colorsSpace: cs,
                                 colors: colors.map { $0.cgColor } as CFArray,
                                 locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(g,
                              start: CGPoint(x: rect.minX, y: rect.minY),
                              end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        cg.restoreGState()
    }

    private static func draw(_ text: String, at p: CGPoint,
                             font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        text.draw(at: p, withAttributes: attrs)
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
        text.draw(at: CGPoint(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2),
                  withAttributes: attrs)
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

    private static func showOrDash(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : s
    }

    private static func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
