//
//  RoofWiseApp.swift
//  RoofWise
//

import SwiftUI
import SwiftData

@main
struct RoofWiseApp: App {
    private let modelContainer: ModelContainer = JobPersistence.makeContainer()

    init() {
        MileageNotificationDelegate.shared.install()
        // Touch the singleton so SLC monitoring resumes if the user has enabled it.
        _ = MileageAutoTrackService.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
