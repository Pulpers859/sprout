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
        #expect(store.baseBudget(for: .personal).dollars == 500)
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

    @Test func setBudgetSetsTheRecurringBudgetAndLeavesCarryoverAlone() {
        // The editor used to take base + carryover and back a new base out of it,
        // so a one-month bump permanently moved the recurring budget and the drift
        // compounded. It now sets the monthly budget directly; carryover is added
        // on top and is not the editor's business.
        let store = makeStore()
        store.resetMonth(carryOverRemainders: true)
        let carryover = store.carryover(for: .personal)

        store.setBudget(MoneyAmount(dollars: 500), for: .personal)
        #expect(store.carryover(for: .personal) == carryover)
        #expect(store.baseBudget(for: .personal).dollars == 500)
        #expect(store.budget(for: .personal) == MoneyAmount(dollars: 500) + carryover)
    }

    @Test func aBudgetBelowTheCarryoverNoLongerZerosTheRecurringBudget() {
        // The old branch set the base to zero forever and silently deleted the
        // difference in carryover, so "tighten up to $100 this month" wiped out
        // the standing budget with nothing on screen to say so.
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 200), for: .personal)
        let draft = TransactionDraft(name: "Light month", amountText: "20.00", selectedEmoji: "🧾")
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        store.resetMonth(carryOverRemainders: true)

        let carryover = store.carryover(for: .personal)
        #expect(carryover.dollars == 180)

        store.setBudget(MoneyAmount(dollars: 100), for: .personal)
        #expect(store.baseBudget(for: .personal).dollars == 100)
        #expect(store.carryover(for: .personal) == carryover)

        // And it stays put across the next rollover rather than decaying to zero.
        store.resetMonth(carryOverRemainders: false)
        #expect(store.baseBudget(for: .personal).dollars == 100)
    }

    @Test func repeatedBudgetEditsDoNotDriftTheRecurringBudget() {
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 200), for: .personal)
        for _ in 0 ..< 4 {
            store.resetMonth(carryOverRemainders: true)
            // Re-entering the same figure the editor shows must be a no-op.
            store.setBudget(store.baseBudget(for: .personal), for: .personal)
        }
        #expect(store.baseBudget(for: .personal).dollars == 200)
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

    // MARK: - Amount text round trip

    @Test func editableAmountTextRoundTripsExactly() {
        // The bug this covers: the sheets used to normalize the typed amount with
        // `String(format: "%.2f", …)`, which always writes a "." separator. Any
        // locale that groups with "." then re-read it as a hundredfold larger
        // amount. Whatever the device locale, the seed text the app writes must
        // parse back to the identical cents.
        for cents in [1, 99, 100, 1250, 99_999, 99_999_999] {
            let amount = MoneyAmount(cents: cents)
            let text = SproutMoneyText.editable(amount)
            #expect(SproutMoneyText.parse(text)?.cents == cents, "round trip failed for \(text)")
        }
    }

    @Test func editableWholeDropsEmptyCents() {
        #expect(SproutMoneyText.editableWhole(MoneyAmount(cents: 40_000)) == "400")
        #expect(SproutMoneyText.parse(SproutMoneyText.editableWhole(MoneyAmount(cents: 40_050)))?.cents == 40_050)
    }

    @Test func parserRejectsNonFiniteAndNegativeText() {
        // `Double("Infinity")` succeeds and `Int(Double.infinity)` is a runtime
        // trap, so this string used to crash the app from the amount field.
        for text in ["Infinity", "-Infinity", "inf", "nan", "-5", "1e9", "12.3.4", "", "   ", "abc"] {
            #expect(SproutMoneyText.parse(text) == nil, "expected \(text) to be rejected")
        }
    }

    @Test func parserFlagsOverMaximumSeparately() {
        #expect(SproutMoneyText.evaluate("1000000") == .exceedsMaximum)
        #expect(SproutMoneyText.evaluate("999999.99") == .valid(SproutMoneyText.maximum))
    }

    @Test func moneyFromNonFiniteDollarsIsZeroNotATrap() {
        // `Int(Double.infinity)` and `Int(Double.nan)` are runtime traps, and
        // "Infinity" is a string a user can paste into the amount field. Zero
        // rather than a clamp: an unparseable amount must not silently become the
        // largest amount the app can hold.
        #expect(MoneyAmount(dollars: .infinity).cents == 0)
        #expect(MoneyAmount(dollars: -.infinity).cents == 0)
        #expect(MoneyAmount(dollars: .nan).cents == 0)
        // Finite values outside the range carry real magnitude and sign, so those
        // are clamped instead.
        #expect(MoneyAmount(dollars: 1e18).cents == MoneyAmount.maximumStorableCents)
        #expect(MoneyAmount(dollars: -1e18).cents == -MoneyAmount.maximumStorableCents)
    }

    @Test func moneyArithmeticSaturatesInsteadOfTrapping() {
        let huge = MoneyAmount(cents: Int.max)
        #expect(huge.cents == MoneyAmount.maximumStorableCents)
        #expect((huge + huge).cents == MoneyAmount.maximumStorableCents)
        #expect((-huge - huge).cents == -MoneyAmount.maximumStorableCents)
    }

    @Test func editedTransactionKeepsItsAmount() {
        // End-to-end version of the round-trip bug: seed an edit draft from a saved
        // entry, save it untouched, and the amount must not move.
        let store = makeStore()
        let draft = TransactionDraft(name: "Coffee", amountText: "12.50", selectedEmoji: "☕️")
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        let entry = try! #require(store.transactions(for: .personal).first)
        #expect(entry.amount.cents == 1250)

        let editDraft = store.makeEditDraft(for: entry)
        #expect(store.updateTransaction(entry, with: editDraft, mode: .expense))
        #expect(store.transactions(for: .personal).first?.amount.cents == 1250)
    }

    @Test func editDraftRestoresTheCategorySelection() {
        let store = makeStore()
        let category = try! #require(store.categories(for: .personal).first)
        var draft = TransactionDraft(name: "Socks", amountText: "9.00", selectedEmoji: category.emoji)
        draft.selectedCategoryID = category.id
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))

        let entry = try! #require(store.transactions(for: .personal).first)
        #expect(store.makeEditDraft(for: entry).selectedCategoryID == category.id)
    }

    // MARK: - Stored month drives the dashboard

    @Test func dashboardFiguresFollowTheStoredMonthNotTheWallClock() {
        // The user crossed into a new month but has not answered the rollover
        // prompt. Day count, pace, calendar grid, and the header label must all
        // still describe the month the transactions belong to.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 3, 10))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let draft = TransactionDraft(name: "Books", amountText: "20.00", selectedEmoji: "📚", date: Self.makeDate(2025, 3, 5))
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.displayedMonthKey == "2025-03")

        clock.date = Self.makeDate(2025, 4, 2)
        store.refreshForCurrentDate()
        #expect(store.needsMonthResetPrompt)

        // Still on March's ledger.
        #expect(store.displayedMonthKey == "2025-03")
        #expect(store.isViewingClosedMonth)
        #expect(store.currentMonthLabel == SproutDate.monthYearTitle(forMonthKey: "2025-03", calendar: calendar))
        #expect(store.daysLeftInDisplayedMonth == 1)
        #expect(store.paceProgress() == 1)
        // 31 March days plus the leading blanks for a Saturday start.
        #expect(store.monthGridDates().compactMap { $0 }.count == 31)

        store.keepCurrentTransactions()
        #expect(store.displayedMonthKey == "2025-04")
        #expect(!store.isViewingClosedMonth)
        #expect(store.monthGridDates().compactMap { $0 }.count == 30)
    }

    @Test func progressIsFullWhenAZeroBudgetHasSpending() {
        let store = makeStore()
        store.setBudget(.zero, for: .personal)
        #expect(store.progress(for: .personal) == 0)

        let draft = TransactionDraft(name: "Snack", amountText: "3.00", selectedEmoji: "🍫")
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.progress(for: .personal) == 1)
    }

    // MARK: - Backup import safety

    @Test func importRejectsJSONThatIsNotASproutBackup() throws {
        let store = makeStore()
        let draft = TransactionDraft(name: "Keep me", amountText: "5.00", selectedEmoji: "🧾")
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))

        // Every snapshot field has a decode default, so an unrelated JSON object
        // used to decode cleanly and wipe the ledger while reporting success.
        for payload in ["{}", "{\"hello\":1}", "{\"note\":\"not sprout\"}"] {
            #expect(throws: BudgetStore.BackupNotRecognizedError.self) {
                try store.importBackupData(Data(payload.utf8))
            }
        }
        #expect(store.transactions(for: .personal).count == 1)
        #expect(store.backupSummary(for: Data("{}".utf8)) == nil)
    }

    @Test func importAcceptsARealBackupAndDescribesIt() throws {
        let source = makeStore()
        let draft = TransactionDraft(name: "Lunch", amountText: "18.25", selectedEmoji: "🥪")
        #expect(source.addTransaction(mode: .expense, draft: draft, tab: .personal))
        let data = try source.exportBackupData()

        let destination = makeStore()
        let summary = try #require(destination.backupSummary(for: data))
        #expect(summary.contains("1 transaction"))
        try destination.importBackupData(data)
        #expect(destination.netSpent(for: .personal).cents == 1825)
    }

    // MARK: - Quick entry routing

    @Test func quickEntryRouteParsesBothURLForms() {
        let host = try! #require(QuickEntryRoute(url: URL(string: "sprout://quick-add?tab=grocery&mode=payment")!))
        #expect(host.tab == .grocery)
        #expect(host.mode == .payment)

        let opaque = try! #require(QuickEntryRoute(url: URL(string: "sprout:quick-add?tab=personal")!))
        #expect(opaque.tab == .personal)
        #expect(opaque.mode == .expense)

        #expect(QuickEntryRoute(url: URL(string: "sprout://settings")!) == nil)
        #expect(QuickEntryRoute(url: URL(string: "https://quick-add")!) == nil)
    }

    @Test func staleQuickEntryRequestsAreNotReplayed() throws {
        // Its own suite, not `.standard`: the test host is the real app, whose
        // ContentView observes `UserDefaults.didChangeNotification` and consumes
        // this key the instant it is written. Sharing the suite made the test race
        // the app it runs inside.
        let suiteName = "sprout.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fresh = QuickEntryRequest(tab: .grocery, mode: .expense, createdAt: .now)
        QuickEntryRequestStore.save(fresh, defaults: defaults)
        #expect(QuickEntryRequestStore.consume(defaults: defaults)?.tab == .grocery)
        // Consuming clears the slot.
        #expect(QuickEntryRequestStore.consume(defaults: defaults) == nil)

        // A Shortcut run that never reached the app must not ambush the user with a
        // quick-add sheet on some later cold launch.
        let stale = QuickEntryRequest(tab: .grocery, mode: .expense, createdAt: Date(timeIntervalSinceNow: -3600))
        QuickEntryRequestStore.save(stale, defaults: defaults)
        #expect(QuickEntryRequestStore.consume(defaults: defaults) == nil)
        // ...and it is cleared rather than left to be retried forever.
        #expect(defaults.data(forKey: QuickEntryRequestStore.key) == nil)
    }

    // MARK: - URL scheme registration

    @Test func theQuickAddSchemeIsDeclaredInTheBundle() throws {
        // The handler in ContentView is inert unless iOS knows the app owns the
        // scheme; this asserts the Info.plist entry that makes the deep link work.
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = (types ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("sprout"))
    }

    // MARK: - Pacing and calendar honesty

    @Test func earlyMonthSpendingIsNotFlaggedAsTooFast() {
        // Day 1 of a 30-day month: even pacing is 3.3%, so a flat 2% band turned
        // the card red for any purchase over about 5% of the budget — on the first
        // day of the month, for a $10 coffee run on a $200 budget.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 4, 1))
        let store = makeStore(calendar: calendar, now: { clock.date })

        // Nothing spent yet on the 1st reads as under plan, not merely "on plan".
        // Widening both sides of the band (the first attempt at this fix) made the
        // encouraging state unreachable for the first week.
        #expect(store.spendingPaceStatus(for: .personal) == .belowPace)

        let draft = TransactionDraft(name: "Coffee", amountText: "12.00", selectedEmoji: "☕️", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.spendingPaceStatus(for: .personal) != .aheadOfPace)

        // Only the "too fast" side is damped, and only early.
        #expect(store.aheadOfPaceThreshold() > store.paceProgress() + BudgetStore.basePaceTolerance)
        #expect(store.belowPaceThreshold() == store.paceProgress() - BudgetStore.basePaceTolerance)

        // By the end of the month the damping is gone and 6% of budget is plainly
        // under plan.
        clock.date = Self.makeDate(2025, 4, 30)
        #expect(store.spendingPaceStatus(for: .personal) == .belowPace)
    }

    @Test func spendingExactlyToBudgetIsNotFlaggedOnTheLastDay() {
        // Pace is judged on the unclamped ratio. While it was clamped to 1 the
        // threshold had to sit below 1 to stay reachable, which flagged a month
        // spent precisely to budget as "spending too fast" on its final day.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 4, 30))
        let store = makeStore(calendar: calendar, now: { clock.date })
        let draft = TransactionDraft(name: "Exact", amountText: "200.00", selectedEmoji: "🧾", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.remaining(for: .personal) == .zero)
        #expect(store.spendingPaceStatus(for: .personal) != .aheadOfPace)
    }

    @Test func overspendIsStillFlaggedOnTheLastDayOfTheMonth() {
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 4, 30))
        let store = makeStore(calendar: calendar, now: { clock.date })
        let draft = TransactionDraft(name: "Blowout", amountText: "500.00", selectedEmoji: "💸", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.spendingPaceStatus(for: .personal) == .aheadOfPace)
    }

    @Test func runawayEarlyMonthSpendingIsStillFlagged() {
        // The wider early band must not swallow a real overspend.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 4, 1))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let draft = TransactionDraft(name: "Sneakers", amountText: "150.00", selectedEmoji: "👟", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.spendingPaceStatus(for: .personal) == .aheadOfPace)
    }

    @Test func transactionsOutsideTheDisplayedMonthAreCounted() {
        // "Keep" after a gap, or a back-dated entry, leaves rows that are in every
        // total but have no cell in the calendar grid. The calendar says so.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 5, 10))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let thisMonth = TransactionDraft(name: "Now", amountText: "10.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 5, 2))
        let backDated = TransactionDraft(name: "Then", amountText: "20.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 3, 2))
        #expect(store.addTransaction(mode: .expense, draft: thisMonth, tab: .personal))
        #expect(store.addTransaction(mode: .expense, draft: backDated, tab: .personal))

        #expect(store.transactionsOutsideDisplayedMonth(for: .personal) == 1)
        #expect(store.transactionsOutsideDisplayedMonth(for: .grocery) == 0)
        // Both still count toward the total the summary card shows.
        #expect(store.netSpent(for: .personal).cents == 3000)
    }

    @Test func keepAfterAGapLeavesEveryRowAccountedFor() {
        // Full "Keep" journey: skip two months, let the recurring rule catch up,
        // and confirm nothing is lost or double-counted.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 1, 5))
        let store = makeStore(calendar: calendar, now: { clock.date })

        var draft = TransactionDraft(name: "Streaming", amountText: "15.00", selectedEmoji: "📺", date: clock.date)
        draft.isRecurring = true
        draft.recurringFrequency = .monthly
        draft.recurringNextDate = TransactionDraft.defaultRecurringNextDate(from: clock.date, frequency: .monthly, calendar: calendar)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(store.netSpent(for: .personal).cents == 1500)

        clock.date = Self.makeDate(2025, 3, 10)
        store.refreshForCurrentDate()
        #expect(store.needsMonthResetPrompt)

        store.keepCurrentTransactions()
        #expect(store.displayedMonthKey == "2025-03")
        #expect(!store.needsMonthResetPrompt)
        // January's original charge plus the February and March catch-up postings.
        #expect(store.transactions(for: .personal).count == 3)
        #expect(store.netSpent(for: .personal).cents == 4500)
        // Two of them are dated outside March, which the calendar has to disclose.
        #expect(store.transactionsOutsideDisplayedMonth(for: .personal) == 2)
    }

    // MARK: - The locale bug this audit was named for

    @Test func amountRoundTripsInEveryDecimalSeparatorConvention() {
        // en_US groups with "," and decimates with "."; de_DE and fr_FR are the
        // reverse; and fr_FR groups with a narrow no-break space.
        for identifier in ["en_US", "de_DE", "fr_FR", "pt_BR", "ja_JP", "en_IN"] {
            let locale = Locale(identifier: identifier)
            for cents in [1, 50, 100, 1250, 99_999, 12_345_678] {
                let amount = MoneyAmount(cents: cents)
                let text = SproutMoneyText.editable(amount, locale: locale)
                #expect(
                    SproutMoneyText.parse(text, locale: locale)?.cents == cents,
                    "\(identifier): \(cents) serialized to \"\(text)\" and did not read back"
                )
            }
        }
    }

    @Test func theCommaDecimalCorruptionIsGone() {
        let german = Locale(identifier: "de_DE")

        // What the user types on a German keypad, and what the app now writes back.
        #expect(SproutMoneyText.parse("12,50", locale: german)?.cents == 1250)
        #expect(SproutMoneyText.editable(MoneyAmount(cents: 1250), locale: german) == "12,50")

        // The old failure, pinned so it cannot come back: the sheets normalized the
        // validated amount with `String(format: "%.2f", …)`, which always emits ".".
        // In de_DE "." is the *grouping* separator, so the store re-read that text
        // as a hundredfold larger amount — a saved 12,50 became 1.250,00.
        let oldNormalization = String(format: "%.2f", MoneyAmount(cents: 1250).dollars)
        #expect(oldNormalization == "12.50")
        #expect(SproutMoneyText.parse(oldNormalization, locale: german)?.cents == 125_000)
        #expect(SproutMoneyText.editable(MoneyAmount(cents: 1250), locale: german) != oldNormalization)
    }

    // MARK: - Second-pass fixes

    @Test func clearingACategoryNameRenamesItRatherThanDeletingIt() {
        // Normalization runs on every save, and it used to *drop* empty-label
        // categories — so clearing the name field to retype it deleted the
        // category mid-edit, and clearing the last one reset the whole set to
        // defaults. Renaming preserves the row and its id either way.
        let store = makeStore()
        let original = store.categories(for: .personal)
        let first = try! #require(original.first)

        var blanked = first
        blanked.label = "   "
        store.updateCategory(blanked)

        let after = store.categories(for: .personal)
        #expect(after.count == original.count)
        #expect(after.first?.id == first.id)
        #expect(after.first?.label == "Untitled")
    }

    @Test func blankingEveryCategoryDoesNotWipeTheSet() {
        let store = makeStore()
        let ids = store.categories(for: .personal).map(\.id)
        for category in store.categories(for: .personal) {
            var blanked = category
            blanked.label = ""
            store.updateCategory(blanked)
        }
        #expect(store.categories(for: .personal).map(\.id) == ids)
    }

    @Test func aWrongBackupImportCanBeUndone() throws {
        // Confirming an import is not the same as being able to change your mind.
        // The `.previous.json` rotation only survives until the next save, which
        // the import itself performs, so the pre-import copy is kept separately.
        let store = makeStore()
        store.setBudget(MoneyAmount(dollars: 275), for: .personal)
        let mine = TransactionDraft(name: "Mine", amountText: "31.00", selectedEmoji: "🧾")
        #expect(store.addTransaction(mode: .expense, draft: mine, tab: .personal))
        #expect(!store.canUndoImport)

        // A real but unrelated backup — the "wrong file" case.
        let other = makeStore()
        other.setBudget(MoneyAmount(dollars: 10), for: .personal)
        let theirs = TransactionDraft(name: "Theirs", amountText: "2.00", selectedEmoji: "🧾")
        #expect(other.addTransaction(mode: .expense, draft: theirs, tab: .personal))

        try store.importBackupData(try other.exportBackupData())
        #expect(store.transactions(for: .personal).map(\.name) == ["Theirs"])
        #expect(store.canUndoImport)

        try store.undoImport()
        #expect(store.transactions(for: .personal).map(\.name) == ["Mine"])
        #expect(store.budget(for: .personal).cents == 27_500)
        // The undo is spent, not repeatable.
        #expect(!store.canUndoImport)
        #expect(throws: BudgetStore.NothingToUndoError.self) { try store.undoImport() }
    }

    @Test func undoneImportSurvivesRelaunch() throws {
        let saveURL = Self.makeTempSaveURL()
        let store = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        let mine = TransactionDraft(name: "Mine", amountText: "31.00", selectedEmoji: "🧾")
        #expect(store.addTransaction(mode: .expense, draft: mine, tab: .personal))

        let other = makeStore()
        #expect(other.addTransaction(
            mode: .expense,
            draft: TransactionDraft(name: "Theirs", amountText: "2.00", selectedEmoji: "🧾"),
            tab: .personal
        ))
        try store.importBackupData(try other.exportBackupData())
        try store.undoImport()

        let reloaded = BudgetStore(fileManager: .default, calendar: .current, saveURL: saveURL)
        #expect(reloaded.transactions(for: .personal).map(\.name) == ["Mine"])
    }

    @Test func theGeneratedInfoPlistKeysSurvivedAddingOurOwn() throws {
        // Setting INFOPLIST_FILE alongside GENERATE_INFOPLIST_FILE is supposed to
        // *merge*. If it ever replaced instead, CFBundleURLTypes would be present
        // and everything Xcode generates would silently be gone — so assert both
        // halves, not just the key we added.
        let bundle = Bundle.main
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") != nil)
        #expect(bundle.object(forInfoDictionaryKey: "UILaunchScreen") != nil)
        #expect(bundle.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil)
        // Presence, not value: pinning the version here would fail on the first
        // release bump for no good reason.
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version?.isEmpty == false)
    }

    // MARK: - Month close-out data loss

    @Test func aSecondCloseOfTheSameMonthMergesRatherThanReplaces() {
        // Manual mid-month reset on Oct 14, then the real Nov 1 rollover. The
        // archive used to be keyed by month and REPLACED, so the first half of
        // October was deleted from the only copy that still held it.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 10, 14))
        let store = makeStore(calendar: calendar, now: { clock.date })

        let firstHalf = TransactionDraft(name: "Early", amountText: "10.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 10, 3))
        #expect(store.addTransaction(mode: .expense, draft: firstHalf, tab: .personal))
        store.resetMonth(carryOverRemainders: false)

        let secondHalf = TransactionDraft(name: "Late", amountText: "20.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 10, 20))
        #expect(store.addTransaction(mode: .expense, draft: secondHalf, tab: .personal))

        clock.date = Self.makeDate(2025, 11, 2)
        store.resetMonth(carryOverRemainders: false)

        let october = try! #require(store.archivedMonths.first { $0.monthKey == "2025-10" })
        #expect(Set(october.transactions.map(\.name)) == ["Early", "Late"])
    }

    @Test func anEntryDatedInTheNewMonthSurvivesTheReset() {
        // The rollover prompt is deferrable, so logging a coffee dated Oct 1 while
        // still on September's ledger is a supported state. Close-out used to
        // archive the WHOLE ledger regardless of date, burying it in September.
        let calendar = Self.gregorian
        // Created in September, so the stored month is September; moving the clock
        // to October without answering the prompt is the deferred-rollover state.
        let clock = TestClock(Self.makeDate(2025, 9, 20))
        let store = makeStore(calendar: calendar, now: { clock.date })
        #expect(store.displayedMonthKey == "2025-09")

        let september = TransactionDraft(name: "Sept thing", amountText: "15.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 9, 20))
        #expect(store.addTransaction(mode: .expense, draft: september, tab: .personal))

        clock.date = Self.makeDate(2025, 10, 1)
        let october = TransactionDraft(name: "Oct coffee", amountText: "5.00", selectedEmoji: "☕️", date: Self.makeDate(2025, 10, 1))
        #expect(store.addTransaction(mode: .expense, draft: october, tab: .personal))
        #expect(store.displayedMonthKey == "2025-09")

        store.resetMonth(carryOverRemainders: true)

        // The October entry stays live; only the September one is archived.
        #expect(store.transactions(for: .personal).map(\.name) == ["Oct coffee"])
        let archived = try! #require(store.archivedMonths.first { $0.monthKey == "2025-09" })
        #expect(archived.transactions.map(\.name) == ["Sept thing"])
        // Carryover reflects September's spending only, not the October coffee.
        #expect(store.carryover(for: .personal).dollars == 185)
    }

    @Test func skippedMonthsEachGetAnArchiveRow() {
        // resetMonth's own doc comment promises every closed month its own entry,
        // but the archive guard skipped months with nothing in them.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 1, 10))
        let store = makeStore(calendar: calendar, now: { clock.date })
        let draft = TransactionDraft(name: "January", amountText: "10.00", selectedEmoji: "🧾", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))

        clock.date = Self.makeDate(2025, 4, 5)
        store.resetMonth(carryOverRemainders: false)

        let keys = Set(store.archivedMonths.map(\.monthKey))
        #expect(keys.isSuperset(of: ["2025-01", "2025-02", "2025-03"]))
    }

    @Test func aStuckRecurringRuleConvergesInsteadOfRepostingForever() {
        // The 600-occurrence bound was a resting state, not a safety net: it left
        // the rule still due, so every foreground pass appended another 600 rows.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 6, 1))
        let store = makeStore(calendar: calendar, now: { clock.date })

        var draft = TransactionDraft(name: "Weekly", amountText: "5.00", selectedEmoji: "🔁", date: Self.makeDate(1990, 1, 1))
        draft.isRecurring = true
        draft.recurringFrequency = .weekly
        draft.recurringNextDate = Self.makeDate(1990, 1, 8)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))

        store.processRecurringTransactionsIfNeeded(referenceDate: clock.date)
        let afterFirstPass = store.transactions(for: .personal).count

        store.processRecurringTransactionsIfNeeded(referenceDate: clock.date)
        let afterSecondPass = store.transactions(for: .personal).count

        // A converged rule adds nothing on the next pass.
        #expect(afterSecondPass == afterFirstPass)
        let rule = try! #require(store.recurringRules(for: .personal).first)
        #expect(rule.nextOccurrenceDate > clock.date)
    }

    @Test func oneBadArchivedMonthDoesNotEraseTheRest() throws {
        // `try? decode([T].self)` fails the whole array on one bad element and
        // swallows it, so a single damaged row returned ZERO archived months —
        // with a success message on top.
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "personalBudget": 20_000,
            "groceryBudget": 40_000,
            "personalCarryover": 0,
            "groceryCarryover": 0,
            "transactions": [],
            "recurringRules": [],
            "currentMonth": SproutDate.currentMonthKey(),
            "personalCategories": [],
            "monthHistory": [
                ["monthKey": "2025-01", "personalBudget": 20_000, "groceryBudget": 40_000,
                 "personalCarryover": 0, "groceryCarryover": 0, "transactions": []],
                ["notAMonth": true],
                ["monthKey": "2025-02", "personalBudget": 20_000, "groceryBudget": 40_000,
                 "personalCarryover": 0, "groceryCarryover": 0, "transactions": []]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        try store.importBackupData(data)
        #expect(Set(store.archivedMonths.map(\.monthKey)) == ["2025-01", "2025-02"])
        // And the loss is reported rather than passing as a clean restore.
        #expect(store.persistenceAlert?.kind == .droppedHistoryOrRules)
    }

    // MARK: - Regressions found reviewing this audit's own changes

    @Test func aClosedMonthDoesNotAdvertiseItsWholeBalanceAsADailyAllowance() {
        // Anchoring a past month to its last day makes days-left 1 by
        // construction, so the per-day figure became the entire remaining
        // balance — the one number whose job is to say what you may spend today
        // telling you to spend all of it. The card now shows the leftover instead,
        // which `isViewingClosedMonth` is what gates.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 9, 20))
        let store = makeStore(calendar: calendar, now: { clock.date })
        let draft = TransactionDraft(name: "Sept", amountText: "100.00", selectedEmoji: "🧾", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
        #expect(!store.isViewingClosedMonth)

        clock.date = Self.makeDate(2025, 10, 3)
        #expect(store.isViewingClosedMonth)
        #expect(store.daysLeftInDisplayedMonth == 1)
        // The raw allowance still equals the remainder; the card must not present
        // it as a per-day figure while this flag is set.
        #expect(store.dailyAllowance(for: .personal) == store.remaining(for: .personal))
    }

    @Test func zeroIsRecognisedThroughTheSharedNormalization() {
        // The budget editor's own copy of this check choked on decoration the
        // shared parser strips, so a zero budget could not be entered as "$0".
        for text in ["0", "0.00", "00", "$0", "$0.00", " 0 "] {
            #expect(SproutMoneyText.isZeroAmount(text), "expected \(text) to read as zero")
        }
        for text in ["", "   ", "1", "0.01", "abc"] {
            #expect(!SproutMoneyText.isZeroAmount(text), "expected \(text) not to read as zero")
        }
    }

    @Test func amountsSurviveCurrencyDecorationAndPlainSpaces() {
        #expect(SproutMoneyText.parse("$12.50")?.cents == 1250)
        #expect(SproutMoneyText.parse("  12.50  ")?.cents == 1250)
        #expect(SproutMoneyText.parse("$1,234.56")?.cents == 123_456)
    }

    @Test func moneyStaysInsideItsRangeUnderArithmetic() {
        // Honest about what this covers: because `init(cents:)` clamps, the
        // operators' overflow branches are unreachable and this exercises the
        // clamp, not them. The invariant that matters to a user is the one below
        // — no arithmetic can produce a value outside the storable range, and
        // nothing traps.
        let big = MoneyAmount(cents: MoneyAmount.maximumStorableCents)
        let values = [MoneyAmount.zero, big, -big, MoneyAmount(cents: 1), MoneyAmount(cents: -1)]
        for lhs in values {
            for rhs in values {
                #expect(abs((lhs + rhs).cents) <= MoneyAmount.maximumStorableCents)
                #expect(abs((lhs - rhs).cents) <= MoneyAmount.maximumStorableCents)
            }
        }
        #expect((MoneyAmount.zero - big).cents == -MoneyAmount.maximumStorableCents)
        #expect((big - -big).cents == MoneyAmount.maximumStorableCents)
    }

    @Test func editableTextKeepsASign() {
        #expect(SproutMoneyText.editable(MoneyAmount(cents: -1250)).hasPrefix("-"))
        #expect(SproutMoneyText.editableWhole(MoneyAmount(cents: -40_000)) == "-400")
    }

    // MARK: - Regressions found reviewing the regression fixes

    @Test func placeholderMonthsDoNotEvictRealHistory() {
        // Force-archiving every skipped month meant a long absence manufactured
        // enough empty rows to push a year of real archives past the 12-month cap.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 1, 15))
        let store = makeStore(calendar: calendar, now: { clock.date })

        // Twelve months that each hold a transaction.
        for month in 1 ... 12 {
            clock.date = Self.makeDate(2025, month, 15)
            let draft = TransactionDraft(
                name: "Month \(month)",
                amountText: "5.00",
                selectedEmoji: "🧾",
                date: clock.date
            )
            #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
            clock.date = Self.makeDate(month == 12 ? 2026 : 2025, month == 12 ? 1 : month + 1, 2)
            store.resetMonth(carryOverRemainders: false)
        }
        #expect(store.archivedMonths.count == BudgetStore.monthHistoryLimit)

        // Now a long absence, which manufactures placeholder rows for 2026.
        clock.date = Self.makeDate(2027, 1, 5)
        store.resetMonth(carryOverRemainders: false)

        let withData = store.archivedMonths.filter { !$0.isEmpty }
        #expect(!withData.isEmpty, "placeholder months evicted every month holding data")
    }

    @Test func closingOneMonthTwiceDoesNotGrantTheBudgetTwice() {
        // `budget(for:)` is base + current carryover, so recomputing leftover on
        // each close re-granted the base: two Carry Over resets inside one month
        // silently doubled the budget.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 6, 10))
        let store = makeStore(calendar: calendar, now: { clock.date })
        store.setBudget(MoneyAmount(dollars: 200), for: .personal)

        let first = TransactionDraft(name: "First", amountText: "50.00", selectedEmoji: "🧾", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: first, tab: .personal))
        store.resetMonth(carryOverRemainders: true)
        #expect(store.carryover(for: .personal).dollars == 150)

        let second = TransactionDraft(name: "Second", amountText: "30.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 6, 20))
        #expect(store.addTransaction(mode: .expense, draft: second, tab: .personal))
        store.resetMonth(carryOverRemainders: true)

        // June granted $200 once and saw $80 of spending.
        #expect(store.carryover(for: .personal).dollars == 120)
    }

    @Test func aMergedArchiveKeepsTheBudgetTheCloseMeasuredAgainst() {
        // Taking the earlier row's budget made the archive disagree with the
        // carryover that was actually forwarded.
        let calendar = Self.gregorian
        let clock = TestClock(Self.makeDate(2025, 10, 14))
        let store = makeStore(calendar: calendar, now: { clock.date })
        store.setBudget(MoneyAmount(dollars: 200), for: .personal)
        let early = TransactionDraft(name: "Early", amountText: "20.00", selectedEmoji: "🧾", date: clock.date)
        #expect(store.addTransaction(mode: .expense, draft: early, tab: .personal))
        store.resetMonth(carryOverRemainders: false)

        store.setBudget(MoneyAmount(dollars: 500), for: .personal)
        let late = TransactionDraft(name: "Late", amountText: "30.00", selectedEmoji: "🧾", date: Self.makeDate(2025, 10, 20))
        #expect(store.addTransaction(mode: .expense, draft: late, tab: .personal))

        clock.date = Self.makeDate(2025, 11, 3)
        store.resetMonth(carryOverRemainders: true)

        let october = try! #require(store.archivedMonths.first { $0.monthKey == "2025-10" })
        #expect(october.personalBudget.dollars == 500)
        // What the archive says is left must equal what was carried forward.
        #expect(october.remaining(for: .personal) == store.carryover(for: .personal))
    }

    @Test func everyDecodeLossIsNamedInOneMessage() throws {
        // Reporting only the most severe category meant a file that lost a
        // transaction AND every recurring rule mentioned only the transaction.
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "personalBudget": 20_000,
            "groceryBudget": 40_000,
            "transactions": [["name": "broken"]],
            "recurringRules": "not an array",
            "currentMonth": SproutDate.currentMonthKey(),
            "monthHistory": []
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        let message = try #require(store.persistenceAlert?.message)
        #expect(message.localizedCaseInsensitiveContains("transaction"))
        #expect(message.localizedCaseInsensitiveContains("recurring"))
    }

    @Test func aSpaceInsideAnAmountIsRejectedRatherThanSwallowed() {
        // Stripping every plain space turned a fat-fingered "1 2" into $12.
        let enUS = Locale(identifier: "en_US")
        #expect(SproutMoneyText.parse("1 2", locale: enUS) == nil)
        #expect(SproutMoneyText.parse("12 34", locale: enUS) == nil)
        // Surrounding whitespace is still fine.
        #expect(SproutMoneyText.parse("  12.50  ", locale: enUS)?.cents == 1250)
    }

    // MARK: - Ledger invariants under random month sequences

    /// Reproducible PRNG: a failing trial has to be replayable.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Randomised sequences of the operations that move money between the live
    /// ledger and the archive, checking invariants after every step.
    ///
    /// Three consecutive rounds of this audit put a data-loss bug in the month
    /// close-out path, and each time the hand-picked example tests passed. The
    /// bugs were all invariant violations — a transaction filed into the wrong
    /// month, a row evicted, a budget granted twice — so the invariants are
    /// asserted directly instead of being approximated by more examples.
    @Test func ledgerInvariantsHoldAcrossRandomMonthSequences() {
        var rng = SeededGenerator(seed: 0xC0FF_EE00_1234_5678)
        let calendar = Self.gregorian

        for trial in 0 ..< 12 {
            var year = 2025
            var month = 1
            var day = 3
            let clock = TestClock(Self.makeDate(year, month, day))
            let store = makeStore(calendar: calendar, now: { clock.date })
            var namesAdded: [String] = []

            for step in 0 ..< 14 {
                switch Int.random(in: 0 ..< 5, using: &rng) {
                case 0, 1:
                    let name = "t\(trial)-\(step)"
                    let cents = Int.random(in: 1 ... 9_000, using: &rng)
                    let draft = TransactionDraft(
                        name: name,
                        amountText: SproutMoneyText.editable(MoneyAmount(cents: cents)),
                        selectedEmoji: "🧾",
                        date: clock.date
                    )
                    let tab: BudgetTab = Bool.random(using: &rng) ? .personal : .grocery
                    if store.addTransaction(mode: .expense, draft: draft, tab: tab) {
                        namesAdded.append(name)
                    }
                case 2:
                    // Advance the clock, sometimes across a month boundary.
                    day += Int.random(in: 1 ... 20, using: &rng)
                    while day > 28 {
                        day -= 28
                        month += 1
                        if month > 12 { month = 1; year += 1 }
                    }
                    clock.date = Self.makeDate(year, month, day)
                    store.refreshForCurrentDate()
                case 3:
                    // Deliberately no "carryover <= the budget before the close"
                    // assertion here. It looks like an invariant and is not one: a
                    // mid-month Reset Fresh zeroes the live carryover while the
                    // archive still remembers what the month opened with, so a
                    // later Carry Over close of the same month legitimately returns
                    // more than the live budget. A refund can exceed it too. An
                    // assertion that fires on correct behaviour is worse than none.
                    store.resetMonth(carryOverRemainders: Bool.random(using: &rng))
                default:
                    let tab: BudgetTab = Bool.random(using: &rng) ? .personal : .grocery
                    store.setBudget(MoneyAmount(cents: Int.random(in: 0 ... 80_000, using: &rng)), for: tab)
                }

                assertLedgerInvariants(store, calendar: calendar, trial: trial, step: step)
            }

            // Nothing the user entered may simply disappear: every name is either
            // still live or preserved in an archive that has not been trimmed away.
            let live = Set(store.snapshot.transactions.map(\.name))
            let archived = Set(store.archivedMonths.flatMap { $0.transactions }.map(\.name))
            let survivingKeys = Set(store.archivedMonths.map(\.monthKey))
            for name in namesAdded where !live.contains(name) && !archived.contains(name) {
                // The only acceptable loss is a month pushed off a history that is
                // full of months which themselves hold data. Losing an entry while
                // an *empty* placeholder row is still retained is the eviction bug
                // this trial exists to catch, so that must not pass.
                #expect(
                    survivingKeys.count >= BudgetStore.monthHistoryLimit
                        && store.archivedMonths.allSatisfy { !$0.isEmpty },
                    "trial \(trial): \(name) vanished while an empty month was retained"
                )
            }
        }
    }

    private func assertLedgerInvariants(
        _ store: BudgetStore,
        calendar: Calendar,
        trial: Int,
        step: Int
    ) {
        let context = "trial \(trial) step \(step)"

        // Carryover is a leftover, so it can never be negative.
        for tab in BudgetTab.allCases {
            #expect(store.carryover(for: tab) >= .zero, "\(context): negative carryover on \(tab)")
            #expect(store.baseBudget(for: tab) >= .zero, "\(context): negative base budget on \(tab)")
        }

        // No transaction may exist twice anywhere.
        let allIDs = store.snapshot.transactions.map(\.id)
            + store.archivedMonths.flatMap { $0.transactions }.map(\.id)
        #expect(Set(allIDs).count == allIDs.count, "\(context): duplicated transaction")

        // The history cap is honoured, and month keys are unique within it.
        #expect(store.archivedMonths.count <= BudgetStore.monthHistoryLimit, "\(context): history over cap")
        let keys = store.archivedMonths.map(\.monthKey)
        #expect(Set(keys).count == keys.count, "\(context): duplicate archived month")

        // An entry may never be filed into a month earlier than its own date.
        for archived in store.archivedMonths {
            for entry in archived.transactions {
                let entryKey = SproutDate.currentMonthKey(now: entry.date, calendar: calendar)
                #expect(
                    entryKey <= archived.monthKey,
                    "\(context): \(entry.name) dated \(entryKey) filed under \(archived.monthKey)"
                )
            }
        }
    }
}
