//
//  RoofWiseApp.swift
//  RoofWise
//

import SwiftUI
import SwiftData

#if canImport(GoogleMaps)
import GoogleMaps
#endif

@main
struct RoofWiseApp: App {
    private let modelContainer: ModelContainer = JobPersistence.makeContainer()

    init() {
        MileageNotificationDelegate.shared.install()
        // Touch the singleton so SLC monitoring resumes if the user has enabled it.
        _ = MileageAutoTrackService.shared

        Self.bootGoogleMaps()
    }

    private static func bootGoogleMaps() {
        #if canImport(GoogleMaps)
        if APIKeys.isLiveGoogleMaps {
            GMSServices.provideAPIKey(APIKeys.googleMapsApiKey)
        } else {
            print("Google Maps in MOCK mode")
        }
        #else
        print("Google Maps SDK not linked — MapKit fallback active")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
