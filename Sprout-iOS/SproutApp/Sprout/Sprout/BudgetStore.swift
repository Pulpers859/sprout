import Combine
import Foundation

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var snapshot: BudgetSnapshot
    @Published var activeTab: BudgetTab = .personal
    @Published var selectedCalendarDate: Date?
    @Published var needsMonthResetPrompt = false

    private let fileManager: FileManager
    private let saveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let calendar: Calendar

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.saveURL = Self.makeSaveURL(fileManager: fileManager)
        self.calendar = calendar

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.snapshot = .empty
        load()
    }

    var currentMonthLabel: String {
        SproutDate.monthYearTitle()
    }

    func transactions(for tab: BudgetTab) -> [TransactionEntry] {
        snapshot.transactions
            .enumerated()
            .filter { $0.element.tab == tab }
            .sorted { lhs, rhs in
                let lhsKey = SproutDate.dayKey(for: lhs.element.date)
                let rhsKey = SproutDate.dayKey(for: rhs.element.date)
                if lhsKey == rhsKey {
                    return lhs.offset < rhs.offset
                }
                return lhsKey > rhsKey
            }
            .map(\.element)
    }

    func budget(for tab: BudgetTab) -> Double {
        baseBudget(for: tab) + carryover(for: tab)
    }

    func baseBudget(for tab: BudgetTab) -> Double {
        switch tab {
        case .personal:
            snapshot.personalBudget
        case .grocery:
            snapshot.groceryBudget
        }
    }

    func carryover(for tab: BudgetTab) -> Double {
        switch tab {
        case .personal:
            snapshot.personalCarryover
        case .grocery:
            snapshot.groceryCarryover
        }
    }

    func setBudget(_ amount: Double, for tab: BudgetTab) {
        guard amount >= 0 else { return }
        let currentCarryover = carryover(for: tab)
        let adjustedBase: Double
        let adjustedCarryover: Double

        if amount >= currentCarryover {
            adjustedBase = amount - currentCarryover
            adjustedCarryover = currentCarryover
        } else {
            adjustedBase = 0
            adjustedCarryover = amount
        }

        switch tab {
        case .personal:
            snapshot.personalBudget = adjustedBase
            snapshot.personalCarryover = adjustedCarryover
        case .grocery:
            snapshot.groceryBudget = adjustedBase
            snapshot.groceryCarryover = adjustedCarryover
        }
        persist()
    }

    func netSpent(for tab: BudgetTab) -> Double {
        transactions(for: tab).reduce(0) { partialResult, item in
            partialResult + (item.isRefund ? -item.amount : item.amount)
        }
    }

    func remaining(for tab: BudgetTab) -> Double {
        budget(for: tab) - netSpent(for: tab)
    }

    func progress(for tab: BudgetTab) -> Double {
        let budget = budget(for: tab)
        guard budget > 0 else { return 0 }
        return min(max(netSpent(for: tab), 0) / budget, 1)
    }

    func paceProgress() -> Double {
        SproutDate.monthPaceProgress()
    }

    func spendingPaceStatus(for tab: BudgetTab, tolerance: Double = 0.02) -> SpendingPaceStatus {
        let actual = progress(for: tab)
        let pace = paceProgress()

        if actual > pace + tolerance {
            return .aheadOfPace
        }
        if actual < pace - tolerance {
            return .belowPace
        }
        return .onPace
    }

    func dailyAllowance(for tab: BudgetTab) -> Double {
        remaining(for: tab) / Double(SproutDate.daysLeftInMonth())
    }

    func recentTransactions(for tab: BudgetTab) -> [TransactionEntry] {
        var seen = Set<String>()
        return transactions(for: tab)
            .filter { !$0.isRefund }
            .filter { entry in
                guard !seen.contains(entry.name) else { return false }
                seen.insert(entry.name)
                return true
            }
            .prefix(5)
            .map { $0 }
    }

    func categories(for tab: BudgetTab) -> [PersonalCategory] {
        tab == .personal ? snapshot.personalCategories : []
    }

    func recurringRules(for tab: BudgetTab) -> [RecurringTransactionRule] {
        snapshot.recurringRules
            .filter { $0.tab == tab }
            .sorted { lhs, rhs in
                if lhs.nextOccurrenceDate == rhs.nextOccurrenceDate {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.nextOccurrenceDate < rhs.nextOccurrenceDate
            }
    }

    func defaultEmoji(for tab: BudgetTab) -> String {
        switch tab {
        case .personal:
            snapshot.personalCategories.first?.emoji ?? tab.icon
        case .grocery:
            tab.icon
        }
    }

    func makeDraft(for tab: BudgetTab, mode _: TransactionMode, seed: TransactionEntry? = nil) -> TransactionDraft {
        let entryDate = Date()
        return TransactionDraft(
            name: seed?.name ?? "",
            amountText: "",
            note: "",
            selectedEmoji: seed?.emoji ?? defaultEmoji(for: tab),
            date: entryDate,
            isRecurring: false,
            recurringFrequency: .monthly,
            recurringNextDate: TransactionDraft.defaultRecurringNextDate(from: entryDate, frequency: .monthly)
        )
    }

    func addTransaction(mode: TransactionMode, draft: TransactionDraft, tab: BudgetTab) -> Bool {
        guard
            let amount = draft.parsedAmount,
            amount > 0,
            !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        let emoji: String
        if mode.isRefund {
            emoji = "💸"
        } else if tab == .grocery {
            emoji = BudgetTab.grocery.icon
        } else {
            emoji = draft.selectedEmoji
        }

        let entry = TransactionEntry(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            date: draft.date,
            tab: tab,
            isRefund: mode.isRefund
        )

        snapshot.transactions.append(entry)
        if draft.isRecurring {
            snapshot.recurringRules.append(
                RecurringTransactionRule(
                    name: entry.name,
                    amount: entry.amount,
                    note: entry.note,
                    emoji: entry.emoji,
                    tab: tab,
                    isRefund: mode.isRefund,
                    frequency: draft.recurringFrequency,
                    nextOccurrenceDate: validatedRecurringDate(
                        proposed: draft.recurringNextDate,
                        after: draft.date,
                        frequency: draft.recurringFrequency
                    )
                )
            )
        }
        persist()
        return true
    }

    func deleteTransaction(_ entry: TransactionEntry) {
        snapshot.transactions.removeAll { $0.id == entry.id }
        persist()
    }

    func removeRecurringRule(_ rule: RecurringTransactionRule) {
        snapshot.recurringRules.removeAll { $0.id == rule.id }
        persist()
    }

    func processRecurringTransactionsIfNeeded(referenceDate: Date = .now) {
        let cutoffDate = calendar.startOfDay(for: referenceDate)
        var hasChanges = false

        for index in snapshot.recurringRules.indices {
            while calendar.startOfDay(for: snapshot.recurringRules[index].nextOccurrenceDate) <= cutoffDate {
                let rule = snapshot.recurringRules[index]
                let occurrenceDate = calendar.startOfDay(for: rule.nextOccurrenceDate)

                snapshot.transactions.append(
                    TransactionEntry(
                        name: rule.name,
                        amount: rule.amount,
                        note: rule.note,
                        emoji: rule.emoji,
                        date: occurrenceDate,
                        tab: rule.tab,
                        isRefund: rule.isRefund
                    )
                )
                snapshot.recurringRules[index].nextOccurrenceDate = rule.frequency.advanced(from: occurrenceDate, calendar: calendar)
                hasChanges = true
            }
        }

        if hasChanges {
            persist()
        }
    }

    func addCategory() {
        guard snapshot.personalCategories.count < 10 else { return }
        let used = Set(snapshot.personalCategories.map(\.emoji))
        let nextEmoji = PersonalCategory.emojiOptions.first(where: { !used.contains($0) }) ?? "📌"
        snapshot.personalCategories.append(PersonalCategory(emoji: nextEmoji, label: "New"))
        persist()
    }

    func updateCategory(_ category: PersonalCategory) {
        guard let index = snapshot.personalCategories.firstIndex(where: { $0.id == category.id }) else { return }
        snapshot.personalCategories[index] = category
        persist()
    }

    func removeCategory(_ category: PersonalCategory) {
        guard snapshot.personalCategories.count > 1 else { return }
        snapshot.personalCategories.removeAll { $0.id == category.id }
        persist()
    }

    func keepCurrentTransactions() {
        snapshot.currentMonth = SproutDate.currentMonthKey()
        needsMonthResetPrompt = false
        persist()
    }

    func resetMonth(carryOverRemainders: Bool) {
        snapshot.personalCarryover = carryOverRemainders ? max(0, remaining(for: .personal)) : 0
        snapshot.groceryCarryover = carryOverRemainders ? max(0, remaining(for: .grocery)) : 0
        snapshot.transactions = []
        snapshot.currentMonth = SproutDate.currentMonthKey()
        selectedCalendarDate = nil
        needsMonthResetPrompt = false
        processRecurringTransactionsIfNeeded()
        persist()
    }

    func exportBackupData() throws -> Data {
        try encoder.encode(snapshot)
    }

    func importBackupData(_ data: Data) throws {
        var decoded = try decoder.decode(BudgetSnapshot.self, from: data)
        decoded.personalCategories = normalizedCategories(decoded.personalCategories)
        snapshot = decoded
        selectedCalendarDate = nil
        needsMonthResetPrompt = snapshot.currentMonth != SproutDate.currentMonthKey()
        processRecurringTransactionsIfNeeded()
        persist()
    }

    private func load() {
        do {
            if fileManager.fileExists(atPath: saveURL.path) {
                let data = try Data(contentsOf: saveURL)
                var decoded = try decoder.decode(BudgetSnapshot.self, from: data)
                decoded.personalCategories = normalizedCategories(decoded.personalCategories)
                snapshot = decoded
            } else {
                snapshot = .empty
                persist()
            }
        } catch {
            snapshot = .empty
        }

        processRecurringTransactionsIfNeeded()
        needsMonthResetPrompt = snapshot.currentMonth != SproutDate.currentMonthKey()
    }

    private func persist() {
        snapshot.personalCategories = normalizedCategories(snapshot.personalCategories)
        snapshot.updatedAt = .now

        do {
            let directory = saveURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(snapshot)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist Sprout data: \(error)")
        }
    }

    private func normalizedCategories(_ categories: [PersonalCategory]) -> [PersonalCategory] {
        let cleaned = categories
            .map { PersonalCategory(id: $0.id, emoji: $0.emoji, label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.label.isEmpty }

        return cleaned.isEmpty ? PersonalCategory.defaults : cleaned
    }

    private func validatedRecurringDate(proposed: Date, after entryDate: Date, frequency: RecurrenceFrequency) -> Date {
        let normalizedEntryDate = calendar.startOfDay(for: entryDate)
        let normalizedProposed = calendar.startOfDay(for: proposed)

        if normalizedProposed > normalizedEntryDate {
            return normalizedProposed
        }

        return frequency.advanced(from: normalizedEntryDate, calendar: calendar)
    }

    private static func makeSaveURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return appSupport
            .appendingPathComponent("Sprout", isDirectory: true)
            .appendingPathComponent("budget-data.json")
    }
}
