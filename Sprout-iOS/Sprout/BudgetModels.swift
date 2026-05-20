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

    static let emojiOptions: [String] = [
        "🛍️", "🎁", "💄", "🍕", "🚗", "☕", "🍔", "🎬", "🎮", "💊",
        "🏥", "✂️", "🐕", "🐈", "🏠", "🔧", "📱", "💻", "📚", "🎵",
        "✈️", "🏋️", "🧹", "👕", "👟", "🎨", "🌮", "🍺", "🍷", "🧃",
        "🛒", "💡", "📦", "🎲", "🪴", "🧴", "💇", "🎂", "🎉", "⛽",
        "🚌", "🚕", "🅿️", "💰", "🏦", "📝", "🔑", "🧊", "🍿", "🎧"
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

struct BudgetSnapshot: Codable {
    var groceryBudget: Double
    var personalBudget: Double
    var groceryCarryover: Double
    var personalCarryover: Double
    var transactions: [TransactionEntry]
    var recurringRules: [RecurringTransactionRule]
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
    var date = Date()
    var isRecurring = false
    var recurringFrequency: RecurrenceFrequency = .monthly
    var recurringNextDate = RecurrenceFrequency.monthly.advanced(from: Date())

    var parsedAmount: Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let value = formatter.number(from: amountText)?.doubleValue {
            return value
        }
        let sanitized = amountText.replacingOccurrences(of: ",", with: "")
        return Double(sanitized)
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
