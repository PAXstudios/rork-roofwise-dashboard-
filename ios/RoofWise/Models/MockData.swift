import SwiftUI

enum MockData {
    static let kpis: [KPIMetric] = [
        .init(title: "Jobs In Progress", value: "14", delta: "2 closing soon", deltaPositive: true, icon: "hammer.fill", tint: Theme.mint),
        .init(title: "Revenue Won (May)", value: "$182.4k", delta: "+18% MoM", deltaPositive: true, icon: "chart.line.uptrend.xyaxis", tint: Theme.amber),
        .init(title: "Storm-Impacted", value: "126", delta: "Hail · 1.75\"", deltaPositive: false, icon: "cloud.bolt.rain.fill", tint: Theme.crimson)
    ]

    static let pipeline: [PipelineColumn] = [
        .init(stage: .new, count: 18, value: "$54k"),
        .init(stage: .contacted, count: 12, value: "$96k"),
        .init(stage: .proposal, count: 7, value: "$142k"),
        .init(stage: .won, count: 4, value: "$78k"),
        .init(stage: .lost, count: 3, value: "—")
    ]

    static let schedule: [ScheduleItem] = [
        .init(time: "08:30", kind: .inspection,
              title: "Forensic Roof Inspection",
              address: "1247 Oakridge Ln · Plano",
              assignee: "Sarah Jenkins", assigneeColor: Theme.ember, priority: .storm),
        .init(time: "10:00", kind: .estimate,
              title: "Estimate Review · Hail Claim",
              address: "445 Pine Lane · Frisco",
              assignee: "Mike Johnson", assigneeColor: Theme.sky, priority: .high),
        .init(time: "12:30", kind: .followUp,
              title: "Adjuster Walk · State Farm",
              address: "88 Maple Cove · McKinney",
              assignee: "Alex Coleman", assigneeColor: Theme.mint, priority: .normal),
        .init(time: "15:00", kind: .install,
              title: "Tear-off Begins · GAF Timberline",
              address: "12 Ridge Vista · Allen",
              assignee: "Crew B", assigneeColor: Theme.amber, priority: .normal)
    ]

    static let recentJobs: [RecentJob] = [
        .init(title: "Westside Library",
              address: "920 Civic Center Dr",
              status: .done,
              subtitle: "Completed Yesterday · TPO Membrane",
              imageURL: "https://images.unsplash.com/photo-1632759145355-8b8f3ab2f1a7?w=900"),
        .init(title: "Smith Residence",
              address: "734 Cedar Hollow Rd",
              status: .active,
              subtitle: "Crew B · Day 2 of 3",
              imageURL: "https://images.unsplash.com/photo-1632759145351-1d76a4b2c1f0?w=900"),
        .init(title: "Hawthorn Apartments",
              address: "210 Hawthorn Blvd",
              status: .awaiting,
              subtitle: "Adjuster meet Thu 2pm",
              imageURL: "https://images.unsplash.com/photo-1604769933916-2bbef5e5ed09?w=900"),
        .init(title: "Patel Custom Build",
              address: "5501 Stonebriar Pkwy",
              status: .scheduled,
              subtitle: "Tear-off begins May 8",
              imageURL: "https://images.unsplash.com/photo-1518780664697-55e3ad937233?w=900")
    ]

    static let mapPins: [MapPin] = [
        .init(kind: .lead, label: "L", x: 0.18, y: 0.32),
        .init(kind: .lead, label: "L", x: 0.42, y: 0.28),
        .init(kind: .lead, label: "L", x: 0.62, y: 0.55),
        .init(kind: .job, label: "J", x: 0.34, y: 0.62),
        .init(kind: .job, label: "J", x: 0.78, y: 0.40),
        .init(kind: .storm, label: "S", x: 0.55, y: 0.35),
        .init(kind: .storm, label: "S", x: 0.28, y: 0.74),
        .init(kind: .storm, label: "S", x: 0.72, y: 0.70)
    ]

