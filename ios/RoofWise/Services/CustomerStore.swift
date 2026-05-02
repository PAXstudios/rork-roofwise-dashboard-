import SwiftUI
import Observation

@Observable
final class CustomerStore {
    var customers: [Customer]
    var activeCustomerID: UUID?

    init() {
        let seed: [Customer] = [
            Customer(ownerName: "Smith Residence", address: "734 Cedar Hollow Rd",
                     phone: "(214) 555-0142", email: "j.smith@example.com",
                     insuranceCompany: "State Farm", policyNumber: "SF-9087421",
                     dateOfLoss: Calendar.current.date(byAdding: .day, value: -28, to: .now),
                     adjusterName: "Karen Liu", adjusterPhone: "(800) 555-0119",
                     stage: .claimFiled, stormTagged: true, estimatedValue: "$28,400"),
            Customer(ownerName: "Patel Custom Build", address: "5501 Stonebriar Pkwy",
                     phone: "(469) 555-0177", email: "ravi@patelbuild.com",
                     insuranceCompany: "Allstate", policyNumber: "AL-5532018",
                     dateOfLoss: Calendar.current.date(byAdding: .day, value: -14, to: .now),
                     adjusterName: "Marcus Reed", adjusterPhone: "(800) 555-0233",
                     stage: .adjusterMeeting, stormTagged: true, estimatedValue: "$54,200"),
            Customer(ownerName: "Hawthorn Apts", address: "210 Hawthorn Blvd",
                     phone: "(972) 555-0188",
                     insuranceCompany: "Travelers", policyNumber: "TR-7711204",
                     stage: .interested, stormTagged: true, estimatedValue: "$112,000"),
            Customer(ownerName: "J. Whitman", address: "12 Ridge Vista",
                     phone: "(214) 555-0166",
                     stage: .inspectionScheduled, estimatedValue: "$18,900"),
            Customer(ownerName: "R. Greene", address: "1247 Oakridge Ln",
                     phone: "(214) 555-0151", email: "rgreene@example.com",
                     insuranceCompany: "USAA", policyNumber: "US-3320981",
                     dateOfLoss: Calendar.current.date(byAdding: .day, value: -42, to: .now),
                     adjusterName: "Diane Cole", adjusterPhone: "(800) 555-0411",
                     stage: .approved, stormTagged: true, estimatedValue: "$31,800"),
            Customer(ownerName: "D. Park", address: "920 Bluebonnet Way",
                     phone: "(469) 555-0110", email: "dpark@example.com",
                     insuranceCompany: "Liberty Mutual", policyNumber: "LM-4498712",
                     stage: .paid, estimatedValue: "$36,400"),
            Customer(ownerName: "M. Castellanos", address: "88 Maple Cove",
                     phone: "(972) 555-0193",
                     stage: .knocked, estimatedValue: "$22,500")
        ]
        self.customers = seed
        self.activeCustomerID = seed.first?.id
    }

    var activeCustomer: Customer? {
        get { customers.first { $0.id == activeCustomerID } }
        set {
            guard let nv = newValue, let i = customers.firstIndex(where: { $0.id == nv.id }) else { return }
            customers[i] = nv
        }
    }

    func setActive(_ id: UUID) {
        activeCustomerID = id
    }

    func add(_ customer: Customer, makeActive: Bool = true) {
        customers.append(customer)
        if makeActive { activeCustomerID = customer.id }
    }

    func update(_ customer: Customer) {
        guard let i = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        customers[i] = customer
    }

    func updateStage(_ id: UUID, to stage: JobPipelineStage) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].stage = stage
    }

    func appendPhotos(_ photos: [CapturedPhoto], to id: UUID) {
        guard !photos.isEmpty, let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].photos.append(contentsOf: photos)
        if customers[i].stage.stepIndex < JobPipelineStage.inspectionComplete.stepIndex {
            customers[i].stage = .inspectionComplete
        }
    }

    func updateAnalysis(for id: UUID, photos: [CapturedPhoto], findings: [InspectionFinding]) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        // Replace photos that match by id with their analyzed counterparts; append new
        var existing = customers[i].photos
        for p in photos {
            if let idx = existing.firstIndex(where: { $0.id == p.id }) {
                existing[idx] = p
            } else {
                existing.append(p)
            }
        }
        customers[i].photos = existing
        customers[i].damageFindings = findings
    }

    func attachClaim(for id: UUID, packet: ClaimPacket) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].claimGrade = packet.grade
        customers[i].claimPacketSummary = packet.summary
        if customers[i].stage.stepIndex < JobPipelineStage.claimFiled.stepIndex {
            customers[i].stage = .claimFiled
        }
    }

    func addNote(_ text: String, to id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].notes.insert(CustomerNote(text: trimmed), at: 0)
    }
}
