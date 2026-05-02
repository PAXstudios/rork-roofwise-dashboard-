//
//  RoofWiseApp.swift
//  RoofWise
//

import SwiftUI

@main
struct RoofWiseApp: App {
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
    }
}
