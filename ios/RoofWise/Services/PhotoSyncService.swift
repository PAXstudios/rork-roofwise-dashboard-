import Foundation
import Observation
import Supabase
import UIKit

/// Sync status surfaced to any photo UI that wants to show upload progress.
enum PhotoSyncStatus: Equatable {
    case idle
    case uploading(remaining: Int)
    case synced(at: Date)
    case failed(message: String)
}

/// Uploads captured inspection photos to Supabase Storage and records a
/// metadata row per photo in the `inspection_photos` table. Local `CapturedPhoto`
/// records (and the in-memory `UIImage`) stay the UI source of truth; this
/// service just mirrors the image bytes + analysis to the cloud so they survive
/// reinstall and are available across devices.
///
/// Storage layout: bucket `inspection-photos`, object key
/// `{userId}/{customerId}/{photoId}.jpg`.
@Observable
@MainActor
final class PhotoSyncService {
    static let shared = PhotoSyncService()

    static let bucket = "inspection-photos"

    private(set) var status: PhotoSyncStatus = .idle

    /// Photo ids already uploaded this session, so re-saving an analyzed copy
    /// of the same photo only re-runs the metadata upsert, not a full re-upload.
    private var uploadedImageIDs: Set<UUID> = []
    private var inFlight: Bool = false

    private init() {}

    /// Upload (or update) a batch of photos for a given customer. Image bytes
    /// are uploaded once per photo id; metadata (findings, markers, analyzed
    /// flag) is upserted every call so analysis results propagate. Safe to call
    /// fire-and-forget — failures are surfaced via `status` and logged.
    func sync(_ photos: [CapturedPhoto], for customerID: UUID) async {
        guard !photos.isEmpty else { return }
        guard let userId = AuthStore.shared.currentUserId else {
            status = .idle
            return
        }
        inFlight = true
        defer { inFlight = false }

        var remaining = photos.count
        status = .uploading(remaining: remaining)

        do {
            for photo in photos {
                let path = Self.objectKey(userId: userId, customerID: customerID, photoID: photo.id)

                // Upload image bytes once per photo id.
                if !uploadedImageIDs.contains(photo.id),
                   let data = photo.image.jpegData(compressionQuality: 0.7) {
                    try await SupabaseService.client.storage
                        .from(Self.bucket)
                        .upload(
                            path: path,
                            file: data,
                            options: FileOptions(contentType: "image/jpeg", upsert: true)
                        )
                    uploadedImageIDs.insert(photo.id)
                }

                // Upsert metadata row (idempotent on photo id).
                let row = RemotePhoto.from(photo: photo,
                                           userId: userId,
                                           customerID: customerID,
                                           storagePath: path)
                try await SupabaseService.client
                    .from("inspection_photos")
                    .upsert(row, onConflict: "id")
                    .execute()

                remaining -= 1
                status = .uploading(remaining: remaining)
            }
            status = .synced(at: Date())
        } catch {
            print("[PhotoSync] failed: \(error)")
            status = .failed(message: Self.friendlyMessage(for: error))
        }
    }

    /// Reset the upload ledger (e.g. on sign-out so a new user re-uploads).
    func resetLedger() {
        uploadedImageIDs.removeAll()
        status = .idle
    }

    private static func objectKey(userId: String, customerID: UUID, photoID: UUID) -> String {
        "\(userId)/\(customerID.uuidString)/\(photoID.uuidString).jpg"
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "Offline — photos will upload when you're back online."
        }
        if raw.contains("jwt") || raw.contains("not authenticated") {
            return "Session expired — please sign in again."
        }
        if raw.contains("bucket") || raw.contains("not found") {
            return "Storage not configured yet — create the inspection-photos bucket."
        }
        return "Photo upload failed: \(error.localizedDescription)"
    }
}

// MARK: - Remote row DTOs

nonisolated struct RemotePhoto: Codable, Sendable {
    let id: String
    let user_id: String
    let customer_id: String
    let slope: String
    let pitch_degrees: Double
    let elevation_feet: Double
    let capture_mode: String
    let squares_covered: Int
    let storage_path: String
    let analyzed: Bool
    let findings: [RemoteFinding]
    let damage_markers: [RemoteMarker]
    let captured_at: Date
    let updated_at: Date

    static func from(photo: CapturedPhoto,
                     userId: String,
                     customerID: UUID,
                     storagePath: String) -> RemotePhoto {
        RemotePhoto(
            id: photo.id.uuidString,
            user_id: userId,
            customer_id: customerID.uuidString,
            slope: photo.slope.rawValue,
            pitch_degrees: photo.pitchDegrees,
            elevation_feet: photo.elevationFeet,
            capture_mode: photo.captureMode.rawValue,
            squares_covered: photo.squaresCovered,
            storage_path: storagePath,
            analyzed: photo.analyzed,
            findings: photo.findings.map(RemoteFinding.from),
            damage_markers: photo.damageMarkers.map(RemoteMarker.from),
            captured_at: photo.timestamp,
            updated_at: Date()
        )
    }
}

nonisolated struct RemoteFinding: Codable, Sendable {
    let label: String
    let display: String
    let value: String
    let confidence: Int
    let detected: Bool
    let severity: String

    static func from(_ f: InspectionFinding) -> RemoteFinding {
        RemoteFinding(
            label: f.label,
            display: f.display,
            value: f.value,
            confidence: f.confidence,
            detected: f.detected,
            severity: f.severity.rawValue
        )
    }
}

nonisolated struct RemoteMarker: Codable, Sendable {
    let x: Double
    let y: Double
    let radius: Double
    let type: String
    let severity: String
    let note: String
    let confidence: Int

    static func from(_ m: DamageMarker) -> RemoteMarker {
        RemoteMarker(
            x: Double(m.x),
            y: Double(m.y),
            radius: Double(m.radius),
            type: m.type.rawValue,
            severity: m.severity.rawValue,
            note: m.note,
            confidence: m.confidence
        )
    }
}
