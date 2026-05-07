import Foundation
import SwiftData

// MARK: - Roof attribute enums

enum JobRoofMaterial: String, CaseIterable, Identifiable, Sendable {
    case asphalt = "Asphalt Shingle"
    case metal = "Metal"
    case tile = "Tile"
    case wood = "Wood Shake"
    case slate = "Slate"
    case flat = "Flat / TPO"
    var id: String { rawValue }
}

enum JobRoofPitch: String, CaseIterable, Identifiable, Sendable {
    case low = "Low (1:12 – 3:12)"
    case medium = "Medium (4:12 – 7:12)"
    case steep = "Steep (8:12 – 12:12)"
    case extreme = "Extreme (>12:12)"
    var id: String { rawValue }
}

// MARK: - SwiftData entities

@Model
final class CustomerRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var phone: String
    var email: String

    @Relationship(deleteRule: .cascade, inverse: \JobRecord.customer)
    var jobs: [JobRecord] = []

    init(id: UUID = UUID(), name: String, phone: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
    }
}

@Model
final class PropertyRecord {
    @Attribute(.unique) var id: UUID
    var addressLine: String
    var city: String
    var state: String
    var zip: String
    var latitude: Double
    var longitude: Double
    var roofMaterialRaw: String
    var roofPitchRaw: String
    var stories: Int
    var sqftEstimate: Int
    var yearBuilt: Int

    init(id: UUID = UUID(),
         addressLine: String = "",
         city: String = "",
         state: String = "TX",
         zip: String = "",
         latitude: Double = 33.0198,
         longitude: Double = -96.6989,
         roofMaterialRaw: String = JobRoofMaterial.asphalt.rawValue,
         roofPitchRaw: String = JobRoofPitch.medium.rawValue,
         stories: Int = 1,
         sqftEstimate: Int = 0,
         yearBuilt: Int = 0) {
        self.id = id
        self.addressLine = addressLine
        self.city = city
        self.state = state
        self.zip = zip
        self.latitude = latitude
        self.longitude = longitude
        self.roofMaterialRaw = roofMaterialRaw
        self.roofPitchRaw = roofPitchRaw
        self.stories = stories
        self.sqftEstimate = sqftEstimate
        self.yearBuilt = yearBuilt
    }

    var roofMaterial: JobRoofMaterial { JobRoofMaterial(rawValue: roofMaterialRaw) ?? .asphalt }
    var roofPitch: JobRoofPitch { JobRoofPitch(rawValue: roofPitchRaw) ?? .medium }
}

@Model
final class InsuranceRecord {
    @Attribute(.unique) var id: UUID
    var carrier: String
    var claimNumber: String
    var adjusterName: String
    var adjusterPhone: String
    var deductibleCents: Int

    init(id: UUID = UUID(),
         carrier: String = "",
         claimNumber: String = "",
         adjusterName: String = "",
         adjusterPhone: String = "",
         deductibleCents: Int = 100_000) {
        self.id = id
        self.carrier = carrier
        self.claimNumber = claimNumber
        self.adjusterName = adjusterName
        self.adjusterPhone = adjusterPhone
        self.deductibleCents = deductibleCents
    }
}

@Model
final class JobPhotoAttachment {
    @Attribute(.unique) var id: UUID
    var caption: String
    var takenAt: Date
    var localFilename: String
    var job: JobRecord?

    init(id: UUID = UUID(),
         caption: String = "",
         takenAt: Date = .now,
         localFilename: String = "") {
        self.id = id
        self.caption = caption
        self.takenAt = takenAt
        self.localFilename = localFilename
    }
}

@Model
final class JobRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var pipelineStageRaw: String
    var damageScore: Int
    var notes: String
    var assignedRep: String
    var stormEventLabel: String

    @Relationship var customer: CustomerRecord?
    @Relationship(deleteRule: .cascade) var property: PropertyRecord?
    @Relationship(deleteRule: .cascade) var insurance: InsuranceRecord?

    @Relationship(deleteRule: .cascade, inverse: \JobPhotoAttachment.job)
    var photos: [JobPhotoAttachment] = []

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         pipelineStageRaw: String = JobPipelineStage.knocked.rawValue,
         damageScore: Int = 0,
         notes: String = "",
         assignedRep: String = "",
         stormEventLabel: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.pipelineStageRaw = pipelineStageRaw
        self.damageScore = damageScore
        self.notes = notes
        self.assignedRep = assignedRep
        self.stormEventLabel = stormEventLabel
    }

    var pipelineStage: JobPipelineStage {
        JobPipelineStage(rawValue: pipelineStageRaw) ?? .knocked
    }
}

// MARK: - Container

enum JobPersistence {
    static let schema = Schema([
        CustomerRecord.self,
        PropertyRecord.self,
        InsuranceRecord.self,
        JobPhotoAttachment.self,
        JobRecord.self,
        Correction.self
    ])

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            // Fall back to in-memory so the app still launches in dev.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }
}
