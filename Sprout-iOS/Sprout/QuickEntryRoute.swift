import Foundation

struct QuickEntryRoute {
    let tab: BudgetTab
    let mode: TransactionMode

    init?(url: URL) {
        guard
            url.scheme?.lowercased() == "sprout",
            url.host?.lowercased() == "quick-add",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let tabValue = queryItems.first(where: { $0.name == "tab" })?.value ?? ""
        let modeValue = queryItems.first(where: { $0.name == "mode" })?.value ?? ""
        let tab = BudgetTab(rawValue: tabValue) ?? .personal
        let mode = TransactionMode(rawValue: modeValue) ?? .expense

        self.tab = tab
        self.mode = mode
    }
}
