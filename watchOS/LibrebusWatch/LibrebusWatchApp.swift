import SwiftUI

@main
struct LibrebusWatchApp: App {
    @StateObject private var store = WatchSchoolStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView(store: store)
                .tint(.indigo)
                .environment(\.timeZone, WatchSnapshot.schoolCalendar.timeZone)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.requestLatest() }
                }
        }
        .backgroundTask(.watchConnectivity) {
            await store.handleBackgroundDelivery()
        }
        WKNotificationScene(controller: LessonNotificationController.self, category: LessonReminder.category)
    }
}
