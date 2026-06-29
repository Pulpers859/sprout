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

    func advanced(from date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)

        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? startOfDay
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: startOfDay) ?? startOfDay
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: startOfDay) ?? startOfDay
        }
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

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        note: String = "",
        emoji: String,
        tab: BudgetTab,
        isRefund: Bool,
        frequency: RecurrenceFrequency,
        nextOccurrenceDate: Date
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

struct BudgetSnapshot: Codable {
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

    static let empty = BudgetSnapshot(
        groceryBudget: 400,
        personalBudget: 200,
        groceryCarryover: 0,
        personalCarryover: 0,
        transactions: [],
        recurringRules: [],
        monthHistory: [],
        currentMonth: SproutDate.currentMonthKey(),
        personalCategories: PersonalCategory.defaults,
        updatedAt: .now
    )

    enum CodingKeys: String, CodingKey {
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
        groceryBudget = try container.decodeIfPresent(Double.self, forKey: .groceryBudget) ?? 400
        personalBudget = try container.decodeIfPresent(Double.self, forKey: .personalBudget) ?? 200
        groceryCarryover = try container.decodeIfPresent(Double.self, forKey: .groceryCarryover) ?? 0
        personalCarryover = try container.decodeIfPresent(Double.self, forKey: .personalCarryover) ?? 0
        transactions = try container.decodeIfPresent([TransactionEntry].self, forKey: .transactions) ?? []
        recurringRules = try container.decodeIfPresent([RecurringTransactionRule].self, forKey: .recurringRules) ?? []
        monthHistory = try container.decodeIfPresent([ArchivedBudgetMonth].self, forKey: .monthHistory) ?? []
        currentMonth = try container.decodeIfPresent(String.self, forKey: .currentMonth) ?? SproutDate.currentMonthKey()
        personalCategories = try container.decodeIfPresent([PersonalCategory].self, forKey: .personalCategories) ?? PersonalCategory.defaults
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
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

    static func defaultRecurringNextDate(from date: Date, frequency: RecurrenceFrequency) -> Date {
        frequency.advanced(from: date)
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
