import Combine
import Foundation

/// A persistence problem worth interrupting the user for. Silent failure is the
/// one outcome a budgeting app cannot afford.
struct PersistenceAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case saveFailed
        case recoveredFromPreviousSave
        case droppedUnreadableRows(count: Int)
        case unreadableTransactionList
        case startedFreshAfterCorruption
    }

    let id = UUID()
    let kind: Kind
    let message: String

    var title: String {
        switch kind {
        case .saveFailed:
            "Couldn't save"
        case .recoveredFromPreviousSave:
            "Restored a previous save"
        case .droppedUnreadableRows:
            "Some entries couldn't be read"
        case .unreadableTransactionList:
            "Transactions couldn't be read"
        case .startedFreshAfterCorruption:
            "Started with a fresh budget"
        }
    }
}

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var snapshot: BudgetSnapshot
    @Published var activeTab: BudgetTab = .personal
    @Published var selectedCalendarDate: Date?
    @Published var needsMonthResetPrompt = false
    @Published var persistenceAlert: PersistenceAlert?

    private let fileManager: FileManager
    private let saveURL: URL
    private let previousSaveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let calendar: Calendar
    private let now: () -> Date
    private var corruptFileLeftInPlace = false

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        saveURL: URL? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        let resolvedSaveURL = saveURL ?? Self.makeSaveURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.saveURL = resolvedSaveURL
        self.previousSaveURL = resolvedSaveURL
            .deletingPathExtension()
            .appendingPathExtension("previous.json")
        self.calendar = calendar
        self.now = now

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.snapshot = .makeEmpty(now: now(), calendar: calendar)
        load()
    }

    var currentMonthLabel: String {
        SproutDate.monthYearTitle()
    }

    var archivedMonths: [ArchivedBudgetMonth] {
        snapshot.monthHistory
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

    func budget(for tab: BudgetTab) -> MoneyAmount {
        baseBudget(for: tab) + carryover(for: tab)
    }

    func baseBudget(for tab: BudgetTab) -> MoneyAmount {
        switch tab {
        case .personal:
            snapshot.personalBudget
        case .grocery:
            snapshot.groceryBudget
        }
    }

    func carryover(for tab: BudgetTab) -> MoneyAmount {
        switch tab {
        case .personal:
            snapshot.personalCarryover
        case .grocery:
            snapshot.groceryCarryover
        }
    }

    func setBudget(_ amount: MoneyAmount, for tab: BudgetTab) {
        guard amount >= .zero else { return }
        let currentCarryover = carryover(for: tab)
        let adjustedBase: MoneyAmount
        let adjustedCarryover: MoneyAmount

        if amount >= currentCarryover {
            adjustedBase = amount - currentCarryover
            adjustedCarryover = currentCarryover
        } else {
            adjustedBase = .zero
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

    func netSpent(for tab: BudgetTab) -> MoneyAmount {
        transactions(for: tab).reduce(.zero) { partialResult, item in
            partialResult + (item.isRefund ? -item.amount : item.amount)
        }
    }

    func remaining(for tab: BudgetTab) -> MoneyAmount {
        budget(for: tab) - netSpent(for: tab)
    }

    func progress(for tab: BudgetTab) -> Double {
        let budget = budget(for: tab)
        guard budget > .zero else { return 0 }
        let spent = max(netSpent(for: tab), .zero)
        return min(Double(spent.cents) / Double(budget.cents), 1)
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

    func dailyAllowance(for tab: BudgetTab) -> MoneyAmount {
        remaining(for: tab).dividedTruncating(by: SproutDate.daysLeftInMonth())
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

    /// `nil` uses the store's injected clock; tests pass an explicit date.
    func refreshForCurrentDate(referenceDate: Date? = nil) {
        let referenceDate = referenceDate ?? now()
        if requiresMonthReset(referenceDate: referenceDate) {
            processRecurringTransactionsThroughCurrentStoredMonthIfNeeded()
            needsMonthResetPrompt = true
            return
        }

        processRecurringTransactionsIfNeeded(referenceDate: referenceDate)
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
        let seedEmoji = seed?.emoji ?? defaultEmoji(for: tab)
        let matchingCategory = snapshot.personalCategories.first { $0.emoji == seedEmoji }
        return TransactionDraft(
            name: seed?.name ?? "",
            amountText: "",
            note: "",
            selectedEmoji: seedEmoji,
            selectedCategoryID: matchingCategory?.id,
            date: entryDate,
            isRecurring: false,
            recurringFrequency: .monthly,
            recurringNextDate: TransactionDraft.defaultRecurringNextDate(
                from: entryDate,
                frequency: .monthly,
                calendar: calendar
            )
        )
    }

    func addTransaction(mode: TransactionMode, draft: TransactionDraft, tab: BudgetTab) -> Bool {
        guard
            let amount = draft.parsedAmount,
            amount > .zero,
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
            let nextOccurrence = validatedRecurringDate(
                proposed: draft.recurringNextDate,
                after: draft.date,
                frequency: draft.recurringFrequency
            )
            // The anchor must come from the entry date, not the computed next date:
            // the auto-derived default for a Jan 31 entry is already Feb 28, and
            // anchoring on that would pin the rule to the 28th forever — exactly the
            // drift this is meant to prevent. Only an explicit user override retargets it.
            let defaultNextOccurrence = TransactionDraft.defaultRecurringNextDate(
                from: draft.date,
                frequency: draft.recurringFrequency,
                calendar: calendar
            )
            let anchorDay = calendar.isDate(draft.recurringNextDate, inSameDayAs: defaultNextOccurrence)
                ? calendar.component(.day, from: draft.date)
                : calendar.component(.day, from: nextOccurrence)
            snapshot.recurringRules.append(
                RecurringTransactionRule(
                    name: entry.name,
                    amount: entry.amount,
                    note: entry.note,
                    emoji: entry.emoji,
                    tab: tab,
                    isRefund: mode.isRefund,
                    frequency: draft.recurringFrequency,
                    nextOccurrenceDate: nextOccurrence,
                    anchorDay: anchorDay
                )
            )
        }
        persist()
        return true
    }

    func updateTransaction(_ entry: TransactionEntry, with draft: TransactionDraft, mode: TransactionMode) -> Bool {
        guard
            let amount = draft.parsedAmount,
            amount > .zero,
            !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let index = snapshot.transactions.firstIndex(where: { $0.id == entry.id })
        else {
            return false
        }

        let emoji: String
        if mode.isRefund {
            emoji = "💸"
        } else if entry.tab == .grocery {
            emoji = BudgetTab.grocery.icon
        } else {
            emoji = draft.selectedEmoji
        }

        snapshot.transactions[index].name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.transactions[index].amount = amount
        snapshot.transactions[index].note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.transactions[index].emoji = emoji
        snapshot.transactions[index].date = draft.date
        snapshot.transactions[index].isRefund = mode.isRefund
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

    func processRecurringTransactionsIfNeeded(referenceDate: Date? = nil) {
        processRecurringTransactions(through: referenceDate ?? now(), persistChanges: true)
    }

    private func processRecurringTransactions(through referenceDate: Date, persistChanges: Bool) {
        let cutoffDate = calendar.startOfDay(for: referenceDate)
        var hasChanges = false

        for index in snapshot.recurringRules.indices {
            // Bounds a rule whose date somehow fails to advance (e.g. an invalid
            // calendar result) so catch-up can never become an infinite loop.
            var remainingOccurrences = 600

            while
                calendar.startOfDay(for: snapshot.recurringRules[index].nextOccurrenceDate) <= cutoffDate,
                remainingOccurrences > 0
            {
                remainingOccurrences -= 1
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

                // Rules saved before anchoring existed adopt their current day as the
                // anchor, so a Jan 31 rule stops degrading to the 28th after February.
                let anchorDay = rule.anchorDay ?? calendar.component(.day, from: occurrenceDate)
                snapshot.recurringRules[index].anchorDay = anchorDay
                let nextDate = rule.frequency.advanced(
                    from: occurrenceDate,
                    calendar: calendar,
                    anchorDay: anchorDay
                )
                hasChanges = true

                // A date that fails to move forward would otherwise post the same
                // charge until the loop bound trips — 600 duplicates is worse than
                // stopping.
                guard calendar.startOfDay(for: nextDate) > occurrenceDate else {
                    snapshot.recurringRules[index].nextOccurrenceDate = nextDate
                    break
                }
                snapshot.recurringRules[index].nextOccurrenceDate = nextDate
            }
        }

        if hasChanges, persistChanges {
            persist()
        }
    }

    func addCategory() {
        guard snapshot.personalCategories.count < 10 else { return }
        snapshot.personalCategories.append(PersonalCategory(emoji: "📌", label: "New"))
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
        snapshot.currentMonth = SproutDate.currentMonthKey(now: now(), calendar: calendar)
        selectedCalendarDate = nil
        needsMonthResetPrompt = false
        processRecurringTransactionsIfNeeded(referenceDate: now())
        persist()
    }

    /// Closes out every month between the stored month and today, one at a time.
    ///
    /// Collapsing a multi-month gap into a single reset used to post the skipped
    /// months' recurring charges against the *new* month's budget and drop those
    /// months from history entirely. Walking month by month gives each period its
    /// own recurring backfill, its own archive entry, and its own carryover.
    func resetMonth(carryOverRemainders: Bool) {
        let targetMonthKey = SproutDate.currentMonthKey(now: now(), calendar: calendar)

        // Stored month is in the future — the device clock moved backwards, not a real
        // rollover. Archiving and clearing here would throw away live data, so just
        // re-sync and keep everything.
        guard snapshot.currentMonth <= targetMonthKey else {
            snapshot.currentMonth = targetMonthKey
            selectedCalendarDate = nil
            needsMonthResetPrompt = false
            persist()
            return
        }

        // A malformed stored key would otherwise spin forever; the bound is far past
        // the 12-month history cap.
        var remainingSteps = 240
        var didCloseAnyMonth = false

        while snapshot.currentMonth < targetMonthKey, remainingSteps > 0 {
            remainingSteps -= 1

            if let lastDate = SproutDate.lastDate(forMonthKey: snapshot.currentMonth, calendar: calendar) {
                processRecurringTransactions(through: lastDate, persistChanges: false)
            }

            closeOutCurrentMonth(carryOverRemainders: carryOverRemainders)
            didCloseAnyMonth = true

            guard let nextKey = SproutDate.nextMonthKey(after: snapshot.currentMonth, calendar: calendar) else {
                break
            }
            snapshot.currentMonth = nextKey
        }

        // A deliberate mid-month reset, where the walk never ran. This must not
        // double-run after the walk already closed the final month, or carryover
        // would be recomputed against an emptied month.
        if !didCloseAnyMonth {
            closeOutCurrentMonth(carryOverRemainders: carryOverRemainders)
        }

        // A reset always lands on today's month, even if the walk bailed early.
        snapshot.currentMonth = targetMonthKey

        selectedCalendarDate = nil
        needsMonthResetPrompt = false
        processRecurringTransactionsIfNeeded(referenceDate: now())
        persist()
    }

    private func closeOutCurrentMonth(carryOverRemainders: Bool) {
        archiveCurrentMonthIfNeeded()
        snapshot.personalCarryover = carryOverRemainders ? max(.zero, remaining(for: .personal)) : .zero
        snapshot.groceryCarryover = carryOverRemainders ? max(.zero, remaining(for: .grocery)) : .zero
        snapshot.transactions = []
    }

    func exportBackupData() throws -> Data {
        try encoder.encode(snapshot)
    }

    func importBackupData(_ data: Data) throws {
        let result = try decodeSnapshot(from: data)
        snapshot = result.snapshot
        // Never clear a pending save failure just because the import itself was clean.
        persistenceAlert = Self.alert(for: result.issues, context: .backupImport) ?? persistenceAlert
        selectedCalendarDate = nil
        refreshForCurrentDate(referenceDate: now())
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: saveURL.path) else {
            snapshot = .makeEmpty(now: now(), calendar: calendar)
            persist()
            finishLoad()
            return
        }

        do {
            let result = try decodeSnapshot(from: try Data(contentsOf: saveURL))
            snapshot = result.snapshot
            persistenceAlert = Self.alert(for: result.issues, context: .liveFile)
        } catch {
            // The corrupt file is evidence, not garbage: preserve it before anything
            // writes over it, then prefer the previous generation over starting empty.
            let quarantineURL = quarantineCorruptSaveFile()

            if
                let previousData = try? Data(contentsOf: previousSaveURL),
                let recovered = try? decodeSnapshot(from: previousData)
            {
                snapshot = recovered.snapshot
                persistenceAlert = PersistenceAlert(
                    kind: .recoveredFromPreviousSave,
                    message: "Your budget file couldn't be read, so Sprout restored the previous save. A copy of the damaged file was kept\(quarantineURL.map { " at \($0.lastPathComponent)" } ?? "")."
                )
            } else {
                snapshot = .makeEmpty(now: now(), calendar: calendar)
                persistenceAlert = PersistenceAlert(
                    kind: .startedFreshAfterCorruption,
                    message: "Your budget file couldn't be read and no previous save was available, so Sprout started fresh. The damaged file was kept\(quarantineURL.map { " at \($0.lastPathComponent)" } ?? "") — you can also restore from a backup in Settings."
                )
            }

            // Quarantine moved the original away, so the recovered state exists only
            // in memory until this write. Without it, quitting without making an edit
            // would come back as an empty budget with no warning at all.
            persist()
        }

        finishLoad()
    }

    private enum DecodeContext {
        case liveFile
        case backupImport
    }

    private static func alert(for issues: SproutDecodeIssueRecorder, context: DecodeContext) -> PersistenceAlert? {
        guard issues.hasIssues else { return nil }

        if issues.hadUnreadableTransactionList {
            let message: String
            switch context {
            case .liveFile:
                message = "The transaction list couldn't be read, so this month's entries are missing. Your budgets and history were kept — restoring a backup in Settings may recover them."
            case .backupImport:
                message = "Restored from backup, but its transaction list couldn't be read, so those entries are missing. Budgets and history were kept."
            }
            return PersistenceAlert(kind: .unreadableTransactionList, message: message)
        }

        let count = issues.droppedTransactions
        let plural = count == 1 ? "" : "s"
        let message: String
        switch context {
        case .liveFile:
            message = "\(count) unreadable transaction\(plural) could not be restored. Everything else was recovered."
        case .backupImport:
            message = "Restored from backup, but \(count) unreadable transaction\(plural) had to be skipped."
        }
        return PersistenceAlert(kind: .droppedUnreadableRows(count: count), message: message)
    }

    private func finishLoad() {
        snapshot.personalCategories = normalizedCategories(snapshot.personalCategories)
        snapshot.monthHistory = normalizedMonthHistory(snapshot.monthHistory)
        refreshForCurrentDate(referenceDate: now())
    }

    /// Reads only the top-level `schemaVersion` so the decoder can interpret money
    /// fields correctly. A missing version means a pre-versioned file, which stored
    /// dollars, so it is treated as v1.
    private static func peekSchemaVersion(from data: Data) -> Int {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let version = dictionary["schemaVersion"] as? Int
        else {
            return 1
        }
        return version
    }

    private func decodeSnapshot(from data: Data) throws -> (snapshot: BudgetSnapshot, issues: SproutDecodeIssueRecorder) {
        let recorder = SproutDecodeIssueRecorder()
        decoder.userInfo[.sproutDecodeIssueRecorder] = recorder
        // Money migration is driven by the file's own schema version: at v1 (or
        // with no version) amounts are Double dollars; at v2+ they are Int cents.
        decoder.userInfo[.sproutSchemaVersion] = Self.peekSchemaVersion(from: data)
        defer {
            decoder.userInfo[.sproutDecodeIssueRecorder] = nil
            decoder.userInfo[.sproutSchemaVersion] = nil
        }

        var decoded = try decoder.decode(BudgetSnapshot.self, from: data)
        decoded.schemaVersion = BudgetSnapshot.currentSchemaVersion
        decoded.personalCategories = normalizedCategories(decoded.personalCategories)
        decoded.monthHistory = normalizedMonthHistory(decoded.monthHistory)
        return (decoded, recorder)
    }

    @discardableResult
    private func quarantineCorruptSaveFile() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: now())
            .replacingOccurrences(of: ":", with: "-")
        let destination = saveURL
            .deletingLastPathComponent()
            .appendingPathComponent("budget-data.corrupt-\(stamp).json")

        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: saveURL, to: destination)
            return destination
        } catch {
            // The corrupt bytes are still sitting at saveURL. Rotating them into the
            // previous-generation slot would destroy the last good copy, so suppress
            // the next rotation.
            corruptFileLeftInPlace = true
            return nil
        }
    }

    private func persist() {
        snapshot.personalCategories = normalizedCategories(snapshot.personalCategories)
        snapshot.monthHistory = normalizedMonthHistory(snapshot.monthHistory)
        snapshot.schemaVersion = BudgetSnapshot.currentSchemaVersion
        snapshot.updatedAt = now()

        do {
            let directory = saveURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(snapshot)

            // Rotate the last known-good file first so a torn write still leaves one
            // readable generation on disk.
            if fileManager.fileExists(atPath: saveURL.path), !corruptFileLeftInPlace {
                rotatePreviousGeneration()
            }

            try data.write(to: saveURL, options: [.atomic])

            // Only now are the corrupt bytes actually gone from saveURL. Clearing the
            // flag before the write would let a failed write leave them in place with
            // rotation re-enabled, destroying the last good generation on the next save.
            corruptFileLeftInPlace = false

            if persistenceAlert?.kind == .saveFailed {
                persistenceAlert = nil
            }
        } catch {
            persistenceAlert = PersistenceAlert(
                kind: .saveFailed,
                message: "Sprout couldn't save your latest change. Check available storage — your recent entries are still on screen but are not yet saved."
            )
        }
    }

    /// Stages the copy before touching the existing generation, so a failure part
    /// way through can never leave zero backups on disk.
    private func rotatePreviousGeneration() {
        // Unique per call so two stores sharing a directory can't collide, and a
        // leaked staging file can never be mistaken for a live one.
        let staging = saveURL
            .deletingLastPathComponent()
            .appendingPathComponent("budget-data.rotating-\(UUID().uuidString).tmp")

        defer { try? fileManager.removeItem(at: staging) }
        guard (try? fileManager.copyItem(at: saveURL, to: staging)) != nil else { return }

        if fileManager.fileExists(atPath: previousSaveURL.path) {
            _ = try? fileManager.replaceItemAt(previousSaveURL, withItemAt: staging)
        } else {
            try? fileManager.moveItem(at: staging, to: previousSaveURL)
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

    private func requiresMonthReset(referenceDate: Date) -> Bool {
        snapshot.currentMonth != SproutDate.currentMonthKey(now: referenceDate, calendar: calendar)
    }

    private func archiveCurrentMonthIfNeeded() {
        guard shouldArchiveCurrentMonth else { return }

        let archivedMonth = ArchivedBudgetMonth(
            monthKey: snapshot.currentMonth,
            personalBudget: snapshot.personalBudget,
            groceryBudget: snapshot.groceryBudget,
            personalCarryover: snapshot.personalCarryover,
            groceryCarryover: snapshot.groceryCarryover,
            transactions: snapshot.transactions,
            archivedAt: now()
        )

        snapshot.monthHistory.removeAll { $0.monthKey == archivedMonth.monthKey }
        snapshot.monthHistory.append(archivedMonth)
    }

    private var shouldArchiveCurrentMonth: Bool {
        !snapshot.transactions.isEmpty || snapshot.personalCarryover > .zero || snapshot.groceryCarryover > .zero
    }

    private func processRecurringTransactionsThroughCurrentStoredMonthIfNeeded() {
        guard let lastDate = SproutDate.lastDate(forMonthKey: snapshot.currentMonth, calendar: calendar) else {
            return
        }

        processRecurringTransactionsIfNeeded(referenceDate: lastDate)
    }

    private func normalizedMonthHistory(_ history: [ArchivedBudgetMonth]) -> [ArchivedBudgetMonth] {
        var monthsByKey: [String: ArchivedBudgetMonth] = [:]

        for month in history.sorted(by: {
            if $0.monthKey == $1.monthKey {
                return $0.archivedAt > $1.archivedAt
            }
            return $0.monthKey > $1.monthKey
        }) {
            if let existing = monthsByKey[month.monthKey], existing.archivedAt >= month.archivedAt {
                continue
            }
            monthsByKey[month.monthKey] = month
        }

        return monthsByKey.values
            .sorted { lhs, rhs in
                if lhs.monthKey == rhs.monthKey {
                    return lhs.archivedAt > rhs.archivedAt
                }
                return lhs.monthKey > rhs.monthKey
            }
            .prefix(12)
            .map { $0 }
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
