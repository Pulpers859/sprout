import AppIntents
import SwiftUI

@main
struct SproutApp: App {
    @StateObject private var store = BudgetStore()
    @StateObject private var quickEntryCoordinator = QuickEntryCoordinator()

    init() {
        SproutAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(quickEntryCoordinator)
        }
    }
}
