import AppIntents
import Foundation

enum SproutBudgetOption: String, AppEnum {
    case personal
    case grocery

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Budget")
    static let caseDisplayRepresentations: [SproutBudgetOption: DisplayRepresentation] = [
        .personal: "Personal",
        .grocery: "Grocery"
    ]

    var budgetTab: BudgetTab {
        switch self {
        case .personal:
            .personal
        case .grocery:
            .grocery
        }
    }
}

enum SproutEntryOption: String, AppEnum {
    case expense
    case payment

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Entry Type")
    static let caseDisplayRepresentations: [SproutEntryOption: DisplayRepresentation] = [
        .expense: "Expense",
        .payment: "Payment"
    ]

    var transactionMode: TransactionMode {
        switch self {
        case .expense:
            .expense
        case .payment:
            .payment
        }
    }
}

struct SproutQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense or Payment"
    static let description = IntentDescription("Open Sprout directly to a compact quick-add sheet for the selected budget and entry type.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Budget")
    var budget: SproutBudgetOption

    @Parameter(title: "Entry Type")
    var entryType: SproutEntryOption

    init() {}

    init(budget: SproutBudgetOption, entryType: SproutEntryOption) {
        self.budget = budget
        self.entryType = entryType
    }

    func perform() async throws -> some IntentResult {
        let request = QuickEntryRequest(
            tab: budget.budgetTab,
            mode: entryType.transactionMode
        )
        QuickEntryRequestStore.save(request)
        return .result(
            dialog: IntentDialog("Opening Sprout quick capture.")
        )
    }
}

@available(*, deprecated)
extension SproutQuickAddIntent {
    static var openAppWhenRun: Bool { true }
}

struct SproutAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .grayGreen
    }

    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: SproutQuickAddIntent(budget: .personal, entryType: .expense),
                phrases: [
                    "Log personal expense in \(.applicationName)",
                    "Quick capture personal purchase in \(.applicationName)"
                ],
                shortTitle: "Log Personal Expense",
                systemImageName: "plus.circle"
            ),
            AppShortcut(
                intent: SproutQuickAddIntent(budget: .grocery, entryType: .expense),
                phrases: [
                    "Log grocery expense in \(.applicationName)",
                    "Quick capture grocery purchase in \(.applicationName)"
                ],
                shortTitle: "Log Grocery Expense",
                systemImageName: "cart.badge.plus"
            ),
            AppShortcut(
                intent: SproutQuickAddIntent(budget: .personal, entryType: .payment),
                phrases: [
                    "Log personal payment in \(.applicationName)",
                    "Quick capture personal refund in \(.applicationName)"
                ],
                shortTitle: "Log Personal Payment",
                systemImageName: "arrow.uturn.backward.circle"
            ),
            AppShortcut(
                intent: SproutQuickAddIntent(budget: .grocery, entryType: .payment),
                phrases: [
                    "Log grocery payment in \(.applicationName)",
                    "Quick capture grocery refund in \(.applicationName)"
                ],
                shortTitle: "Log Grocery Payment",
                systemImageName: "arrow.uturn.backward.circle.fill"
            )
        ]
    }
}
