import SwiftUI

enum Theme {
    // MARK: Canonical brand palette (RoofWise spec — use these EXACT values).
    // Navy + burnt orange + cream + slate. No inline hex anywhere else.
    static let navy   = Color(red: 0.0471, green: 0.0941, blue: 0.2353)   // #0C183C
    static let orange = Color(red: 0.9882, green: 0.3765, blue: 0.0941)   // #FC6018
    static let cream  = Color(red: 0.9412, green: 0.9412, blue: 0.8941)   // #F0F0E4
    static let slate  = Color(red: 0.3294, green: 0.3765, blue: 0.4706)   // #546078

    // Legacy brand-token aliases — re-pointed to the canonical spec palette so the
    // whole app (which references these names ~1865×) adopts navy/orange/cream/slate
    // without touching every call site. Prefer the canonical names in new code.
    static let ink = navy                                                 // was #0F1B3B
    static let inkSoft = slate                                            // muted slate
    static let canvas = cream                                            // was ivory #F8F6F2
    static let ember = orange                                            // was #FF6B2E

    static let inkRaised = Color(red: 0.12, green: 0.20, blue: 0.42)      // navy gradient companion
    static let inkFaint = Color(red: 0.55, green: 0.59, blue: 0.67)
    static let scrim = Color.black.opacity(0.65)                          // photo overlay scrim
    static let card = Color.white
    static let hairline = Color(red: 0.91, green: 0.90, blue: 0.88)

    static let emberDeep = Color(red: 0.91, green: 0.32, blue: 0.10)
    static let emberSoft = Color(red: 1.00, green: 0.93, blue: 0.88)

    // MARK: Semantic status colors (severity / state).
    // NOTE: off the canonical 4-token palette; retained because they encode
    // severity + status semantics across many views. Slated for a Phase-3
    // palette-purity pass — see SPEC_AUDIT.md.
    static let mint = Color(red: 0.18, green: 0.70, blue: 0.50)
    static let mintSoft = Color(red: 0.88, green: 0.97, blue: 0.92)
    static let sky = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let skySoft = Color(red: 0.89, green: 0.94, blue: 1.00)
    static let amber = Color(red: 0.97, green: 0.74, blue: 0.21)
    static let amberSoft = Color(red: 1.00, green: 0.96, blue: 0.86)
    static let crimson = Color(red: 0.86, green: 0.22, blue: 0.31)

    // Map terrain
    static let mapLand = Color(red: 0.95, green: 0.94, blue: 0.91)
    static let mapBlock = Color(red: 0.92, green: 0.91, blue: 0.87)
    static let mapRoad = Color.white
    static let mapHighway = Color(red: 1.00, green: 0.86, blue: 0.55)
    static let mapWater = Color(red: 0.84, green: 0.92, blue: 0.96)
    static let mapPark = Color(red: 0.83, green: 0.91, blue: 0.83)
}

extension View {
    func cardStyle(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.hairline, lineWidth: 0.6)
            )
            .shadow(color: Theme.ink.opacity(0.04), radius: 14, x: 0, y: 6)
    }
}

extension Theme {
    /// Primary navy CTA gradient (top-leading -> bottom-trailing).
    static var inkGradient: LinearGradient {
        LinearGradient(colors: [ink, inkRaised],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Type ramp
//
// Audited from existing Plan / Training / Quick Inspection screens.
// These are the ONLY sizes new screens may use. If a layout needs something
// else, snap to the nearest ramp size — do NOT introduce a new one.
//
// Existing ramp (in pt): 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 22, 24, 26, 28
// Weights: .heavy, .bold, .semibold, .medium
//
// Glove-readability minimums from Phase 1/2 prompts (28/24/22/18/17pt) all
// already exist in the ramp — use these tokens rather than literals.
extension Theme {
    enum TypeRamp {
        // Hero / numeric display (steppers, big values).
        static let display: CGFloat = 28          // was 30, 32
        static let title: CGFloat = 24            // section hero / client name
        static let titleSm: CGFloat = 22          // card title large

        // Body / CTA.
        static let cta: CGFloat = 18              // big bottom button label
        static let body: CGFloat = 17             // primary body, ≥17pt min
        static let bodyTight: CGFloat = 16        // dense body, button label
        static let subhead: CGFloat = 15          // subhead / chip large

        // Meta / chip / caption.
        static let meta: CGFloat = 14             // chip body, secondary
        static let metaSm: CGFloat = 13           // section labels
        static let caption: CGFloat = 11          // pill, eyebrow (spec: 11pt)
        static let captionSm: CGFloat = 11        // dense eyebrow
        static let micro: CGFloat = 10            // micro tag
        static let microSm: CGFloat = 9           // map glyph / counter

        // MARK: Spec-named ramp (RoofWise build spec). Aliases onto the audited
        // sizes above so new screens can use the spec vocabulary directly.
        static let titleXl: CGFloat = 28          // hero headlines (semibold)
        static let titleLg: CGFloat = 24          // page titles (semibold)
        static let titleMd: CGFloat = 20          // section headers (semibold)
        static let bodyLg: CGFloat = 17           // body copy (regular)
        static let bodyMd: CGFloat = 15           // secondary body (regular)
        static let bodySm: CGFloat = 13           // labels, chips (regular)

        // Spec-weighted system fonts — use in new code instead of inline
        // `.font(.system(size:weight:))` so the ramp stays the single source.
        static var titleXlFont: Font { .system(size: titleXl, weight: .semibold) }
        static var titleLgFont: Font { .system(size: titleLg, weight: .semibold) }
        static var titleMdFont: Font { .system(size: titleMd, weight: .semibold) }
        static var titleSmFont: Font { .system(size: titleSm, weight: .medium) }
        static var bodyLgFont: Font { .system(size: bodyLg, weight: .regular) }
        static var bodyMdFont: Font { .system(size: bodyMd, weight: .regular) }
        static var bodySmFont: Font { .system(size: bodySm, weight: .regular) }
        static var captionFont: Font { .system(size: caption, weight: .regular) }
    }
}
