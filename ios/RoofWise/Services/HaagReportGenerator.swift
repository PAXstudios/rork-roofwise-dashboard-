import UIKit
import PDFKit

/// Generates a HAAG-compliant insurance-grade PDF report from an
/// `Inspection`. Pure: takes data in, returns PDF bytes (or writes
/// them to disk). Uses Apple PDFKit + UIGraphicsPDFRenderer only.
///
/// US Letter @ 72 dpi: 612×792. Margins: 0.5" = 36pt on every side.
nonisolated enum HaagReportGenerator {

    // MARK: Page geometry

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // MARK: Theme (UIColor mirrors of Theme.swift tokens)

    private static let ink       = UIColor(red: 0.058, green: 0.106, blue: 0.231, alpha: 1)
    private static let inkSoft   = UIColor(red: 0.27,  green: 0.32,  blue: 0.43,  alpha: 1)
    private static let inkFaint  = UIColor(red: 0.55,  green: 0.59,  blue: 0.67,  alpha: 1)
    private static let canvas    = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    private static let hairline  = UIColor(red: 0.91,  green: 0.90,  blue: 0.88,  alpha: 1)
    private static let ember     = UIColor(red: 1.00,  green: 0.42,  blue: 0.18,  alpha: 1)
    private static let emberDeep = UIColor(red: 0.91,  green: 0.32,  blue: 0.10,  alpha: 1)
    private static let emberSoft = UIColor(red: 1.00,  green: 0.93,  blue: 0.88,  alpha: 1)
    private static let mint      = UIColor(red: 0.18,  green: 0.70,  blue: 0.50,  alpha: 1)
    private static let mintSoft  = UIColor(red: 0.88,  green: 0.97,  blue: 0.92,  alpha: 1)
    private static let amber     = UIColor(red: 0.97,  green: 0.74,  blue: 0.21,  alpha: 1)
    private static let amberSoft = UIColor(red: 1.00,  green: 0.96,  blue: 0.86,  alpha: 1)
    private static let crimson   = UIColor(red: 0.86,  green: 0.22,  blue: 0.31,  alpha: 1)

    // MARK: Public API

    /// Generates the report and returns the raw PDF data. Pass the captured
    /// slope photos to embed a photo-documentation section.
    static func generate(inspection: Inspection, photos: [CapturedPhoto] = []) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String:  "HAAG Roof Inspection Report — \(inspection.job.reportId)",
            kCGPDFContextAuthor as String: inspection.job.companyName.isEmpty
                ? "RoofWise" : inspection.job.companyName
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )

        // Single source of truth for every verdict in the report: the rigorous,
        // published-threshold HAAG engine. The cover/weather/roof pages are
        // descriptive; everything downstream reads from this decision.
        let decision = HaagDecisionEngine.evaluate(.from(inspection))

        return renderer.pdfData { ctx in
            drawCover(ctx, inspection)
            drawWeather(ctx, inspection)
            drawRoof(ctx, inspection)
            drawSlopes(ctx, inspection, decision)
            drawPhotoDocumentation(ctx, inspection, photos)
            drawCollateral(ctx, inspection)
            drawSummary(ctx, inspection, decision)
            drawNarrative(ctx, inspection, decision)
            drawHomeownerSummary(ctx, inspection, decision)
            drawSignatures(ctx, inspection)
        }
    }

    /// Generates and writes the PDF to the documents directory as
    /// `<report_id>.pdf`. Returns the file URL on success.
    @discardableResult
    static func write(inspection: Inspection, photos: [CapturedPhoto] = []) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        let url = docs.appendingPathComponent("\(inspection.job.reportId).pdf")
        do {
            try generate(inspection: inspection, photos: photos).write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Page: COVER

    private static func drawCover(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection) {
        ctx.beginPage()
        let cg = ctx.cgContext

        // Brand band
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 160)
        drawGradient(cg, rect: band, colors: [ember, emberDeep])
        drawLogo(cg, origin: CGPoint(x: margin, y: 44), size: 40)
        draw("ROOFWISE",
             at: CGPoint(x: margin + 54, y: 50),
             font: .systemFont(ofSize: 18, weight: .heavy),
             color: .white, kern: 3.0)
        draw("HAAG-Compliant Forensic Roof Inspection",
             at: CGPoint(x: margin + 54, y: 74),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: UIColor.white.withAlphaComponent(0.9))

        let dateFmt = DateFormatter(); dateFmt.dateStyle = .long
        drawRight("INSPECTION REPORT",
                  origin: CGPoint(x: pageSize.width - margin, y: 50),
                  font: .systemFont(ofSize: 10, weight: .heavy),
                  color: UIColor.white.withAlphaComponent(0.85), kern: 2.0)
        drawRight(insp.job.reportId,
                  origin: CGPoint(x: pageSize.width - margin, y: 68),
                  font: .systemFont(ofSize: 17, weight: .heavy),
                  color: .white)
        drawRight("Report date: \(dateFmt.string(from: insp.job.reportDate))",
                  origin: CGPoint(x: pageSize.width - margin, y: 96),
                  font: .systemFont(ofSize: 11, weight: .semibold),
                  color: UIColor.white.withAlphaComponent(0.9))

        // Hero — client + property
        var y: CGFloat = 200
        let heroRect = CGRect(x: margin, y: y, width: contentWidth, height: 110)
        drawCard(cg, rect: heroRect, fill: .white)
        draw("PROPERTY",
             at: CGPoint(x: heroRect.minX + 18, y: heroRect.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: inkFaint, kern: 1.4)
        draw(showOrDash(insp.job.clientName),
             at: CGPoint(x: heroRect.minX + 18, y: heroRect.minY + 30),
             font: .systemFont(ofSize: 22, weight: .heavy),
             color: ink)
        draw(showOrDash(insp.job.propertyAddress),
             at: CGPoint(x: heroRect.minX + 18, y: heroRect.minY + 64),
             font: .systemFont(ofSize: 13, weight: .semibold),
             color: inkSoft)
        y = heroRect.maxY + 16

        // Two-column meta block — inspection / claim
        let metaRect = CGRect(x: margin, y: y, width: contentWidth, height: 200)
        drawCard(cg, rect: metaRect, fill: .white)
        let leftX = metaRect.minX + 18
        let rightX = metaRect.minX + metaRect.width / 2 + 4
        drawLabelValue("Inspection date",
                       insp.job.inspectionDate.formatted(date: .abbreviated, time: .omitted),
                       origin: CGPoint(x: leftX, y: metaRect.minY + 18))
        drawLabelValue("Inspector",
                       showOrDash(insp.job.inspectorName),
                       origin: CGPoint(x: leftX, y: metaRect.minY + 56))
        drawLabelValue("Company",
                       showOrDash(insp.job.companyName),
                       origin: CGPoint(x: leftX, y: metaRect.minY + 94))
        drawLabelValue("Client",
                       showOrDash(insp.job.clientName),
                       origin: CGPoint(x: leftX, y: metaRect.minY + 132))

        drawLabelValue("Carrier",
                       showOrDash(insp.job.carrierName),
                       origin: CGPoint(x: rightX, y: metaRect.minY + 18))
        drawLabelValue("Policy #",
                       showOrDash(insp.job.policyNumber),
                       origin: CGPoint(x: rightX, y: metaRect.minY + 56))
        drawLabelValue("Claim #",
                       showOrDash(insp.job.claimNumber),
                       origin: CGPoint(x: rightX, y: metaRect.minY + 94))
        drawLabelValue("Report #",
                       insp.job.reportId,
                       origin: CGPoint(x: rightX, y: metaRect.minY + 132))

        // Footer
        drawFooter(cg, page: 1, reportId: insp.job.reportId)
    }

    // MARK: - Page: WEATHER VERIFICATION

    private static func drawWeather(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Weather Verification",
                   subtitle: "Storm corroboration · third-party sources")
        var y: CGFloat = 130

        let card = CGRect(x: margin, y: y, width: contentWidth, height: 220)
        drawCard(ctx.cgContext, rect: card, fill: .white)

        let leftX = card.minX + 18
        let rightX = card.minX + card.width / 2 + 4
        let dateStr = insp.event.eventDate
            .map { $0.formatted(date: .long, time: .omitted) } ?? "—"

        drawLabelValue("Event date", dateStr,
                       origin: CGPoint(x: leftX, y: card.minY + 18))
        drawLabelValue("Hail reported",
                       insp.event.hasHail ? "Yes" : "No",
                       origin: CGPoint(x: leftX, y: card.minY + 60))
        drawLabelValue("Wind reported",
                       insp.event.hasWind ? "Yes" : "No",
                       origin: CGPoint(x: leftX, y: card.minY + 102))

        drawLabelValue("Max hail size",
                       insp.event.hailMaxSizeIn.map { String(format: "%.2f in", $0) } ?? "—",
                       origin: CGPoint(x: rightX, y: card.minY + 18))
        drawLabelValue("Max wind gust",
                       insp.event.windMaxGustMph.map { "\(Int($0.rounded())) mph" } ?? "—",
                       origin: CGPoint(x: rightX, y: card.minY + 60))
        drawLabelValue("Sources",
                       insp.event.weatherSources.isEmpty
                          ? "—" : insp.event.weatherSources.joined(separator: ", "),
                       origin: CGPoint(x: rightX, y: card.minY + 102))

        // Footnote
        drawWrapped("Reported figures are corroborated against publicly available NOAA storm reports and at least one secondary commercial weather source where available. Absent corroboration is shown as “—”.",
                    rect: CGRect(x: card.minX + 18,
                                 y: card.minY + 156,
                                 width: card.width - 36,
                                 height: 50),
                    font: .systemFont(ofSize: 10, weight: .regular),
                    color: inkSoft, lineSpacing: 3)

        drawFooter(ctx.cgContext, page: 2, reportId: insp.job.reportId)
    }

    // MARK: - Page: ROOF SYSTEM

    private static func drawRoof(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Roof System",
                   subtitle: "Pre-storm baseline characterization")
        var y: CGFloat = 130

        let card = CGRect(x: margin, y: y, width: contentWidth, height: 200)
        drawCard(ctx.cgContext, rect: card, fill: .white)
        let leftX = card.minX + 18
        let rightX = card.minX + card.width / 2 + 4
        drawLabelValue("Primary material",
                       insp.roof.primaryMaterial.displayName,
                       origin: CGPoint(x: leftX, y: card.minY + 18))
        drawLabelValue("Estimated age",
                       "\(insp.roof.estimatedAgeYears) yr",
                       origin: CGPoint(x: leftX, y: card.minY + 60))
        drawLabelValue("Layers",
                       "\(insp.roof.layers)",
                       origin: CGPoint(x: leftX, y: card.minY + 102))

        drawLabelValue("Geometry",
                       insp.roof.geometry.displayName,
                       origin: CGPoint(x: rightX, y: card.minY + 18))
        drawLabelValue("Pre-storm condition",
                       insp.roof.overallConditionPreStorm.displayName,
                       origin: CGPoint(x: rightX, y: card.minY + 60))
        drawLabelValue("Slopes inspected",
                       "\(insp.slopes.count)",
                       origin: CGPoint(x: rightX, y: card.minY + 102))

        drawFooter(ctx.cgContext, page: 3, reportId: insp.job.reportId)
    }

    // MARK: - Pages: SLOPE-BY-SLOPE FINDINGS

    private static func drawSlopes(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection, _ decision: HaagDecision) {
        let decisionsById: [String: HaagSlopeDecision] = Dictionary(
            decision.slopeDecisions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if insp.slopes.isEmpty {
            ctx.beginPage()
            drawHeader(ctx.cgContext,
                       title: "Slope-by-Slope Findings",
                       subtitle: "No slopes recorded")
            let r = CGRect(x: margin, y: 130, width: contentWidth, height: 80)
            drawCard(ctx.cgContext, rect: r, fill: .white)
            drawWrapped("No slopes were captured for this inspection.",
                        rect: CGRect(x: r.minX + 16, y: r.minY + 24,
                                     width: r.width - 32, height: r.height - 32),
                        font: .systemFont(ofSize: 11, weight: .regular),
                        color: inkSoft)
            drawFooter(ctx.cgContext, page: 4, reportId: insp.job.reportId)
            return
        }

        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Slope-by-Slope Findings",
                   subtitle: "\(insp.slopes.count) slopes")
        var y: CGFloat = 130
        var page = 4
        let blockHeight: CGFloat = 234

        for slope in insp.slopes {
            if y + blockHeight > pageSize.height - 60 {
                drawFooter(ctx.cgContext, page: page, reportId: insp.job.reportId)
                ctx.beginPage()
                page += 1
                drawHeader(ctx.cgContext,
                           title: "Slope-by-Slope Findings (cont.)",
                           subtitle: "")
                y = 130
            }
            drawSlopeBlock(ctx.cgContext,
                           rect: CGRect(x: margin, y: y, width: contentWidth, height: blockHeight),
                           slope: slope,
                           decision: decisionsById[slope.orientation])
            y += blockHeight + 12
        }

        drawFooter(ctx.cgContext, page: page, reportId: insp.job.reportId)
    }

    private static func drawSlopeBlock(_ cg: CGContext, rect: CGRect, slope: Slope, decision: HaagSlopeDecision?) {
        drawCard(cg, rect: rect, fill: .white)

        // Header line
        let header = "\(slope.orientation) Slope — "
            + "\(formatNumber(slope.areaSquares)) sq, "
            + "\(slope.pitchRiseOver12):12 pitch"
        draw(header,
             at: CGPoint(x: rect.minX + 18, y: rect.minY + 16),
             font: .systemFont(ofSize: 14, weight: .heavy),
             color: ink)

        // Damage table — 3 columns
        let tableY = rect.minY + 46
        let colW = (rect.width - 36) / 3
        let cols: [(title: String, color: UIColor, rows: [(String, String)])] = [
            ("HAIL", crimson, [
                ("Bruises",        "\(slope.damageTypes.hail.asphaltBruise)"),
                ("Mat fractures",  "\(slope.damageTypes.hail.asphaltMatFracture)"),
                ("Granule loss",   "\(slope.damageTypes.hail.asphaltGranuleLossExposed)")
            ]),
            ("WIND", amber, [
                ("Creased",        "\(slope.damageTypes.wind.shingleCrease)"),
                ("Missing",        "\(slope.damageTypes.wind.shingleMissing)"),
                ("Lifted/Unsealed","\(slope.damageTypes.wind.shingleLiftedUnsealed)")
            ]),
            ("WEAR", inkSoft, [
                ("Natural",        slope.damageTypes.wear.naturalWeathering ? "Yes" : "—"),
                ("Foot traffic",   slope.damageTypes.wear.footTraffic ? "Yes" : "—"),
                ("Manufacturing",  slope.damageTypes.wear.manufacturingDefect ? "Yes" : "—")
            ])
        ]

        for (i, col) in cols.enumerated() {
            let cx = rect.minX + 18 + CGFloat(i) * colW
            // header strip
            let stripRect = CGRect(x: cx, y: tableY, width: colW - 6, height: 22)
            cg.saveGState()
            cg.setFillColor(col.color.withAlphaComponent(0.12).cgColor)
            cg.addPath(UIBezierPath(roundedRect: stripRect, cornerRadius: 6).cgPath)
            cg.fillPath()
            cg.restoreGState()
            draw(col.title,
                 at: CGPoint(x: stripRect.minX + 8, y: stripRect.minY + 6),
                 font: .systemFont(ofSize: 9, weight: .heavy),
                 color: col.color, kern: 1.4)
            // rows
            for (j, row) in col.rows.enumerated() {
                let ry = stripRect.maxY + 6 + CGFloat(j) * 18
                draw(row.0,
                     at: CGPoint(x: stripRect.minX + 4, y: ry),
                     font: .systemFont(ofSize: 10, weight: .semibold),
                     color: inkSoft)
                drawRight(row.1,
                          origin: CGPoint(x: stripRect.maxX - 4, y: ry),
                          font: .systemFont(ofSize: 11, weight: .heavy),
                          color: ink)
            }
        }

        // Cost line
        let costY = tableY + 22 + 6 + 18 * 3 + 12
        let cost = "Cost: \(slope.damagedUnitsPerSquare) × "
            + currency(slope.unitRepairCost) + " × "
            + String(format: "%.2f", slope.repairDifficultyFactor) + " × "
            + formatNumber(slope.areaSquares) + " = "
            + currency(slope.repairCostSlope)
        draw(cost,
             at: CGPoint(x: rect.minX + 18, y: costY),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: inkSoft)
        draw("Replacement: \(currency(slope.replacementCostSlope))",
             at: CGPoint(x: rect.minX + 18, y: costY + 16),
             font: .systemFont(ofSize: 11, weight: .semibold),
             color: inkSoft)

        // HAAG threshold line — the exact rule that produced this verdict.
        if let d = decision {
            draw("HAAG: \(d.triggeredRule)",
                 at: CGPoint(x: rect.minX + 18, y: costY + 32),
                 font: .systemFont(ofSize: 10, weight: .heavy),
                 color: ink)
        }

        // Verdict pill at bottom
        let verdict = slopeVerdict(decision)
        let pillFont = UIFont.systemFont(ofSize: 11, weight: .heavy)
        let pillSize = textSize(verdict.title, font: pillFont, kern: 0.6)
        let pillRect = CGRect(x: rect.minX + 18,
                              y: rect.maxY - 32,
                              width: pillSize.width + 22,
                              height: 22)
        cg.saveGState()
        cg.setFillColor(verdict.color.withAlphaComponent(0.16).cgColor)
        cg.addPath(UIBezierPath(roundedRect: pillRect, cornerRadius: 11).cgPath)
        cg.fillPath()
        cg.restoreGState()
        drawCentered(verdict.title, in: pillRect,
                     font: pillFont, color: verdict.color, kern: 0.6)
    }

    private static func slopeVerdict(_ d: HaagSlopeDecision?) -> (title: String, color: UIColor) {
        switch d?.recommendation {
        case .replace:          return ("Slope Replacement Qualifies", crimson)
        case .repair:           return ("Repairs Recommended", amber)
        case .insufficientData: return ("Insufficient Sampling", inkFaint)
        case .noFunctionalDamage, .none: return ("No Functional Damage", mint)
        }
    }

    // MARK: - Pages: PHOTO DOCUMENTATION

    /// Embeds captured slope photos with their AI/inspector damage markers
    /// overlaid, grouped by slope. Skipped entirely when no photos exist so
    /// the report never shows a blank page.
    private static func drawPhotoDocumentation(_ ctx: UIGraphicsPDFRendererContext,
                                               _ insp: Inspection,
                                               _ photos: [CapturedPhoto]) {
        guard !photos.isEmpty else { return }

        // Group by slope, in the SlopeType declaration order.
        let grouped = Dictionary(grouping: photos, by: { $0.slope })
        let orderedSlopes = SlopeType.allCases.filter { grouped[$0] != nil }

        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Photo Documentation",
                   subtitle: "\(photos.count) photo\(photos.count == 1 ? "" : "s") · markers overlaid")
        var y: CGFloat = 130
        let cardHeight: CGFloat = 286

        for slope in orderedSlopes {
            let items = grouped[slope] ?? []

            // Slope subheading.
            if y + 30 > pageSize.height - 60 {
                drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
                ctx.beginPage()
                drawHeader(ctx.cgContext, title: "Photo Documentation (cont.)", subtitle: "")
                y = 130
            }
            draw(slope.shortName.uppercased(),
                 at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 11, weight: .heavy),
                 color: ember, kern: 1.6)
            y += 22

            for photo in items {
                if y + cardHeight > pageSize.height - 60 {
                    drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
                    ctx.beginPage()
                    drawHeader(ctx.cgContext, title: "Photo Documentation (cont.)", subtitle: "")
                    y = 130
                    draw(slope.shortName.uppercased(),
                         at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 11, weight: .heavy),
                         color: ember, kern: 1.6)
                    y += 22
                }
                drawPhotoCard(ctx.cgContext,
                              rect: CGRect(x: margin, y: y, width: contentWidth, height: cardHeight),
                              photo: photo)
                y += cardHeight + 14
            }
        }

        drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
    }

    private static func drawPhotoCard(_ cg: CGContext, rect: CGRect, photo: CapturedPhoto) {
        drawCard(cg, rect: rect, fill: .white)

        // Image surface (aspect-fit inside a fixed frame).
        let imgFrame = CGRect(x: rect.minX + 14, y: rect.minY + 14,
                              width: rect.width - 28, height: 200)
        cg.saveGState()
        cg.setFillColor(canvas.cgColor)
        let clip = UIBezierPath(roundedRect: imgFrame, cornerRadius: 10)
        cg.addPath(clip.cgPath)
        cg.fillPath()
        cg.addPath(clip.cgPath)
        cg.clip()

        let drawn = aspectFitRect(imageSize: photo.image.size, in: imgFrame)
        photo.image.draw(in: drawn)

        // Damage markers (normalized to the image; radius vs min image dim).
        for marker in photo.damageMarkers {
            let cx = drawn.minX + marker.x * drawn.width
            let cy = drawn.minY + marker.y * drawn.height
            let r = max(4, marker.radius * min(drawn.width, drawn.height))
            let color = markerColor(marker.type)
            let dot = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: dot)
            cg.setFillColor(color.withAlphaComponent(0.22).cgColor)
            cg.fillEllipse(in: dot)
        }
        cg.restoreGState()

        // Caption row.
        let capY = imgFrame.maxY + 12
        let modeLabel = photo.captureMode == .square ? "100 sq ft test square" : "Single-shingle close-up"
        draw(modeLabel,
             at: CGPoint(x: rect.minX + 16, y: capY),
             font: .systemFont(ofSize: 11, weight: .heavy),
             color: ink)
        drawRight("Pitch \(Int(photo.pitchDegrees.rounded()))° · \(Int(photo.elevationFeet.rounded())) ft",
                  origin: CGPoint(x: rect.maxX - 16, y: capY),
                  font: .systemFont(ofSize: 10, weight: .semibold),
                  color: inkSoft)

        // Findings / marker summary line.
        let summary: String = {
            let byType = photo.markersByType
            if !byType.isEmpty {
                return byType.map { "\($0.items.count) \($0.type.pluralDisplay)" }.joined(separator: " · ")
            }
            let top = photo.topDetectedFindings.prefix(3).map(\.display)
            return top.isEmpty ? "No damage markers recorded" : top.joined(separator: " · ")
        }()
        drawWrapped(summary,
                    rect: CGRect(x: rect.minX + 16, y: capY + 18,
                                 width: rect.width - 32, height: 34),
                    font: .systemFont(ofSize: 10, weight: .semibold),
                    color: inkSoft, lineSpacing: 2)
    }

    private static func aspectFitRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
    }

    /// PDF-local marker palette (mirrors the report theme, no Theme dependency
    /// so this stays a pure nonisolated drawing routine).
    private static func markerColor(_ type: DamageMarkerType) -> UIColor {
        switch type {
        case .hailHits, .bruising:                 return crimson
        case .windDamage, .windCreasing, .lifted:  return amber
        case .granuleLoss, .blistering:            return emberDeep
        case .cracking, .splitting:                return ember
        case .missingShingles, .structuralSagging: return UIColor(red: 0.55, green: 0.20, blue: 0.60, alpha: 1)
        case .flashing:                            return inkSoft
        case .algaeMoss:                           return mint
        case .other:                               return ember
        }
    }

    // MARK: - Page: COLLATERAL

    private static func drawCollateral(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Collateral Damage Checklist",
                   subtitle: "Corroborating evidence around the structure")
        var y: CGFloat = 130

        let items: [(String, Bool)] = [
            ("Gutter dents",            insp.collateral.gutterDents),
            ("Downspout dents",         insp.collateral.downspoutDents),
            ("Window screen damage",    insp.collateral.screenDamage),
            ("Siding impacts",          insp.collateral.sidingImpacts),
            ("Vehicle damage reported", insp.collateral.vehicleDamageReported)
        ]

        for (label, checked) in items {
            let row = CGRect(x: margin, y: y, width: contentWidth, height: 44)
            drawCard(ctx.cgContext, rect: row, fill: .white)
            // checkbox
            let box = CGRect(x: row.minX + 14, y: row.midY - 10, width: 20, height: 20)
            ctx.cgContext.saveGState()
            ctx.cgContext.setStrokeColor((checked ? mint : inkFaint).cgColor)
            ctx.cgContext.setLineWidth(1.5)
            ctx.cgContext.addPath(UIBezierPath(roundedRect: box, cornerRadius: 5).cgPath)
            ctx.cgContext.strokePath()
            if checked {
                ctx.cgContext.setFillColor(mint.withAlphaComponent(0.18).cgColor)
                ctx.cgContext.addPath(UIBezierPath(roundedRect: box, cornerRadius: 5).cgPath)
                ctx.cgContext.fillPath()
                drawCentered("✓", in: box,
                             font: .systemFont(ofSize: 14, weight: .heavy),
                             color: mint)
            }
            ctx.cgContext.restoreGState()
            draw(label,
                 at: CGPoint(x: box.maxX + 12, y: row.midY - 7),
                 font: .systemFont(ofSize: 13, weight: .heavy),
                 color: ink)
            drawRight(checked ? "OBSERVED" : "NOT OBSERVED",
                      origin: CGPoint(x: row.maxX - 14, y: row.midY - 5),
                      font: .systemFont(ofSize: 9, weight: .heavy),
                      color: checked ? mint : inkFaint, kern: 1.2)
            y += 50
        }

        drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
    }

    // MARK: - Page: SUMMARY & RECOMMENDATION

    private static func drawSummary(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection, _ decision: HaagDecision) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Summary & Recommendation",
                   subtitle: "Roof-level HAAG decision")

        let cg = ctx.cgContext
        let verdict = roofVerdict(decision.overallRecommendation)
        let totals = decision.totals
        var y: CGFloat = 130

        // Big colored callout
        let callout = CGRect(x: margin, y: y, width: contentWidth, height: 110)
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: callout, cornerRadius: 16).cgPath)
        cg.clip()
        drawGradient(cg, rect: callout,
                     colors: [verdict.color, verdict.color.withAlphaComponent(0.78)])
        cg.restoreGState()
        draw("RECOMMENDATION",
             at: CGPoint(x: callout.minX + 18, y: callout.minY + 16),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: UIColor.white.withAlphaComponent(0.9), kern: 1.6)
        draw(verdict.title,
             at: CGPoint(x: callout.minX + 18, y: callout.minY + 32),
             font: .systemFont(ofSize: 22, weight: .heavy),
             color: .white)
        let qualifyingNames = decision.slopeDecisions
            .filter { $0.recommendation == .replace }
            .map(\.name)
            .joined(separator: ", ")
        if !qualifyingNames.isEmpty {
            draw("Qualifying slopes: \(qualifyingNames)",
                 at: CGPoint(x: callout.minX + 18, y: callout.minY + 70),
                 font: .systemFont(ofSize: 12, weight: .semibold),
                 color: UIColor.white.withAlphaComponent(0.95))
        }
        y = callout.maxY + 16

        // HAAG evidence + counts card — the auditable basis for the verdict.
        let stats = CGRect(x: margin, y: y, width: contentWidth, height: 130)
        drawCard(cg, rect: stats, fill: .white)
        let leftX = stats.minX + 18
        let rightX = stats.minX + stats.width / 2 + 4
        drawLabelValue("Evidence quality",
                       decision.evidenceQuality.rawValue.capitalized,
                       origin: CGPoint(x: leftX, y: stats.minY + 18))
        drawLabelValue("Slopes qualifying",
                       "\(totals.slopesReplaceQualifying) of \(totals.slopesEvaluated)",
                       origin: CGPoint(x: leftX, y: stats.minY + 60))
        drawLabelValue("Test squares",
                       formatNumber(totals.testSquaresPhotographed),
                       origin: CGPoint(x: leftX, y: stats.minY + 102))
        drawLabelValue("Functional hits",
                       "\(totals.totalFunctionalHits)",
                       origin: CGPoint(x: rightX, y: stats.minY + 18))
        drawLabelValue("Weighted hits / square",
                       String(format: "%.1f", totals.weightedHitsPerSquare),
                       origin: CGPoint(x: rightX, y: stats.minY + 60))
        drawLabelValue("Perils",
                       perilSummary(decision.perils),
                       origin: CGPoint(x: rightX, y: stats.minY + 102))
        y = stats.maxY + 16

        // Threshold rule text.
        let ruleRect = CGRect(x: margin, y: y, width: contentWidth, height: 64)
        drawCard(cg, rect: ruleRect, fill: canvas)
        draw("THRESHOLD APPLIED",
             at: CGPoint(x: ruleRect.minX + 18, y: ruleRect.minY + 14),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: inkFaint, kern: 1.4)
        drawWrapped(decision.roofCovering.ruleText,
                    rect: CGRect(x: ruleRect.minX + 18, y: ruleRect.minY + 28,
                                 width: ruleRect.width - 36, height: ruleRect.height - 34),
                    font: .systemFont(ofSize: 11, weight: .semibold),
                    color: inkSoft, lineSpacing: 2)
        y = ruleRect.maxY + 16

        // Triggered overrides (if any).
        if !decision.triggeredOverrides.isEmpty {
            let oh: CGFloat = 30 + CGFloat(decision.triggeredOverrides.count) * 32
            let oRect = CGRect(x: margin, y: y, width: contentWidth, height: oh)
            drawCard(cg, rect: oRect, fill: emberSoft)
            draw("OVERRIDES TRIGGERED",
                 at: CGPoint(x: oRect.minX + 18, y: oRect.minY + 12),
                 font: .systemFont(ofSize: 9, weight: .heavy),
                 color: emberDeep, kern: 1.4)
            var oy = oRect.minY + 30
            for o in decision.triggeredOverrides {
                drawWrapped("\u{2022} \(o.rationale)",
                            rect: CGRect(x: oRect.minX + 18, y: oy,
                                         width: oRect.width - 36, height: 30),
                            font: .systemFont(ofSize: 10, weight: .semibold),
                            color: ink, lineSpacing: 1)
                oy += 32
            }
            y = oRect.maxY + 16
        }

        // Notes (if any)
        if !insp.summary.notes.isEmpty {
            let notes = CGRect(x: margin, y: y, width: contentWidth, height: 90)
            drawCard(cg, rect: notes, fill: canvas)
            draw("INSPECTOR NOTES",
                 at: CGPoint(x: notes.minX + 18, y: notes.minY + 16),
                 font: .systemFont(ofSize: 9, weight: .heavy),
                 color: inkFaint, kern: 1.4)
            drawWrapped(insp.summary.notes,
                        rect: CGRect(x: notes.minX + 18, y: notes.minY + 32,
                                     width: notes.width - 36, height: notes.height - 40),
                        font: .systemFont(ofSize: 11, weight: .regular),
                        color: inkSoft, lineSpacing: 3)
        }

        drawFooter(cg, page: 0, reportId: insp.job.reportId)
    }

    private static func roofVerdict(_ rec: HaagRecommendation) -> (title: String, color: UIColor) {
        switch rec {
        case .fullReplacement:    return ("Full Replacement Supported", crimson)
        case .partialReplacement: return ("Partial Replacement Supported", ember)
        case .repair:             return ("Repairs Recommended", amber)
        case .insufficientData:   return ("Insufficient Evidence", inkFaint)
        case .noFunctionalDamage: return ("No Functional Damage", mint)
        }
    }

    private static func perilSummary(_ perils: [HaagPeril]) -> String {
        if perils.contains(.combinedHailWind) { return "Hail + Wind" }
        if perils.contains(.hail) && perils.contains(.wind) { return "Hail + Wind" }
        if perils.contains(.hail) { return "Hail" }
        if perils.contains(.wind) { return "Wind" }
        if perils.contains(.wear) { return "Wear" }
        return "\u{2014}"
    }

    // MARK: - Page: INSURANCE-GRADE NARRATIVE

    private static func drawNarrative(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection, _ decision: HaagDecision) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Insurance-Grade Narrative",
                   subtitle: "HAAG threshold reasoning")

        let body = buildNarrative(insp, decision)
        let card = CGRect(x: margin, y: 130, width: contentWidth, height: pageSize.height - 130 - 80)
        drawCard(ctx.cgContext, rect: card, fill: .white)
        drawWrapped(body,
                    rect: CGRect(x: card.minX + 20, y: card.minY + 20,
                                 width: card.width - 40, height: card.height - 40),
                    font: .systemFont(ofSize: 11, weight: .regular),
                    color: ink, lineSpacing: 4)

        drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
    }

    private static func buildNarrative(_ insp: Inspection, _ decision: HaagDecision) -> String {
        var parts: [String] = []
        let mat = insp.roof.primaryMaterial.displayName
        let layers = insp.roof.layers
        let cond = insp.roof.overallConditionPreStorm.displayName.lowercased()
        let total = insp.slopes.count

        parts.append("This forensic inspection was performed on \(insp.job.inspectionDate.formatted(date: .long, time: .omitted)) at \(showOrDash(insp.job.propertyAddress)), assessing a \(mat.lowercased()) roof system in \(cond) pre-storm condition with \(layers) layer\(layers == 1 ? "" : "s") covering \(total) slope\(total == 1 ? "" : "s").")

        if let date = insp.event.eventDate {
            var weather = "The reported loss event of \(date.formatted(date: .long, time: .omitted)) was corroborated"
            if let h = insp.event.hailMaxSizeIn { weather += " with measured hail to \(String(format: "%.2f", h)) inches" }
            if let w = insp.event.windMaxGustMph { weather += " and wind gusts to \(Int(w.rounded())) mph" }
            if !insp.event.weatherSources.isEmpty {
                weather += " across \(insp.event.weatherSources.joined(separator: ", "))"
            }
            weather += "."
            parts.append(weather)
        } else {
            parts.append("No specific loss-event date was provided; weather corroboration data is therefore not enumerated in this section.")
        }

        // Methodology + governing threshold straight from the engine.
        parts.append("Each accessible slope was evaluated against a 100 sq ft (10 ft \u{00D7} 10 ft) HAAG test square. \(decision.roofCovering.ruleText) Evidence quality for this inspection is rated \(decision.evidenceQuality.rawValue) across \(formatNumber(decision.totals.testSquaresPhotographed)) test square(s), with \(decision.totals.totalFunctionalHits) functional hit(s) counted (\(String(format: "%.1f", decision.totals.weightedHitsPerSquare)) per square, weighted).")

        // Per-slope outcomes, citing the exact triggered rule.
        let reps = decision.slopeDecisions.filter { $0.recommendation == .replace }
        let repairs = decision.slopeDecisions.filter { $0.recommendation == .repair }
        if !reps.isEmpty {
            let lines = reps.map { "\($0.name): \($0.triggeredRule)" }.joined(separator: "; ")
            parts.append("HAAG replacement thresholds were met on the following slope\(reps.count == 1 ? "" : "s") \u{2014} \(lines). On these slopes, repair-in-kind is not feasible because individual units cannot be matched without breaking adjacent factory seals, and partial replacement of contiguous courses would compromise the wind-resistance of surrounding material. Slope-level replacement is the supportable corrective action.")
        }
        if !repairs.isEmpty {
            let lines = repairs.map { "\($0.name): \($0.triggeredRule)" }.joined(separator: "; ")
            parts.append("Functional damage below the slope-replacement threshold was documented on \(lines). Spot repairs are technically feasible, subject to unit availability and matching, and represent the least-invasive corrective action.")
        }
        if reps.isEmpty && repairs.isEmpty {
            parts.append("No slope met HAAG thresholds for functional damage. Observed conditions are consistent with cosmetic wear or ordinary aging and do not warrant storm-related repair or replacement at this time.")
        }

        // Overrides, verbatim from the engine's rationale.
        for o in decision.triggeredOverrides {
            parts.append(o.rationale)
        }

        parts.append("Roof-level conclusion: \(decision.summary)")
        parts.append("This report was prepared in conformance with HAAG Engineering inspection methodology (engine v\(decision.engineVersion)) and is intended to support a good-faith insurance claim determination.")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Page: HOMEOWNER-FRIENDLY SUMMARY

    private static func drawHomeownerSummary(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection, _ decision: HaagDecision) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Homeowner Summary",
                   subtitle: "Plain-English overview")

        let body = buildHomeownerText(insp, decision)
        let card = CGRect(x: margin, y: 130, width: contentWidth, height: pageSize.height - 130 - 80)
        drawCard(ctx.cgContext, rect: card, fill: .white)
        drawWrapped(body,
                    rect: CGRect(x: card.minX + 20, y: card.minY + 20,
                                 width: card.width - 40, height: card.height - 40),
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: ink, lineSpacing: 4)

        drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
    }

    private static func buildHomeownerText(_ insp: Inspection, _ decision: HaagDecision) -> String {
        var parts: [String] = []
        let name = insp.job.clientName.isEmpty ? "you" : insp.job.clientName
        parts.append("Hi \(name) — here's what we found on your roof in plain English.")

        let qualifyingNames = decision.slopeDecisions
            .filter { $0.recommendation == .replace }
            .map(\.name)
            .joined(separator: ", ")
        switch decision.overallRecommendation {
        case .fullReplacement:
            parts.append("Your roof needs a full replacement. We found enough storm damage on enough faces of your roof that fixing individual spots wouldn't last and wouldn't be safe. Replacing the whole roof is the right call.")
        case .partialReplacement:
            let list = qualifyingNames.isEmpty ? "the affected sides" : qualifyingNames
            parts.append("Some sides of your roof need to be replaced — specifically \(list). Other sides are still in good shape and can stay.")
        case .repair:
            parts.append("We found some storm damage but it can be repaired in place. We don't recommend a full replacement at this time.")
        case .insufficientData:
            parts.append("We need a few more close-up photos of each side of your roof before we can give you a final answer. We'll schedule a quick follow-up to finish documenting it.")
        case .noFunctionalDamage:
            parts.append("Good news — we didn't find storm damage that requires repair or replacement. Your roof looks healthy.")
        }

        if insp.event.hasHail || insp.event.hasWind {
            var w = "We confirmed the storm event"
            if let d = insp.event.eventDate { w += " on \(d.formatted(date: .long, time: .omitted))" }
            if let h = insp.event.hailMaxSizeIn { w += " with hail up to \(String(format: "%.2f", h))\" " }
            if let mph = insp.event.windMaxGustMph { w += "and winds up to \(Int(mph.rounded())) mph" }
            w += " using public weather data, so the insurance carrier can verify it independently."
            parts.append(w)
        }

        let hasFunctional = decision.overallRecommendation == .fullReplacement
            || decision.overallRecommendation == .partialReplacement
            || decision.overallRecommendation == .repair
        if insp.roof.layers >= 2 && hasFunctional {
            parts.append("Because your roof already has \(insp.roof.layers) layers, building code won't let us add another. That's why we're recommending a tear-off rather than another patch.")
        }

        parts.append("If you have any questions about this report, just call your inspector. We'll walk you through every page line-by-line.")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Page: SIGNATURES

    private static func drawSignatures(_ ctx: UIGraphicsPDFRendererContext, _ insp: Inspection) {
        ctx.beginPage()
        drawHeader(ctx.cgContext,
                   title: "Sign-off",
                   subtitle: "Inspector & Homeowner")
        var y: CGFloat = 140

        drawSignatureBlock(ctx.cgContext,
                           rect: CGRect(x: margin, y: y, width: contentWidth, height: 200),
                           title: "Inspector",
                           name: insp.job.inspectorName,
                           date: insp.job.inspectionDate,
                           signaturePng: insp.inspectorSignaturePng)
        y += 220

        drawSignatureBlock(ctx.cgContext,
                           rect: CGRect(x: margin, y: y, width: contentWidth, height: 200),
                           title: "Homeowner",
                           name: insp.job.clientName,
                           date: insp.job.inspectionDate,
                           signaturePng: insp.homeownerSignaturePng)

        drawFooter(ctx.cgContext, page: 0, reportId: insp.job.reportId)
    }

    private static func drawSignatureBlock(_ cg: CGContext,
                                           rect: CGRect,
                                           title: String,
                                           name: String,
                                           date: Date,
                                           signaturePng: Data?) {
        drawCard(cg, rect: rect, fill: .white)
        draw(title.uppercased(),
             at: CGPoint(x: rect.minX + 18, y: rect.minY + 14),
             font: .systemFont(ofSize: 9, weight: .heavy),
             color: inkFaint, kern: 1.4)

        // Signature surface
        let sigRect = CGRect(x: rect.minX + 18, y: rect.minY + 36,
                             width: rect.width - 36, height: 110)
        cg.saveGState()
        cg.setFillColor(canvas.cgColor)
        cg.addPath(UIBezierPath(roundedRect: sigRect, cornerRadius: 10).cgPath)
        cg.fillPath()
        cg.restoreGState()
        if let data = signaturePng, let img = UIImage(data: data) {
            let inset = sigRect.insetBy(dx: 8, dy: 8)
            let imgSize = img.size
            if imgSize.width > 0, imgSize.height > 0 {
                let scale = min(inset.width / imgSize.width, inset.height / imgSize.height)
                let drawW = imgSize.width * scale
                let drawH = imgSize.height * scale
                let drawX = inset.midX - drawW / 2
                let drawY = inset.midY - drawH / 2
                img.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
            }
        } else {
            // X line — empty signature
            cg.saveGState()
            cg.setStrokeColor(hairline.cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: sigRect.minX + 16, y: sigRect.maxY - 16))
            cg.addLine(to: CGPoint(x: sigRect.maxX - 16, y: sigRect.maxY - 16))
            cg.strokePath()
            cg.restoreGState()
            draw("Signature",
                 at: CGPoint(x: sigRect.minX + 16, y: sigRect.maxY - 12),
                 font: .systemFont(ofSize: 9, weight: .semibold),
                 color: inkFaint)
        }

        // Name + date row
        let lineY = rect.minY + 158
        // name line
        cg.saveGState()
        cg.setStrokeColor(hairline.cgColor)
        cg.setLineWidth(0.6)
        cg.move(to: CGPoint(x: rect.minX + 18, y: lineY))
        cg.addLine(to: CGPoint(x: rect.minX + 18 + (rect.width - 36) * 0.65, y: lineY))
        cg.move(to: CGPoint(x: rect.minX + 18 + (rect.width - 36) * 0.7, y: lineY))
        cg.addLine(to: CGPoint(x: rect.maxX - 18, y: lineY))
        cg.strokePath()
        cg.restoreGState()
        draw(showOrDash(name),
             at: CGPoint(x: rect.minX + 18, y: lineY + 4),
             font: .systemFont(ofSize: 11, weight: .heavy),
             color: ink)
        draw("PRINTED NAME",
             at: CGPoint(x: rect.minX + 18, y: lineY + 22),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.2)
        draw(date.formatted(date: .abbreviated, time: .omitted),
             at: CGPoint(x: rect.minX + 18 + (rect.width - 36) * 0.7, y: lineY + 4),
             font: .systemFont(ofSize: 11, weight: .heavy),
             color: ink)
        draw("DATE",
             at: CGPoint(x: rect.minX + 18 + (rect.width - 36) * 0.7, y: lineY + 22),
             font: .systemFont(ofSize: 8, weight: .heavy),
             color: inkFaint, kern: 1.2)
    }

    // MARK: - Drawing primitives

    private static func drawHeader(_ cg: CGContext, title: String, subtitle: String) {
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 80)
        cg.setFillColor(canvas.cgColor)
        cg.fill(band)
        cg.setFillColor(ember.cgColor)
        cg.fill(CGRect(x: 0, y: band.maxY, width: pageSize.width, height: 2))

        drawLogo(cg, origin: CGPoint(x: margin, y: 26), size: 28)
        draw("ROOFWISE",
             at: CGPoint(x: margin + 38, y: 26),
             font: .systemFont(ofSize: 11, weight: .heavy),
             color: ember, kern: 2.4)
        draw(title,
             at: CGPoint(x: margin + 38, y: 42),
             font: .systemFont(ofSize: 16, weight: .heavy),
             color: ink)
        if !subtitle.isEmpty {
            drawRight(subtitle,
                      origin: CGPoint(x: pageSize.width - margin, y: 44),
                      font: .systemFont(ofSize: 10, weight: .semibold),
                      color: inkSoft)
        }
    }

    private static func drawFooter(_ cg: CGContext, page: Int, reportId: String) {
        let y = pageSize.height - 32
        cg.setFillColor(hairline.cgColor)
        cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.6))
        draw("RoofWise · HAAG-compliant inspection report · \(reportId)",
             at: CGPoint(x: margin, y: y + 8),
             font: .systemFont(ofSize: 8, weight: .semibold),
             color: inkFaint, kern: 0.4)
    }

    private static func drawLogo(_ cg: CGContext, origin: CGPoint, size: CGFloat) {
        // Try the bundled AppIcon image first; fall back to a vector mark.
        if let img = UIImage(named: "AppIcon") ?? UIImage(named: "icon") {
            cg.saveGState()
            let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.22)
            cg.addPath(path.cgPath)
            cg.clip()
            img.draw(in: rect)
            cg.restoreGState()
            return
        }
        // Vector fallback: stylized "house" mark.
        let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))
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
                              end: CGPoint(x: rect.maxX, y: rect.maxY),
                              options: [])
        cg.restoreGState()
    }

    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    private static func drawRight(_ text: String, origin: CGPoint,
                                  font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        text.draw(at: CGPoint(x: origin.x - size.width, y: origin.y),
                  withAttributes: attrs)
    }

    private static func drawCentered(_ text: String, in rect: CGRect,
                                     font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width / 2,
                        y: rect.midY - size.height / 2)
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
        draw(value, at: CGPoint(x: origin.x, y: origin.y + 12),
             font: .systemFont(ofSize: 13, weight: .heavy),
             color: ink)
    }

    private static func textSize(_ text: String, font: UIFont, kern: CGFloat = 0) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        return (text as NSString).size(withAttributes: attrs)
    }

    // MARK: - Format helpers

    private static func showOrDash(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : s
    }

    private static func formatNumber(_ d: Double) -> String {
        if d == d.rounded() { return String(format: "%.0f", d) }
        return String(format: "%.1f", d)
    }

    private static func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
