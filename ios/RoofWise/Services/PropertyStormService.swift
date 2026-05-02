import SwiftUI
import Foundation

/// Computes a deterministic storm history for a given property based on a
/// stable hash of its address. Until real geolookup is wired up, this gives
/// each customer a believable, repeatable storm fingerprint.
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

    static func hits(for customer: Customer) -> [PropertyHit] {
        let seed = stableHash(customer.address.isEmpty ? customer.ownerName : customer.address)
        var rng = SeededRNG(seed: seed)

        // Filter the storms this property "saw" — pick 2-4 deterministically
        var pool = MockData.storms
        // Always favor severe + recent
        pool.sort { $0.year > $1.year }

        let count = 2 + Int(rng.next() % 3) // 2..4
        var picks: [PropertyHit] = []
        var available = pool
        for _ in 0..<min(count, available.count) {
            let idx = Int(rng.next() % UInt64(available.count))
            let storm = available.remove(at: idx)
            // Coverage roll, biased by storm intensity
            let bias = storm.intensity
            let roll = Double(rng.next() % 1000) / 1000.0
            let coverage = min(1.0, max(0.1, (roll * 0.7) + bias * 0.5))
            picks.append(PropertyHit(storm: storm, coverage: coverage))
        }
        // Sort newest first
        return picks.sorted { $0.storm.year > $1.storm.year }
    }

    static func mostRecentSevereHit(for customer: Customer) -> PropertyHit? {
        hits(for: customer).first { $0.storm.band == .severe || $0.coverage >= 0.6 }
    }

    // MARK: - Deterministic helpers

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return h
    }
}

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
