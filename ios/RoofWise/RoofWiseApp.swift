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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MileageNotificationDelegate.shared.install()
        // Touch the singleton so SLC monitoring resumes if the user has enabled it.
        _ = MileageAutoTrackService.shared

        Self.bootGoogleMaps()

        // Register the storm-watch BGTask handler. Safe no-op in mock builds
        // and on simulator where BGTasks are unavailable.
        StormWatchService.registerBackgroundTasks()
        CalibrationPushService.registerBackgroundTasks()

        // Register the storm-alert notification category so action buttons
        // (View / Snooze / Dismiss) appear when an alert push arrives.
        StormPushService.shared.registerCategory()
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { @MainActor in
                    await StormPushService.shared.refreshStatus()
                    _ = await StormWatchService.shared.scanNow()
                }
            case .background:
                StormWatchService.shared.scheduleNextBackgroundRefresh()
                StormWatchService.shared.stopForegroundPolling()
                CalibrationPushService.shared.scheduleNext()
            default:
                break
            }
        }
    }
}
