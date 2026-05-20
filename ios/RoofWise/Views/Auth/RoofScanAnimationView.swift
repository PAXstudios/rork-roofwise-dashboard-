import SwiftUI

/// Futuristic animated background: a wireframe roof being scanned for damage.
/// Uses TimelineView for continuous animation without driving state updates.
struct RoofScanAnimationView: View {
    /// Detection hotspots in normalized roof-local coords (x: 0…1 across roof base, y: 0…1 down roof face).
    /// Each has a phase offset so they pulse at different times.
    private static let hotspots: [Hotspot] = [
        Hotspot(x: 0.22, y: 0.34, phase: 0.00, severity: .high),
        Hotspot(x: 0.48, y: 0.58, phase: 0.35, severity: .med),
        Hotspot(x: 0.71, y: 0.28, phase: 0.65, severity: .high),
        Hotspot(x: 0.36, y: 0.72, phase: 0.20, severity: .low),
        Hotspot(x: 0.82, y: 0.62, phase: 0.80, severity: .med),
        Hotspot(x: 0.15, y: 0.60, phase: 0.50, severity: .low),
        Hotspot(x: 0.60, y: 0.40, phase: 0.10, severity: .high),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    gridBackdrop(size: size, t: t)
                    roofWireframe(size: size, t: t)
                    scanBeam(size: size, t: t)
                    hotspotsLayer(size: size, t: t)
                    cornerBrackets(size: size)
                    hudReadout(size: size, t: t)
                }
                .drawingGroup()
                .compositingGroup()
                .blendMode(.plusLighter)
                .opacity(0.85)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Grid backdrop

