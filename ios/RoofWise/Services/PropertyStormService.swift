import SwiftUI
import Foundation

/// Per-property storm history.
///
/// Previously this synthesized a fake, deterministic storm "fingerprint" from a
/// hash of the address — fabricated data presented as real NEXRAD/carrier loss
/// data, which violates the "no synthesized data" rule (and is dangerous for an
/// insurance-claim product). It now returns no hits; real history will be sourced
/// from `StormEventsService` (NOAA) once the address is geocoded to lat/lng.
/// `PropertyHit` is retained as the contract for that real implementation.
enum PropertyStormService {

    struct PropertyHit: Identifiable {
        let id = UUID()
        let storm: StormEvent
        /// 0 - 1, how directly this property sits inside the impact core
        let coverage: Double
        /// "Direct hit", "Edge of core", "Glancing"
        var coverageLabel: String {
            switch coverage {
            case 0.75...: return "Direct hit"
            case 0.5..<0.75: return "Inside impact zone"
            case 0.25..<0.5: return "Edge of core"
            default: return "Glancing"
            }
        }
        var coverageColor: Color {
            switch coverage {
            case 0.75...: return Theme.crimson
            case 0.5..<0.75: return Theme.ember
            case 0.25..<0.5: return Theme.amber
            default: return Theme.inkFaint
            }
        }
    }

    /// No fabricated history. Real per-property storm matches will come from
    /// `StormEventsService` (NOAA) keyed on the geocoded property coordinate.
    static func hits(for customer: Customer) -> [PropertyHit] { [] }

    static func mostRecentSevereHit(for customer: Customer) -> PropertyHit? { nil }
}
