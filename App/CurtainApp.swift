// Curtain: countdowns that add up.

import SwiftUI
import CurtainCore

@main
struct CurtainApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .environment(\.timeZone, AppClock.timeZone)
                .environment(\.calendar, AppClock.calendar)
                .onOpenURL { store.open($0) }
        }
    }
}
