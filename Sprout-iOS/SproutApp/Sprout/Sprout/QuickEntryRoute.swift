import Foundation

struct QuickEntryRoute {
    let tab: BudgetTab
    let mode: TransactionMode

    init?(url: URL) {
        guard
            url.scheme?.lowercased() == "sprout",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        // Accepts both `sprout://quick-add?…` (host form) and `sprout:quick-add?…`
        // (opaque form), which is what a hand-typed link or some launchers produce.
        let target = (components.host ?? components.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard target == "quick-add" else { return nil }

        let queryItems = components.queryItems ?? []
        let tabValue = queryItems.first(where: { $0.name == "tab" })?.value ?? ""
        let modeValue = queryItems.first(where: { $0.name == "mode" })?.value ?? ""
        let tab = BudgetTab(rawValue: tabValue) ?? .personal
        let mode = TransactionMode(rawValue: modeValue) ?? .expense

        self.tab = tab
        self.mode = mode
    }
}
