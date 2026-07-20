import Foundation

enum BudgetTab: String, Codable, CaseIterable, Identifiable {
    case personal
    case grocery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal:
            "Personal Expenses"
        case .grocery:
            "Groceries"
        }
    }

    var shortTitle: String {
        switch self {
        case .personal:
            "Personal"
        case .grocery:
            "Grocery"
        }
    }

    var icon: String {
        switch self {
        case .personal:
            "🛍️"
        case .grocery:
            "🛒"
        }
    }

    var emptyStateMessage: String {
        "No transactions yet — you're doing great! 🌿"
    }
}

enum TransactionMode: String, Identifiable, CaseIterable, Codable {
    case expense
    case payment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            "Add Expense"
        case .payment:
            "Add Payment"
        }
    }

    var prompt: String {
        switch self {
        case .expense:
            "What was it?"
        case .payment:
            "What was returned?"
        }
    }

    var symbol: String {
        switch self {
        case .expense:
            "plus.circle.fill"
        case .payment:
            "arrow.uturn.backward.circle.fill"
        }
    }

    var isRefund: Bool {
        self == .payment
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            "Every week"
        case .monthly:
            "Every month"
        case .yearly:
            "Every year"
        }
    }

    var shortTitle: String {
        switch self {
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
        case .yearly:
            "Yearly"
        }
    }

    func advanced(from date: Date, calendar: Calendar = .current, anchorDay: Int? = nil) -> Date {
        let startOfDay = calendar.startOfDay(for: date)

        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? startOfDay
        case .monthly:
            return Self.anchoredDate(byAddingMonths: 1, to: startOfDay, anchorDay: anchorDay, calendar: calendar)
        case .yearly:
            return Self.anchoredDate(byAddingMonths: 12, to: startOfDay, anchorDay: anchorDay, calendar: calendar)
        }
    }

    // Advancing from the previous occurrence loses the intended day after a short
    // month (Jan 31 -> Feb 28 -> Mar 28 forever), so the target day comes from the
    // anchor and is re-clamped against each destination month independently.
    private static func anchoredDate(byAddingMonths months: Int, to date: Date, anchorDay: Int?, calendar: Calendar) -> Date {
        let targetDay = anchorDay ?? calendar.component(.day, from: date)
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
            let targetMonthStart = calendar.date(byAdding: .month, value: months, to: monthStart),
            let dayCount = calendar.range(of: .day, in: .month, for: targetMonthStart)?.count,
            let result = calendar.date(byAdding: .day, value: min(max(targetDay, 1), dayCount) - 1, to: targetMonthStart)
        else {
            return calendar.date(byAdding: .month, value: months, to: date) ?? date
        }
        return result
    }
}

struct PersonalCategory: Codable, Hashable, Identifiable {
    var id: UUID
    var emoji: String
    var label: String

    init(id: UUID = UUID(), emoji: String, label: String) {
        self.id = id
        self.emoji = emoji
        self.label = label
    }

    static let defaults: [PersonalCategory] = [
        .init(emoji: "🛍️", label: "Shopping"),
        .init(emoji: "🎁", label: "Gifts"),
        .init(emoji: "💄", label: "Beauty"),
        .init(emoji: "🍕", label: "Dining"),
        .init(emoji: "🚗", label: "Gas")
    ]

}

struct TransactionEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: Double
    var note: String
    var emoji: String
    var date: Date
    var tab: BudgetTab
    var isRefund: Bool

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        note: String = "",
        emoji: String,
        date: Date,
        tab: BudgetTab,
        isRefund: Bool
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.note = note
        self.emoji = emoji
        self.date = date
        self.tab = tab
        self.isRefund = isRefund
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, amount, note, emoji, date, tab, isRefund
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
        emoji = try container.decode(String.self, forKey: .emoji)
        date = try container.decode(Date.self, forKey: .date)
        if let tabValue = try? container.decode(BudgetTab.self, forKey: .tab) {
            tab = tabValue
        } else if let typeValue = try? container.decode(BudgetTab.self, forKey: .type) {
            tab = typeValue
        } else {
            tab = .personal
        }
        isRefund = (try? container.decode(Bool.self, forKey: .isRefund)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(note, forKey: .note)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(date, forKey: .date)
        try container.encode(tab, forKey: .tab)
        try container.encode(isRefund, forKey: .isRefund)
    }
}

