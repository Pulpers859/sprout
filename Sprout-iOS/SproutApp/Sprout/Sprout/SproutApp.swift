import AppIntents
import SwiftUI

@main
struct SproutApp: App {
    @StateObject private var store = BudgetStore()
    @StateObject private var quickEntryCoordinator = QuickEntryCoordinator()
    @StateObject private var holidayRouter = HolidayRouter()

    init() {
        SproutAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(quickEntryCoordinator)
                .environmentObject(holidayRouter)
        }
    }
}