    static let aiReview: [AIReviewItem] = [
        .init(address: "1247 Oakridge Ln",
              damageType: "Hail Bruise · Slope SW",
              confidence: 72,
              imageURL: "https://images.unsplash.com/photo-1597047084897-51e81819a499?w=600",
              aiTags: ["Granule loss", "Mat fracture?"]),
        .init(address: "88 Maple Cove",
              damageType: "Wind Lift · Ridge",
              confidence: 64,
              imageURL: "https://images.unsplash.com/photo-1605276374104-dee2a0ed3cd6?w=600",
              aiTags: ["Crease", "Sealant"]),
        .init(address: "12 Ridge Vista",
              damageType: "Mech vs Hail",
              confidence: 51,
              imageURL: "https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=600",
              aiTags: ["Pattern check"])
    ]

    static let tasks: [TaskItem] = [
        .init(title: "Send Patel scope of work to adjuster", due: "Today · 4pm", done: false, tag: "Claim", tagColor: Theme.ember),
        .init(title: "Order GAF Timberline HDZ — Charcoal", due: "Tomorrow", done: false, tag: "Supply", tagColor: Theme.sky),
        .init(title: "Confirm crew B for Allen tear-off", due: "Today", done: true, tag: "Ops", tagColor: Theme.mint),
        .init(title: "Review AI labels · 3 inspections", due: "Today", done: false, tag: "Review", tagColor: Theme.amber)
    ]

    static let activity: [ActivityEntry] = [
        .init(icon: "checkmark.seal.fill", iconColor: Theme.mint,
              title: "Westside Library marked complete",
              detail: "Final invoice $84,200 · Photos uploaded",
              time: "32m"),
        .init(icon: "bolt.fill", iconColor: Theme.ember,
              title: "Storm cell crossed Plano",
              detail: "1.75″ hail · 41 leads auto-tagged",
              time: "2h"),
        .init(icon: "person.crop.circle.badge.plus", iconColor: Theme.sky,
              title: "Sarah Jenkins booked 4 inspections",
              detail: "From Oak Valley canvas route",
              time: "5h"),
        .init(icon: "doc.text.fill", iconColor: Theme.amber,
              title: "Proposal viewed · Smith Residence",
              detail: "Opened 3 times · Likely ready to sign",
              time: "Yesterday")
    ]

    // 4-year storm history (deterministic mock)
    static let storms: [StormEvent] = [
        // 2026
        .init(type: .hail, year: 2026, date: "Apr 18", intensity: 0.95, sizeInches: 1.75, windMPH: nil, x: 0.55, y: 0.35, radius: 0.28),
        .init(type: .wind, year: 2026, date: "Mar 02", intensity: 0.62, sizeInches: nil, windMPH: 71, x: 0.30, y: 0.62, radius: 0.22),
        // 2025
        .init(type: .hail, year: 2025, date: "May 21", intensity: 0.80, sizeInches: 1.25, windMPH: nil, x: 0.40, y: 0.50, radius: 0.30),
        .init(type: .hail, year: 2025, date: "Aug 09", intensity: 0.55, sizeInches: 0.88, windMPH: nil, x: 0.72, y: 0.42, radius: 0.18),
        .init(type: .wind, year: 2025, date: "Oct 14", intensity: 0.70, sizeInches: nil, windMPH: 78, x: 0.60, y: 0.70, radius: 0.25),
        // 2024
        .init(type: .hail, year: 2024, date: "Apr 04", intensity: 0.88, sizeInches: 2.00, windMPH: nil, x: 0.25, y: 0.30, radius: 0.32),
        .init(type: .wind, year: 2024, date: "Jun 22", intensity: 0.50, sizeInches: nil, windMPH: 64, x: 0.78, y: 0.62, radius: 0.20),
        // 2023
        .init(type: .hail, year: 2023, date: "May 11", intensity: 0.72, sizeInches: 1.10, windMPH: nil, x: 0.50, y: 0.55, radius: 0.26),
        .init(type: .wind, year: 2023, date: "Sep 03", intensity: 0.45, sizeInches: nil, windMPH: 58, x: 0.20, y: 0.50, radius: 0.18)
    ]
}