struct RecurringTransactionRule: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: Double
    var note: String
    var emoji: String
    var tab: BudgetTab
    var isRefund: Bool
    var frequency: RecurrenceFrequency
    var nextOccurrenceDate: Date
    var anchorDay: Int?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        note: String = "",
        emoji: String,
        tab: BudgetTab,
        isRefund: Bool,
        frequency: RecurrenceFrequency,
        nextOccurrenceDate: Date,
        anchorDay: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.note = note
        self.emoji = emoji
        self.tab = tab
        self.isRefund = isRefund
        self.frequency = frequency
        self.nextOccurrenceDate = nextOccurrenceDate
        self.anchorDay = anchorDay
    }
}

struct ArchivedBudgetMonth: Codable, Hashable, Identifiable {
    var monthKey: String
    var personalBudget: Double
    var groceryBudget: Double
    var personalCarryover: Double
    var groceryCarryover: Double
    var transactions: [TransactionEntry]
    var archivedAt: Date

    var id: String { monthKey }

    init(
        monthKey: String,
        personalBudget: Double,
        groceryBudget: Double,
        personalCarryover: Double,
        groceryCarryover: Double,
        transactions: [TransactionEntry],
        archivedAt: Date
    ) {
        self.monthKey = monthKey
        self.personalBudget = personalBudget
        self.groceryBudget = groceryBudget
        self.personalCarryover = personalCarryover
        self.groceryCarryover = groceryCarryover
        self.transactions = transactions
        self.archivedAt = archivedAt
    }

    // History is worth more intact than pristine: one unreadable row should cost
    // that row, not the whole archived month.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthKey = try container.decode(String.self, forKey: .monthKey)
        personalBudget = try container.decodeIfPresent(Double.self, forKey: .personalBudget) ?? 0
        groceryBudget = try container.decodeIfPresent(Double.self, forKey: .groceryBudget) ?? 0
        personalCarryover = try container.decodeIfPresent(Double.self, forKey: .personalCarryover) ?? 0
        groceryCarryover = try container.decodeIfPresent(Double.self, forKey: .groceryCarryover) ?? 0
        transactions = SproutLossyDecoding.transactions(
            in: container,
            forKey: .transactions,
            recorder: decoder.sproutDecodeIssueRecorder
        )
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt) ?? .distantPast
    }

    func budget(for tab: BudgetTab) -> Double {
        switch tab {
        case .personal:
            personalBudget + personalCarryover
        case .grocery:
            groceryBudget + groceryCarryover
        }
    }

    func netSpent(for tab: BudgetTab) -> Double {
        transactions(for: tab).reduce(0) { partialResult, item in
            partialResult + (item.isRefund ? -item.amount : item.amount)
        }
    }

    func remaining(for tab: BudgetTab) -> Double {
        budget(for: tab) - netSpent(for: tab)
    }

    func transactions(for tab: BudgetTab) -> [TransactionEntry] {
        transactions
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
}

/// Counts rows dropped during a lenient decode so the UI can tell the user that
/// data was recovered rather than silently presenting a thinner ledger.
final class SproutDecodeIssueRecorder: @unchecked Sendable {
    private(set) var droppedTransactions = 0
    private(set) var hadUnreadableTransactionList = false

    var hasIssues: Bool {
        droppedTransactions > 0 || hadUnreadableTransactionList
    }

    func recordDroppedTransaction() {
        droppedTransactions += 1
    }

    /// The array itself was unreadable, so the loss can't be counted row by row.
    func recordUnreadableTransactionList() {
        hadUnreadableTransactionList = true
    }
}

extension CodingUserInfoKey {
    static let sproutDecodeIssueRecorder = CodingUserInfoKey(rawValue: "sprout.decodeIssueRecorder")!
}

extension Decoder {
    var sproutDecodeIssueRecorder: SproutDecodeIssueRecorder? {
        userInfo[.sproutDecodeIssueRecorder] as? SproutDecodeIssueRecorder
    }
}

enum SproutLossyDecoding {
    /// Decodes each element independently so a single malformed row cannot fail
    /// the surrounding container.
    private struct Failable<Wrapped: Decodable>: Decodable {
        let value: Wrapped?

        init(from decoder: Decoder) throws {
            value = try? Wrapped(from: decoder)
        }
    }

    static func transactions<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        recorder: SproutDecodeIssueRecorder?
    ) -> [TransactionEntry] {
        // An absent or null key is a legitimately empty ledger, not damage. Conflating
        // the two would fire a "couldn't be read" alert on healthy files and make the
        // real signal worthless.
        guard container.contains(key), !((try? container.decodeNil(forKey: key)) ?? true) else {
            return []
        }

        guard let wrapped = try? container.decode([Failable<TransactionEntry>].self, forKey: key) else {
            // Present but structurally broken — never return empty silently.
            recorder?.recordUnreadableTransactionList()
            return []
        }

        for element in wrapped where element.value == nil {
            recorder?.recordDroppedTransaction()
        }
        return wrapped.compactMap(\.value)
    }
}

