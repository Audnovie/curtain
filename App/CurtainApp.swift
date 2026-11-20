// Curtain: countdowns that add up.

import SwiftUI
import UIKit
import WidgetKit
import CurtainCore

@main
struct CurtainApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.timeZone, AppClock.timeZone)
                .environment(\.calendar, AppClock.calendar)
                .onOpenURL { store.open($0) }
                // The clock was changed, the time zone moved, or a new day began.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Opening the app is a cheap moment to have every widget take a fresh look.
            if phase == .active { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}

struct RootView: View {
    var body: some View {
        #if DEBUG
        if AppClock.arguments.contains("-UITestProbe") {
            ProbeView()
        } else {
            DashboardView()
        }
        #else
        DashboardView()
        #endif
    }
}
