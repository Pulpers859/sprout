import Testing
import Foundation
@testable import Sprout

/// Mutable clock so tests can cross month boundaries without touching the device date.
final class TestClock: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
struct BudgetStoreTests {

    /// Every store gets its own temp file. Previously these tests shared the real
    /// Application Support save file, which made them order-dependent and let them
    /// overwrite live data.
    private func makeStore(
        calendar: Calendar = .current,
        now: (() -> Date)? = nil
    ) -> BudgetStore {
        BudgetStore(
            fileManager: .default,
            calendar: calendar,
            saveURL: Self.makeTempSaveURL(),
            now: now ?? { Date() }
        )
    }

    private static func makeTempSaveURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SproutTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("budget-data.json")
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    // MARK: - Budget Math

    @Test func defaultBudgets() {
        let store = makeStore()
        #expect(store.budget(for: .personal).dollars == 200)
        #expect(store.budget(for: .grocery).dollars == 400)
    }

    @Test func setBudgetUpdatesTotal() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 500), for: .personal)
        #expect(store.budget(for: .personal).dollars == 500)
    }

    @Test func setBudgetRejectsNegative() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: -50), for: .personal)
        #expect(store.budget(for: .personal).dollars == 200)
    }

    @Test func netSpentWithNoTransactions() {
        let store = makeStore()
        #expect(store.netSpent(for: .personal).dollars == 0)
        #expect(store.remaining(for: .personal).dollars == 200)
    }

    @Test func netSpentSumsExpenses() {
        let store = makeStore()
        let draft1 = TransactionDraft(name: "Coffee", amountText: "5.00", selectedEmoji: "☕")
        let draft2 = TransactionDraft(name: "Lunch", amountText: "12.50", selectedEmoji: "🍕")
        _ = store.addTransaction(mode: .expense, draft: draft1, tab: .personal)
        _ = store.addTransaction(mode: .expense, draft: draft2, tab: .personal)
        #expect(store.netSpent(for: .personal).dollars == 17.50)
        #expect(store.remaining(for: .personal).dollars == 182.50)
    }

    @Test func refundReducesNetSpent() {
        let store = makeStore()
        let expense = TransactionDraft(name: "Shirt", amountText: "40", selectedEmoji: "👕")
        let refund = TransactionDraft(name: "Shirt Return", amountText: "40", selectedEmoji: "💸")
        _ = store.addTransaction(mode: .expense, draft: expense, tab: .personal)
        _ = store.addTransaction(mode: .payment, draft: refund, tab: .personal)
        #expect(store.netSpent(for: .personal).dollars == 0)
        #expect(store.remaining(for: .personal).dollars == 200)
    }

    @Test func progressClampsToZeroOne() {
        let store = makeStore()
        #expect(store.progress(for: .personal) == 0)

        store.setBudget(MoneyAmount(dollars: 100), for: .personal)
        let big = TransactionDraft(name: "Overboard", amountText: "200", selectedEmoji: "💸")
        _ = store.addTransaction(mode: .expense, draft: big, tab: .personal)
        #expect(store.progress(for: .personal) == 1)
    }

    @Test func progressZeroBudget() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 0), for: .personal)
        #expect(store.progress(for: .personal) == 0)
    }

    @Test func dailyAllowanceNeverDividesByZero() {
        let store = makeStore()
        let allowance = store.dailyAllowance(for: .personal)
        // MoneyAmount is integer-backed, so it can never be non-finite; a normal
        // month (days remaining >= 1) leaves a positive daily allowance.
        #expect(allowance > .zero)
    }

    @Test func tabsAreIndependent() {
        let store = makeStore()
        let draft = TransactionDraft(name: "Milk", amountText: "5", selectedEmoji: "🛒")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .grocery)
        #expect(store.netSpent(for: .grocery).dollars == 5)
        #expect(store.netSpent(for: .personal).dollars == 0)
    }

    // MARK: - Carryover

    @Test func setBudgetPreservesCarryover() {
        let store = makeStore()
        store.resetMonth(carryOverRemainders: true)
        let carryover = store.carryover(for: .personal)
        store.setBudget(MoneyAmount(dollars: 500), for: .personal)
        #expect(store.carryover(for: .personal) == carryover)
        #expect(store.baseBudget(for: .personal) == MoneyAmount(dollars: 500) - carryover)
    }

    @Test func setBudgetBelowCarryoverClampsCarryover() {
        let store = makeStore()
        store.resetMonth(carryOverRemainders: true)
        let carryover = store.carryover(for: .personal)
        guard carryover > .zero else { return }

        store.setBudget(carryover.dividedTruncating(by: 2), for: .personal)
        #expect(store.carryover(for: .personal) == carryover.dividedTruncating(by: 2))
        #expect(store.baseBudget(for: .personal) == .zero)
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
        #expect(store.carryover(for: .personal).dollars == 0)
        #expect(store.carryover(for: .grocery).dollars == 0)
    }

    @Test func resetCarryOverSetsPositiveRemainder() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 200), for: .personal)
        let draft = TransactionDraft(name: "Coffee", amountText: "50", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        let expectedCarry = store.remaining(for: .personal)
        store.resetMonth(carryOverRemainders: true)
        #expect(store.carryover(for: .personal) == expectedCarry)
    }

    @Test func resetCarryOverClampsNegativeToZero() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 10), for: .personal)
        let draft = TransactionDraft(name: "Big Purchase", amountText: "50", selectedEmoji: "🛍️")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.resetMonth(carryOverRemainders: true)
        #expect(store.carryover(for: .personal).dollars == 0)
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
        store.setBudget(MoneyAmount(dollars: 350), for: .personal)
        let draft = TransactionDraft(name: "Test", amountText: "25", selectedEmoji: "🧪")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        let data = try store.exportBackupData()
        let store2 = makeStore()
        try store2.importBackupData(data)

        #expect(store2.budget(for: .personal).dollars == 350)
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
        #expect(draft.parsedAmount?.dollars == 12.50)
    }

    @Test func parsedAmountHandlesComma() {
        var draft = TransactionDraft()
        draft.amountText = "1,200"
        #expect(draft.parsedAmount?.dollars == 1200)
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

    // MARK: - Multi-Month Rollover

    @Test func skippingMonthsArchivesEachMonthSeparately() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 5, 15))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let draft = TransactionDraft(name: "Coffee", amountText: "30", selectedEmoji: "☕", date: clock.date)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        #expect(store.snapshot.currentMonth == "2026-05")

        clock.date = Self.makeDate(2026, 8, 10)
        store.refreshForCurrentDate(referenceDate: clock.date)
        #expect(store.needsMonthResetPrompt)

        store.resetMonth(carryOverRemainders: true)

        #expect(store.snapshot.currentMonth == "2026-08")
        let archivedKeys = store.archivedMonths.map(\.monthKey)
        #expect(archivedKeys.contains("2026-05"))
        #expect(archivedKeys.contains("2026-06"))
        #expect(archivedKeys.contains("2026-07"))
        #expect(store.transactions(for: .personal).isEmpty)
    }

    @Test func skippedMonthRecurringChargesStayInTheirOwnMonth() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 5, 15))
        let store = makeStore(calendar: calendar, now: { clock.date })

        var draft = TransactionDraft(name: "Rent", amountText: "100", selectedEmoji: "🏠", date: Self.makeDate(2026, 5, 15))
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = Self.makeDate(2026, 6, 1)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        clock.date = Self.makeDate(2026, 7, 10)
        store.refreshForCurrentDate(referenceDate: clock.date)
        store.resetMonth(carryOverRemainders: false)

        // July must hold only July's charge — June's used to be double-counted here.
        #expect(store.snapshot.currentMonth == "2026-07")
        #expect(store.netSpent(for: .personal).dollars == 100)

        let june = store.archivedMonths.first { $0.monthKey == "2026-06" }
        #expect(june?.netSpent(for: .personal).dollars == 100)
    }

    @Test func multiMonthCarryoverCompoundsThroughEachMonth() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 5, 15))
        let store = makeStore(calendar: calendar, now: { clock.date })

        store.setBudget(MoneyAmount(dollars: 200), for: .personal)
        let draft = TransactionDraft(name: "Coffee", amountText: "50", selectedEmoji: "☕", date: clock.date)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        clock.date = Self.makeDate(2026, 7, 10)
        store.refreshForCurrentDate(referenceDate: clock.date)
        store.resetMonth(carryOverRemainders: true)

        // May leaves 150; June spends nothing against 200 base + 150 carried.
        #expect(store.carryover(for: .personal).dollars == 350)
    }

    @Test func manualMidMonthResetStillArchivesOnce() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 5, 15))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let draft = TransactionDraft(name: "Coffee", amountText: "5", selectedEmoji: "☕", date: clock.date)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        store.resetMonth(carryOverRemainders: false)

        #expect(store.snapshot.currentMonth == "2026-05")
        #expect(store.archivedMonths.filter { $0.monthKey == "2026-05" }.count == 1)
        #expect(store.transactions(for: .personal).isEmpty)
    }

    // MARK: - Recurrence Anchoring

    @Test func monthlyRecurrenceRecoversAnchorDayAfterShortMonth() {
        let calendar = Self.gregorian
        let jan31 = Self.makeDate(2026, 1, 31)

        let february = RecurrenceFrequency.monthly.advanced(from: jan31, calendar: calendar, anchorDay: 31)
        #expect(calendar.component(.day, from: february) == 28)

        // Without anchoring this stayed on the 28th for every later month.
        let march = RecurrenceFrequency.monthly.advanced(from: february, calendar: calendar, anchorDay: 31)
        #expect(calendar.component(.day, from: march) == 31)
    }

    @Test func yearlyRecurrenceHandlesLeapDayAnchor() {
        let calendar = Self.gregorian
        let leapDay = Self.makeDate(2024, 2, 29)

        let nonLeapYear = RecurrenceFrequency.yearly.advanced(from: leapDay, calendar: calendar, anchorDay: 29)
        #expect(calendar.component(.month, from: nonLeapYear) == 2)
        #expect(calendar.component(.day, from: nonLeapYear) == 28)

        // 2028 is a leap year, so the anchor is restored rather than staying at 28.
        let leapYearAgain = RecurrenceFrequency.yearly.advanced(
            from: Self.makeDate(2027, 2, 28),
            calendar: calendar,
            anchorDay: 29
        )
        #expect(calendar.component(.day, from: leapYearAgain) == 29)
    }

    @Test func recurringCatchUpAdvancesPastCutoff() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 1, 31))
        let store = makeStore(calendar: calendar, now: { clock.date })

        var draft = TransactionDraft(name: "Rent", amountText: "10", selectedEmoji: "🏠", date: Self.makeDate(2026, 1, 15))
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = Self.makeDate(2026, 1, 31)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        store.processRecurringTransactionsIfNeeded(referenceDate: clock.date)

        let rule = store.recurringRules(for: .personal).first
        #expect(rule?.anchorDay == 31)
        if let next = rule?.nextOccurrenceDate {
            #expect(next > clock.date)
        }
    }

    // MARK: - Persistence Failure Recovery

    @Test func corruptSaveFileIsQuarantinedNotOverwritten() throws {
        let saveURL = Self.makeTempSaveURL()
        try Data("{ not valid json".utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)

        #expect(store.persistenceAlert?.kind == .startedFreshAfterCorruption)

        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: saveURL.deletingLastPathComponent().path
        )
        #expect(siblings.contains { $0.hasPrefix("budget-data.corrupt-") })
    }

    @Test func corruptSaveFileFallsBackToPreviousGeneration() throws {
        let saveURL = Self.makeTempSaveURL()

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        let first = TransactionDraft(name: "Kept", amountText: "10", selectedEmoji: "☕")
        _ = store.addTransaction(mode: .expense, draft: first, tab: .personal)
        let second = TransactionDraft(name: "Newer", amountText: "20", selectedEmoji: "🍕")
        _ = store.addTransaction(mode: .expense, draft: second, tab: .personal)

        try Data("corrupted".utf8).write(to: saveURL)

        let recovered = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(recovered.persistenceAlert?.kind == .recoveredFromPreviousSave)
        #expect(recovered.transactions(for: .personal).contains { $0.name == "Kept" })
    }

    @Test func singleBadTransactionRowDoesNotDiscardWholeLedger() throws {
        let saveURL = Self.makeTempSaveURL()
        let json = """
        {
          "schemaVersion": 1,
          "groceryBudget": 400,
          "personalBudget": 200,
          "groceryCarryover": 0,
          "personalCarryover": 0,
          "currentMonth": "\(SproutDate.currentMonthKey())",
          "personalCategories": [],
          "recurringRules": [],
          "monthHistory": [],
          "updatedAt": "2026-07-01T12:00:00Z",
          "transactions": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Good",
              "amount": 12.5,
              "note": "",
              "emoji": "☕",
              "date": "2026-07-01T12:00:00Z",
              "tab": "personal",
              "isRefund": false
            },
            { "name": "Broken", "amount": "not-a-number" }
          ]
        }
        """
        try Data(json.utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)

        #expect(store.persistenceAlert?.kind == .droppedUnreadableRows(count: 1))
        #expect(store.transactions(for: .personal).count == 1)
        #expect(store.transactions(for: .personal).first?.name == "Good")
    }

    @Test func missingFileStartsCleanWithoutAlert() {
        let store = makeStore()
        #expect(store.persistenceAlert == nil)
        #expect(store.budget(for: .personal).dollars == 200)
    }

    @Test func snapshotCarriesSchemaVersion() throws {
        let store = makeStore()
        let data = try store.exportBackupData()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == BudgetSnapshot.currentSchemaVersion)
    }

    @Test func recurringRuleAnchorsToEntryDayNotDerivedNextDate() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 1, 31))
        let store = makeStore(calendar: calendar, now: { clock.date })

        // Default next date for a Jan 31 entry is already Feb 28; anchoring on that
        // would pin the rule to the 28th forever.
        let entryDate = Self.makeDate(2026, 1, 31)
        var draft = TransactionDraft(name: "Rent", amountText: "900", selectedEmoji: "🏠", date: entryDate)
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = TransactionDraft.defaultRecurringNextDate(from: entryDate, frequency: .monthly, calendar: calendar)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        #expect(store.recurringRules(for: .personal).first?.anchorDay == 31)
    }

    @Test func explicitRecurringDateOverridesAnchor() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 1, 31))
        let store = makeStore(calendar: calendar, now: { clock.date })

        var draft = TransactionDraft(name: "Gym", amountText: "40", selectedEmoji: "🏋️", date: Self.makeDate(2026, 1, 31))
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = Self.makeDate(2026, 3, 15)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        #expect(store.recurringRules(for: .personal).first?.anchorDay == 15)
    }

    @Test func storedMonthAheadOfTodayDoesNotDiscardData() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2026, 8, 10))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let draft = TransactionDraft(name: "Coffee", amountText: "25", selectedEmoji: "☕", date: clock.date)
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)
        #expect(store.snapshot.currentMonth == "2026-08")

        // Device clock moved backwards — not a real rollover.
        clock.date = Self.makeDate(2026, 6, 10)
        store.resetMonth(carryOverRemainders: false)

        #expect(store.snapshot.currentMonth == "2026-06")
        #expect(store.netSpent(for: .personal).dollars == 25)
        #expect(store.archivedMonths.isEmpty)
    }

    @Test func recoveredSnapshotSurvivesRelaunch() throws {
        let saveURL = Self.makeTempSaveURL()

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        _ = store.addTransaction(
            mode: .expense,
            draft: TransactionDraft(name: "Kept", amountText: "10", selectedEmoji: "☕"),
            tab: .personal
        )
        _ = store.addTransaction(
            mode: .expense,
            draft: TransactionDraft(name: "Newer", amountText: "20", selectedEmoji: "🍕"),
            tab: .personal
        )

        try Data("corrupted".utf8).write(to: saveURL)

        let recovered = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(recovered.transactions(for: .personal).contains { $0.name == "Kept" })

        // Relaunch without any edit: the recovery must already be on disk.
        let relaunched = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(relaunched.transactions(for: .personal).contains { $0.name == "Kept" })
        #expect(relaunched.persistenceAlert == nil)
    }

    @Test func unreadableTransactionListStillAlerts() throws {
        let saveURL = Self.makeTempSaveURL()
        let json = """
        {
          "schemaVersion": 1,
          "groceryBudget": 400,
          "personalBudget": 200,
          "groceryCarryover": 0,
          "personalCarryover": 0,
          "currentMonth": "\(SproutDate.currentMonthKey())",
          "personalCategories": [],
          "recurringRules": [],
          "monthHistory": [],
          "updatedAt": "2026-07-01T12:00:00Z",
          "transactions": "not-an-array"
        }
        """
        try Data(json.utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)

        // Budgets survived, so this is not the corrupt-file path — but the silent
        // empty ledger must still be reported.
        #expect(store.persistenceAlert != nil)
        #expect(store.budget(for: .personal).dollars == 200)
    }

    @Test func absentTransactionKeyIsNotTreatedAsDamage() throws {
        let saveURL = Self.makeTempSaveURL()
        // No "transactions" key at all — a legitimately empty ledger, not corruption.
        let json = """
        {
          "groceryBudget": 400,
          "personalBudget": 200,
          "groceryCarryover": 0,
          "personalCarryover": 0,
          "currentMonth": "\(SproutDate.currentMonthKey())",
          "personalCategories": [],
          "recurringRules": [],
          "monthHistory": [],
          "updatedAt": "2026-07-01T12:00:00Z"
        }
        """
        try Data(json.utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)

        #expect(store.persistenceAlert == nil)
        #expect(store.transactions(for: .personal).isEmpty)
    }

    @Test func legacyFileWithoutSchemaVersionStillLoads() throws {
        let saveURL = Self.makeTempSaveURL()
        let json = """
        {
          "groceryBudget": 400,
          "personalBudget": 275,
          "groceryCarryover": 0,
          "personalCarryover": 0,
          "currentMonth": "\(SproutDate.currentMonthKey())",
          "personalCategories": [],
          "recurringRules": [],
          "monthHistory": [],
          "updatedAt": "2026-07-01T12:00:00Z",
          "transactions": []
        }
        """
        try Data(json.utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(store.budget(for: .personal).dollars == 275)
        #expect(store.snapshot.schemaVersion == BudgetSnapshot.currentSchemaVersion)
    }

    @Test func legacyV1DollarsMigrateToExactCents() throws {
        let saveURL = Self.makeTempSaveURL()
        // A v1 file stored money as Double dollars. Fractional values prove the
        // migration multiplies by 100 rather than reinterpreting the number as cents.
        let json = """
        {
          "schemaVersion": 1,
          "groceryBudget": 400,
          "personalBudget": 200.50,
          "groceryCarryover": 0,
          "personalCarryover": 0,
          "currentMonth": "\(SproutDate.currentMonthKey())",
          "personalCategories": [],
          "recurringRules": [],
          "monthHistory": [],
          "updatedAt": "2026-07-01T12:00:00Z",
          "transactions": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Lunch",
              "amount": 12.34,
              "note": "",
              "emoji": "🍕",
              "date": "2026-07-01T12:00:00Z",
              "tab": "personal",
              "isRefund": false
            }
          ]
        }
        """
        try Data(json.utf8).write(to: saveURL)

        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        // $200.50 -> 20050 cents, $12.34 -> 1234 cents (not reinterpreted as cents).
        #expect(store.baseBudget(for: .personal).cents == 20050)
        #expect(store.transactions(for: .personal).first?.amount.cents == 1234)
        #expect(store.netSpent(for: .personal).cents == 1234)

        // Loading migrates and re-persists in the cents schema, so the file on disk
        // is now v2 with integer-cent money.
        let rewritten = try JSONSerialization.jsonObject(with: try Data(contentsOf: saveURL)) as? [String: Any]
        #expect(rewritten?["schemaVersion"] as? Int == 2)
        #expect(rewritten?["personalBudget"] as? Int == 20050)
    }

    @Test func v2FileRoundTripsExactCents() throws {
        let saveURL = Self.makeTempSaveURL()
        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        store.setBudget(MoneyAmount(dollars: 123.45), for: .personal)
        let draft = TransactionDraft(name: "Odd", amountText: "9.99", selectedEmoji: "🧾")
        _ = store.addTransaction(mode: .expense, draft: draft, tab: .personal)

        // A fresh store reads the on-disk v2 file back with no drift.
        let reloaded = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(reloaded.budget(for: .personal).cents == 12345)
        #expect(reloaded.netSpent(for: .personal).cents == 999)
        #expect(reloaded.remaining(for: .personal).cents == 12345 - 999)
    }
}