struct BudgetSnapshot: Codable {
    /// Bumped only when a change needs migration logic; additive fields do not
    /// require a bump because every field decodes with a default.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var groceryBudget: Double
    var personalBudget: Double
    var groceryCarryover: Double
    var personalCarryover: Double
    var transactions: [TransactionEntry]
    var recurringRules: [RecurringTransactionRule]
    var monthHistory: [ArchivedBudgetMonth]
    var currentMonth: String
    var personalCategories: [PersonalCategory]
    var updatedAt: Date

    static func makeEmpty(now: Date = .now, calendar: Calendar = .current) -> BudgetSnapshot {
        BudgetSnapshot(
            groceryBudget: 400,
            personalBudget: 200,
            groceryCarryover: 0,
            personalCarryover: 0,
            transactions: [],
            recurringRules: [],
            monthHistory: [],
            currentMonth: SproutDate.currentMonthKey(now: now, calendar: calendar),
            personalCategories: PersonalCategory.defaults,
            updatedAt: now
        )
    }

    static var empty: BudgetSnapshot { makeEmpty() }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case groceryBudget
        case personalBudget
        case groceryCarryover
        case personalCarryover
        case transactions
        case recurringRules
        case monthHistory
        case currentMonth
        case personalCategories
        case updatedAt
    }

    init(
        schemaVersion: Int = BudgetSnapshot.currentSchemaVersion,
        groceryBudget: Double,
        personalBudget: Double,
        groceryCarryover: Double,
        personalCarryover: Double,
        transactions: [TransactionEntry],
        recurringRules: [RecurringTransactionRule],
        monthHistory: [ArchivedBudgetMonth],
        currentMonth: String,
        personalCategories: [PersonalCategory],
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.groceryBudget = groceryBudget
        self.personalBudget = personalBudget
        self.groceryCarryover = groceryCarryover
        self.personalCarryover = personalCarryover
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.monthHistory = monthHistory
        self.currentMonth = currentMonth
        self.personalCategories = personalCategories
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Every field falls back rather than throwing: a snapshot that decodes
        // partially is always better than one that fails whole and strands the user
        // on defaults.
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 0
        groceryBudget = (try? container.decodeIfPresent(Double.self, forKey: .groceryBudget)) ?? 400
        personalBudget = (try? container.decodeIfPresent(Double.self, forKey: .personalBudget)) ?? 200
        groceryCarryover = (try? container.decodeIfPresent(Double.self, forKey: .groceryCarryover)) ?? 0
        personalCarryover = (try? container.decodeIfPresent(Double.self, forKey: .personalCarryover)) ?? 0
        transactions = SproutLossyDecoding.transactions(
            in: container,
            forKey: .transactions,
            recorder: decoder.sproutDecodeIssueRecorder
        )
        recurringRules = (try? container.decodeIfPresent([RecurringTransactionRule].self, forKey: .recurringRules)) ?? []
        monthHistory = (try? container.decodeIfPresent([ArchivedBudgetMonth].self, forKey: .monthHistory)) ?? []
        currentMonth = (try? container.decodeIfPresent(String.self, forKey: .currentMonth)) ?? SproutDate.currentMonthKey()
        personalCategories = (try? container.decodeIfPresent([PersonalCategory].self, forKey: .personalCategories)) ?? PersonalCategory.defaults
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .now
    }
}

struct TransactionDraft: Equatable {
    var name = ""
    var amountText = ""
    var note = ""
    var selectedEmoji = BudgetTab.personal.icon
    var selectedCategoryID: UUID?
    var date = Date()
    var isRecurring = false
    var recurringFrequency: RecurrenceFrequency = .monthly
    var recurringNextDate = RecurrenceFrequency.monthly.advanced(from: Date())

    static let maximumAmount: Double = 999_999.99

    var parsedAmount: Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let value = formatter.number(from: amountText)?.doubleValue {
            return value <= Self.maximumAmount ? value : nil
        }
        let sanitized = amountText.replacingOccurrences(of: ",", with: "")
        guard let value = Double(sanitized) else { return nil }
        return value <= Self.maximumAmount ? value : nil
    }

    var minimumRecurringDate: Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }

    static func defaultRecurringNextDate(
        from date: Date,
        frequency: RecurrenceFrequency,
        calendar: Calendar = .current
    ) -> Date {
        frequency.advanced(from: date, calendar: calendar)
    }
}

enum TransactionPresentationStyle {
    case standard
    case quickCapture
}

enum SpendingPaceStatus {
    case belowPace
    case onPace
    case aheadOfPace
}
