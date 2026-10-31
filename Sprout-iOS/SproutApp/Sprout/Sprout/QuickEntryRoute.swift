import Foundation

struct QuickEntryRoute {
    /// Which tab the link targets.
    ///
    /// `tab=holiday` used to fall through to `.personal`, which is the worst
    /// possible outcome for a link whose whole job is to file money: a gift
    /// would have been offered against the Personal budget instead of the
    /// holiday one. It now routes where it says.
    let section: AppSection
    let mode: TransactionMode

    /// The monthly budget tab this link targets. `.personal` for a holiday link,
    /// where it is never read.
    var tab: BudgetTab { section.budgetTab ?? .personal }

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
        // An unrecognised value still defaults to Personal Expense, which the
        // sheet names on screen before anything is saved.
        self.section = AppSection(rawValue: tabValue.lowercased()) ?? .personal
        self.mode = TransactionMode(rawValue: modeValue) ?? .expense
    }
}
