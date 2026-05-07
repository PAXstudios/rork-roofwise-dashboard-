import SwiftUI

enum Theme {
    // Brand palette — deep storm navy + warm rooftop ember on ivory canvas.
    static let ink = Color(red: 0.058, green: 0.106, blue: 0.231)        // #0F1B3B
    static let inkRaised = Color(red: 0.12, green: 0.20, blue: 0.42)      // gradient companion
    static let inkSoft = Color(red: 0.27, green: 0.32, blue: 0.43)        // muted slate
    static let inkFaint = Color(red: 0.55, green: 0.59, blue: 0.67)
    static let scrim = Color.black.opacity(0.65)                          // photo overlay scrim
    static let canvas = Color(red: 0.973, green: 0.965, blue: 0.949)      // ivory #F8F6F2
    static let card = Color.white
    static let hairline = Color(red: 0.91, green: 0.90, blue: 0.88)

    static let ember = Color(red: 1.00, green: 0.42, blue: 0.18)          // #FF6B2E
    static let emberDeep = Color(red: 0.91, green: 0.32, blue: 0.10)
    static let emberSoft = Color(red: 1.00, green: 0.93, blue: 0.88)

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