    private func gridBackdrop(size: CGSize, t: TimeInterval) -> some View {
        Canvas { ctx, _ in
            let step: CGFloat = 36
            let drift = CGFloat(t.truncatingRemainder(dividingBy: Double(step))) * 1.2
            let color = Color.orange.opacity(0.08)
            var path = Path()
            var x: CGFloat = -step + drift.truncatingRemainder(dividingBy: step)
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = -step + drift.truncatingRemainder(dividingBy: step)
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(color), lineWidth: 0.5)
        }
    }

    // MARK: - Roof wireframe (isometric two-pitch roof)

    private struct RoofGeometry {
        let leftA: CGPoint   // ridge left
        let leftB: CGPoint   // ridge right
        let leftC: CGPoint   // eave right
        let leftD: CGPoint   // eave left
        let rightA: CGPoint
        let rightB: CGPoint
        let rightC: CGPoint
        let rightD: CGPoint
        let bounds: CGRect   // full roof bbox for hotspot mapping (front face)
    }

    private func computeRoof(size: CGSize) -> RoofGeometry {
        let cx = size.width / 2
        let cy = size.height * 0.58
        let halfW: CGFloat = min(size.width * 0.42, 230)
        let depth: CGFloat = halfW * 0.35
        let height: CGFloat = halfW * 0.55

        // Front (left) pitch — visible face
        let ridgeL = CGPoint(x: cx - halfW * 0.55, y: cy - height)
        let ridgeR = CGPoint(x: cx + halfW * 0.55, y: cy - height)
        let eaveL  = CGPoint(x: cx - halfW, y: cy)
        let eaveR  = CGPoint(x: cx + halfW, y: cy)

        // Back (right) pitch — perspective offset up-right
        let backL  = CGPoint(x: ridgeL.x + depth * 0.45, y: ridgeL.y - depth * 0.35)
        let backR  = CGPoint(x: ridgeR.x + depth * 0.45, y: ridgeR.y - depth * 0.35)
        let backEL = CGPoint(x: eaveL.x + depth * 0.45,  y: eaveL.y  - depth * 0.35)
        let backER = CGPoint(x: eaveR.x + depth * 0.45,  y: eaveR.y  - depth * 0.35)

        return RoofGeometry(
            leftA: ridgeL, leftB: ridgeR, leftC: eaveR, leftD: eaveL,
            rightA: backL, rightB: backR, rightC: backER, rightD: backEL,
            bounds: CGRect(x: eaveL.x, y: ridgeL.y, width: eaveR.x - eaveL.x, height: cy - ridgeL.y)
        )
    }

    private func roofWireframe(size: CGSize, t: TimeInterval) -> some View {
        let r = computeRoof(size: size)
        let pulse = 0.5 + 0.5 * sin(t * 1.2)
        return Canvas { ctx, _ in
            // Back pitch (dimmer)
            var back = Path()
            back.move(to: r.rightA)
            back.addLine(to: r.rightB)
            back.addLine(to: r.rightC)
            back.addLine(to: r.rightD)
            back.closeSubpath()
            ctx.fill(back, with: .color(.orange.opacity(0.05)))
            ctx.stroke(back, with: .color(.orange.opacity(0.35)), lineWidth: 0.8)

            // Front pitch fill (subtle warm glow)
            var face = Path()
            face.move(to: r.leftA)
            face.addLine(to: r.leftB)
            face.addLine(to: r.leftC)
            face.addLine(to: r.leftD)
            face.closeSubpath()
            ctx.fill(face, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.00, green: 0.42, blue: 0.18).opacity(0.18 + 0.05 * pulse),
                    Color(red: 0.91, green: 0.32, blue: 0.10).opacity(0.06)
                ]),
                startPoint: CGPoint(x: r.leftA.x, y: r.leftA.y),
                endPoint: CGPoint(x: r.leftC.x, y: r.leftC.y)
            ))
            ctx.stroke(face, with: .color(.orange.opacity(0.95)), lineWidth: 1.4)

            // Ridge connectors
            var ridge = Path()
            ridge.move(to: r.leftA); ridge.addLine(to: r.rightA)
            ridge.move(to: r.leftB); ridge.addLine(to: r.rightB)
            ridge.move(to: r.leftC); ridge.addLine(to: r.rightC)
            ridge.move(to: r.leftD); ridge.addLine(to: r.rightD)
            ctx.stroke(ridge, with: .color(.orange.opacity(0.45)), lineWidth: 0.8)

            // Shingle grid on front face — parallel rows + columns mapped to the trapezoid
            let rows = 7
            let cols = 10
            var shingles = Path()
            for i in 1..<rows {
                let f = CGFloat(i) / CGFloat(rows)
                let p1 = lerp(r.leftA, r.leftD, t: f)
                let p2 = lerp(r.leftB, r.leftC, t: f)
                shingles.move(to: p1); shingles.addLine(to: p2)
            }
            for j in 1..<cols {
                let f = CGFloat(j) / CGFloat(cols)
                let p1 = lerp(r.leftA, r.leftB, t: f)
                let p2 = lerp(r.leftD, r.leftC, t: f)
                shingles.move(to: p1); shingles.addLine(to: p2)
            }
            ctx.stroke(shingles, with: .color(.orange.opacity(0.28)), lineWidth: 0.5)
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: - Scan beam (sweeping line over the roof face)

    private func scanBeam(size: CGSize, t: TimeInterval) -> some View {
        let r = computeRoof(size: size)
        // Sweep position 0…1 with ease, period 3.6s
        let period: Double = 3.6
        let phase = (t.truncatingRemainder(dividingBy: period)) / period
        let s = CGFloat(phase)

        return Canvas { ctx, _ in
            // Beam line from leftA→leftD edge to leftB→leftC edge at fraction s
            let p1 = lerp(r.leftA, r.leftD, t: s)
            let p2 = lerp(r.leftB, r.leftC, t: s)

            // Glow band around the beam (faded above and below)
            let bandWidth: CGFloat = 28
            let dir = CGVector(dx: p2.x - p1.x, dy: p2.y - p1.y)
            let len = max(1, sqrt(dir.dx * dir.dx + dir.dy * dir.dy))
            let perp = CGVector(dx: -dir.dy / len, dy: dir.dx / len)

            var glow = Path()
            glow.move(to: CGPoint(x: p1.x + perp.dx * bandWidth, y: p1.y + perp.dy * bandWidth))
            glow.addLine(to: CGPoint(x: p2.x + perp.dx * bandWidth, y: p2.y + perp.dy * bandWidth))
            glow.addLine(to: CGPoint(x: p2.x - perp.dx * bandWidth, y: p2.y - perp.dy * bandWidth))
            glow.addLine(to: CGPoint(x: p1.x - perp.dx * bandWidth, y: p1.y - perp.dy * bandWidth))
            glow.closeSubpath()
            ctx.fill(glow, with: .linearGradient(
                Gradient(colors: [
                    Color.orange.opacity(0.0),
                    Color.orange.opacity(0.45),
                    Color.orange.opacity(0.0)
                ]),
                startPoint: CGPoint(x: p1.x + perp.dx * bandWidth, y: p1.y + perp.dy * bandWidth),
                endPoint: CGPoint(x: p1.x - perp.dx * bandWidth, y: p1.y - perp.dy * bandWidth)
            ))

            // Bright beam line
            var beam = Path()
            beam.move(to: p1); beam.addLine(to: p2)
            ctx.stroke(beam, with: .color(Color(red: 1.0, green: 0.78, blue: 0.45)), lineWidth: 2)

            // Endpoint nodes
            for p in [p1, p2] {
                let rect = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)))
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                         with: .color(.orange.opacity(0.35)))
            }
        }
    }

    // MARK: - Hotspots (detected damage markers, pulse independently)

    private struct Hotspot {
        let x: CGFloat
        let y: CGFloat
        let phase: Double
        let severity: Severity
        enum Severity { case low, med, high }
    }

    private func hotspotsLayer(size: CGSize, t: TimeInterval) -> some View {
        let r = computeRoof(size: size)
        // Sweep fraction matches scanBeam — only show hotspots once beam has passed them
        let period: Double = 3.6
        let phase = (t.truncatingRemainder(dividingBy: period)) / period
        let scanY = CGFloat(phase)

        return Canvas { ctx, _ in
            for h in Self.hotspots {
                // Map hotspot (h.x, h.y) onto roof trapezoid (bilinear)
                let top = lerp(r.leftA, r.leftB, t: h.x)
                let bot = lerp(r.leftD, r.leftC, t: h.x)
                let p = lerp(top, bot, t: h.y)

                // Reveal only after beam has passed; fade in/out smoothly
                let reveal = max(0, min(1, (scanY - h.y) * 6))
                let pulse = 0.5 + 0.5 * sin(t * 2.2 + h.phase * .pi * 2)
                let baseR: CGFloat
                let color: Color
                switch h.severity {
                case .high: baseR = 9;  color = Color(red: 1.0, green: 0.35, blue: 0.15)
                case .med:  baseR = 7;  color = Color(red: 1.0, green: 0.62, blue: 0.20)
                case .low:  baseR = 5;  color = Color(red: 1.0, green: 0.82, blue: 0.30)
                }
                let radius = baseR * (0.85 + 0.4 * CGFloat(pulse))
                let alpha = 0.85 * reveal

                // Halo
                let halo = CGRect(x: p.x - radius * 3, y: p.y - radius * 3,
                                  width: radius * 6, height: radius * 6)
                ctx.fill(Path(ellipseIn: halo),
                         with: .radialGradient(
                            Gradient(colors: [color.opacity(0.55 * alpha), .clear]),
                            center: CGPoint(x: p.x, y: p.y),
                            startRadius: 0,
                            endRadius: radius * 3))

                // Marker
                let dot = CGRect(x: p.x - radius, y: p.y - radius,
                                 width: radius * 2, height: radius * 2)
                ctx.stroke(Path(ellipseIn: dot.insetBy(dx: -3, dy: -3)),
                           with: .color(color.opacity(0.9 * alpha)),
                           lineWidth: 1)
                ctx.fill(Path(ellipseIn: dot), with: .color(color.opacity(alpha)))

                // Crosshair tick
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - radius - 4, y: p.y))
                cross.addLine(to: CGPoint(x: p.x - radius - 1, y: p.y))
                cross.move(to: CGPoint(x: p.x + radius + 1, y: p.y))
                cross.addLine(to: CGPoint(x: p.x + radius + 4, y: p.y))
                ctx.stroke(cross, with: .color(color.opacity(alpha)), lineWidth: 1)
            }
        }
    }

    // MARK: - HUD corner brackets

    private func cornerBrackets(size: CGSize) -> some View {
        Canvas { ctx, _ in
            let inset: CGFloat = 22
            let len: CGFloat = 28
            let color = GraphicsContext.Shading.color(.orange.opacity(0.55))
            let lw: CGFloat = 1.4

            func bracket(_ corner: CGPoint, dx: CGFloat, dy: CGFloat) {
                var p = Path()
                p.move(to: CGPoint(x: corner.x + dx * len, y: corner.y))
                p.addLine(to: corner)
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * len))
                ctx.stroke(p, with: color, lineWidth: lw)
            }
            bracket(CGPoint(x: inset, y: inset), dx: 1, dy: 1)
            bracket(CGPoint(x: size.width - inset, y: inset), dx: -1, dy: 1)
            bracket(CGPoint(x: inset, y: size.height - inset), dx: 1, dy: -1)
            bracket(CGPoint(x: size.width - inset, y: size.height - inset), dx: -1, dy: -1)
        }
    }

    // MARK: - HUD readout (faint scrolling text)

    private func hudReadout(size: CGSize, t: TimeInterval) -> some View {
        let progress = Int((t.truncatingRemainder(dividingBy: 3.6) / 3.6) * 100)
        let detected = 3 + Int(t.truncatingRemainder(dividingBy: 7)) % 5
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .opacity(0.6 + 0.4 * sin(t * 4))
                Text("SCAN \(String(format: "%02d", progress))%")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
            }
            Text("DAMAGE NODES · \(detected)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.orange.opacity(0.55))
        }
        .padding(.leading, 30)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ZStack {
        Color.black
        RoofScanAnimationView()
    }
    .ignoresSafeArea()
}
