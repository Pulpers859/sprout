import Testing
import Foundation
@testable import Sprout

@MainActor
struct BudgetStoreTests {

    private func makeStore(calendar: Calendar = .current) -> BudgetStore {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return BudgetStore(fileManager: fm, calendar: calendar)
    }

    // MARK: - Budget Math

    @Test func defaultBudgets() {
        let store = makeStore()
        #expect(store.budget(for: .personal) == 200)
        #expect(store.budget(for: .grocery) == 400)
    }

    @Test func setBudgetUpdatesTotal() {
        let store = makeStore()
        store.setBudget(500, for: .personal)
        #expect(store.budget(for: .personal) == 500)
    }

    @Test func setBudgetRejectsNegative() {
        let store = makeStore()
        store.setBudget(-50, for: .personal)
        #expect(store.budget(for: .personal) == 200)
    }

    @Test func netSpentWithNoTransactions() {
        let store = makeStore()
        #expect(store.netSpent(for: .personal) == 0)
        #expect(store.remaining(for: .personal) == 200)
    }

    @Test func netSpentSumsExpenses() {
        let store = makeStore()
        let draft1 = TransactionDraft(name: "Coffee", amountText: "5.00", selectedEmoji: "☕")
        let draft2 = TransactionDraft(name: "Lunch", amountText: "12.50", selectedEmoji: "🍕")
        _ = store.addTransaction(mode: .expense, draft: draft1, tab: .personal)
        _ = store.addTransaction(mode: .expense, draft: draft2, tab: .personal)
        #expect(store.netSpent(for: .personal) == 17.50)
        #expect(store.remaining(for: .personal) == 182.50)
    }

    @Test func refundReducesNetSpent() {
        let store = makeStore()
        let expense = TransactionDraft(name: "Shirt", amountText: "40", selectedEmoji: "👕")
        let refund = TransactionDraft(name: "Shirt Return", amountText: "40", selectedEmoji: "💸")
        _ = store.addTransaction(mode: .expense, draft: expense, tab: .personal)
        _ = store.addTransaction(mode: .payment, draft: refund, tab: .personal)
        #expect(store.netSpent(for: .personal) == 0)
        #expect(store.remaining(for: .personal) == 200)
    }

    @Test func progressClampsToZeroOne() {
        let store = makeStore()
        #expect(store.progress(for: .personal) == 0)

        store.setBudget(100, for: .personal)
        let big = TransactionDraft(name: "Overboard", amountText: "200", selectedEmoji: "💸")
        _ = store.addTransaction(mode: .expense, draft: big, tab: .personal)
        #expect(store.progress(for: .personal) == 1)
    }

    @Test func progressZeroBudget() {
        let store = makeStore()
        store.setBudget(0, for: .personal)
        #expect(store.progress(for: .personal) == 0)
    }

    @Test func dailyAllowanceNeverDividesByZero() {
        let store = makeStore()
        let allowance = store.dailyAllowance(for: .personal)
        #expect(allowance.isFinite)
        #expect(allowance > 0)
    }

    @Test func tabsAreIndependent() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Milk", amountText: "5", selectedEmoji: "🛒")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .grocery)
        #expect(store.netSpent(for: .grocery) == 5)
        #expect(store.netSpent(for: .personal) == 0)
    }

    // MARK: - Carryover

    @Test func setBudgetPreservesCarryover() {
        let store = makeStore()
        store.resetMonth(carryOverRemainders: true)
        let carryover = store.carryover(for: .personal)
        store.setBudget(500, for: .personal)
        #expect(store.carryover(for: .personal) == carryover)
        #expect(store.baseBudget(for: .personal) == 500 - carryover)
    }

    @Test func setBudgetBelowCarryoverClampsCarryover() {
        let store = makeStore()
        store.resetMonth(carryOverRemainders: true)
        let carryover = store.carryover(for: .personal)
        guard carryover > 0 else { return }

        store.setBudget(carryover / 2, for: .personal)
        #expect(store.carryover(for: .personal) == carryover / 2)
        #expect(store.baseBudget(for: .personal) == 0)
    }

    // MARK: - Transaction Validation

    @Test func addTransactionRejectsEmpty() {
        let store = makeStore()
        let empty = TransactionDraft(name: "", amountText: "10", selectedEmoji: "🛍️")
        let result = store.addTransaction(mode: .expense, draft: empty, tab: .personal)
        #expect(result == false)
        #expect(store.transactions(for: .personal).isEmpty)
    }

    @Test func addTransactionRejectsZeroAmount() {
        let store = makeStore()
        let zero = TransactionDraft(name: "Coffee", amountText: "0", selectedEmoji: "☕")
        let result = store.addTransaction(mode: .expense, draft: zero, tab: .personal)
        #expect(result == false)
    }

    @Test func addTransactionRejectsNegativeAmount() {
        let store = makeStore()
        let negative = TransactionDraft(name: "Coffee", amountText: "-5", selectedEmoji: "☕")
        let result = store.addTransaction(mode: .expense, draft: negative, tab: .personal)
        #expect(result == false)
    }

    @Test func addTransactionTrimsWhitespace() {
        let store = makeStore()
        let draft = TransactionDraft(name: "  Coffee  ", amountText: "5", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        #expect(store.transactions(for: .personal).first?.name == "Coffee")
    }

    @Test func deleteRemovesTransaction() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Coffee", amountText: "5", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        let entry = store.transactions(for: .personal).first!
        store.deleteTransaction(entry)
        #expect(store.transactions(for: .personal).isEmpty)
    }

    // MARK: - Month Rollover

    @Test func resetMonthClearsTransactions() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Coffee", amountText: "5", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.resetMonth(carryOverRemainders: false)
        #expect(store.transactions(for: .personal).isEmpty)
    }

    @Test func resetFreshZerosCarryover() {
        let store = makeStore()
        store.resetMonth(carryOverRemainders: false)
        #expect(store.carryover(for: .personal) == 0)
        #expect(store.carryover(for: .grocery) == 0)
    }

    @Test func resetCarryOverSetsPositiveRemainder() {
        let store = makeStore()
        store.setBudget(200, for: .personal)
        let draft = TransactionDraft(name: "Coffee", amountText: "50", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        let expectedCarry = store.remaining(for: .personal)
        store.resetMonth(carryOverRemainders: true)
        #expect(store.carryover(for: .personal) == expectedCarry)
    }

    @Test func resetCarryOverClampsNegativeToZero() {
        let store = makeStore()
        store.setBudget(10, for: .personal)
        let draft = TransactionDraft(name: "Big Purchase", amountText: "50", selectedEmoji: "🛍️")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.resetMonth(carryOverRemainders: true)
        #expect(store.carryover(for: .personal) == 0)
    }

    @Test func resetArchivesMonth() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Coffee", amountText: "5", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.resetMonth(carryOverRemainders: false)
        #expect(!store.archivedMonths.isEmpty)
    }

    @Test func keepCurrentTransactionsPreservesData() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Coffee", amountText: "5", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.keepCurrentTransactions()
        #expect(store.transactions(for: .personal).count == 1)
    }

    // MARK: - Categories

    @Test func defaultCategoriesExist() {
        let store = makeStore()
        let cats = store.categories(for: .personal)
        #expect(!cats.isEmpty)
        #expect(cats.count == PersonalCategory.defaults.count)
    }

    @Test func addCategoryIncrements() {
        let store = makeStore()
        let before = store.categories(for: .personal).count
        store.addCategory()
        #expect(store.categories(for: .personal).count == before + 1)
    }

    @Test func addCategoryCapsAtTen() {
        let store = makeStore()
        for _ in 0..<20 { store.addCategory() }
        #expect(store.categories(for: .personal).count <= 10)
    }

    @Test func removeCategoryKeepsMinimumOne() {
        let store = makeStore()
        let cats = store.categories(for: .personal)
        for cat in cats { store.removeCategory(cat) }
        #expect(store.categories(for: .personal).count >= 1)
    }

    @Test func groceryHasNoCustomCategories() {
        let store = makeStore()
        #expect(store.categories(for: .grocery).isEmpty)
    }

    // MARK: - Recurring Transactions

    @Test func addRecurringCreatesRule() {
        let store = makeStore()
        var draft = TransactionDraft(name: "Netflix", amountText: "15.99", selectedEmoji: "🎬")
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        #expect(store.recurringRules(for: .personal).count == 1)
        #expect(store.recurringRules(for: .personal).first?.name == "Netflix")
    }

    @Test func removeRecurringRule() {
        let store = makeStore()
        var draft = TransactionDraft(name: "Netflix", amountText: "15.99", selectedEmoji: "🎬")
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        let rule = store.recurringRules(for: .personal).first!
        store.removeRecurringRule(rule)
        #expect(store.recurringRules(for: .personal).isEmpty)
    }

    // MARK: - Spending Pace

    @Test func spendingPaceReturnsValidStatus() {
        let store = makeStore()
        let status = store.spendingPaceStatus(for: .personal)
        let valid: [SpendingPaceStatus] = [.belowPace, .onPace, .aheadOfPace]
        #expect(valid.contains(status))
    }

    @Test func paceProgressBetweenZeroAndOne() {
        let pace = SproutDate.monthPaceProgress()
        #expect(pace >= 0)
        #expect(pace <= 1)
    }

    // MARK: - Backup

    @Test func exportImportRoundTrip() throws {
        let store = makeStore()
        store.setBudget(350, for: .personal)
        let draft = TransactionDraft(name: "Test", amountText: "25", selectedEmoji: "🧪")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        let data = try store.exportBackupData()
        let store2 = makeStore()
        try store2.importBackupData(data)

        #expect(store2.budget(for: .personal) == 350)
        #expect(store2.transactions(for: .personal).count == 1)
        #expect(store2.transactions(for: .personal).first?.name == "Test")
    }

    // MARK: - SproutDate Helpers

    @Test func currentMonthKeyFormat() {
        let key = SproutDate.currentMonthKey()
        #expect(key.contains("-"))
        let parts = key.split(separator: "-")
        #expect(parts.count == 2)
        #expect(parts[0].count == 4)
        #expect(parts[1].count == 2)
    }

    @Test func dayKeyFormat() {
        let key = SproutDate.dayKey(for: Date())
        let parts = key.split(separator: "-")
        #expect(parts.count == 3)
    }

    @Test func daysLeftIsPositive() {
        let days = SproutDate.daysLeftInMonth()
        #expect(days >= 1)
    }

    @Test func monthGridDatesStartCorrectly() {
        let dates = SproutDate.monthGridDates()
        #expect(!dates.isEmpty)
        let nonNilDates = dates.compactMap { $0 }
        #expect(!nonNilDates.isEmpty)
    }

    @Test func firstAndLastDateForMonthKey() {
        let first = SproutDate.firstDate(forMonthKey: "2025-01")
        let last = SproutDate.lastDate(forMonthKey: "2025-01")
        #expect(first != nil)
        #expect(last != nil)
        if let f = first, let l = last {
            #expect(f < l)
            let dayComp = Calendar.current.component(.day, from: l)
            #expect(dayComp == 31)
        }
    }

    @Test func invalidMonthKeyReturnsNil() {
        #expect(SproutDate.firstDate(forMonthKey: "garbage") == nil)
        #expect(SproutDate.lastDate(forMonthKey: "garbage") == nil)
    }

    // MARK: - TransactionDraft Parsing

    @Test func parsedAmountHandlesDecimal() {
        var draft = TransactionDraft()
        draft.amountText = "12.50"
        #expect(draft.parsedAmount == 12.50)
    }

    @Test func parsedAmountHandlesComma() {
        var draft = TransactionDraft()
        draft.amountText = "1,200"
        #expect(draft.parsedAmount == 1200)
    }

    @Test func parsedAmountRejectsEmpty() {
        var draft = TransactionDraft()
        draft.amountText = ""
        #expect(draft.parsedAmount == nil)
    }

    @Test func parsedAmountRejectsLetters() {
        var draft = TransactionDraft()
        draft.amountText = "abc"
        #expect(draft.parsedAmount == nil)
    }
}
