import Foundation

/// A top-level area of the app.
///
/// Holiday spending is deliberately **not** a `BudgetTab`. Every figure that
/// reads a `BudgetTab` — monthly totals, remaining, carryover, pace, the
/// calendar grid, month rollover, recurring rules — would otherwise be able to
/// see gift purchases, which is the one thing a separate holiday budget must
/// never do. Modelling it as its own section makes that exclusion structural
/// instead of something every call site has to remember.
enum AppSection: String, Codable, Hashable, Identifiable, CaseIterable {
    case personal
    case grocery
    case holiday

    var id: String { rawValue }

    init(budgetTab: BudgetTab) {
        switch budgetTab {
        case .personal:
            self = .personal
        case .grocery:
            self = .grocery
        }
    }

    /// The monthly budget tab this section maps to, or `nil` for sections that
    /// are not monthly budgets at all.
    var budgetTab: BudgetTab? {
        switch self {
        case .personal:
            .personal
        case .grocery:
            .grocery
        case .holiday:
            nil
        }
    }

    var shortTitle: String {
        switch self {
        case .personal:
            "Personal"
        case .grocery:
            "Grocery"
        case .holiday:
            "Holiday"
        }
    }

    var symbolName: String {
        switch self {
        case .personal:
            "person.fill"
        case .grocery:
            "cart.fill"
        case .holiday:
            "gift.fill"
        }
    }
}

/// Someone you are buying gifts for this season.
struct GiftRecipient: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    /// What you mean to spend on this person.
    ///
    /// `nil` means no target is set, which is **not** the same as a target of
    /// zero: a nil target leaves the season's budget unallocated, while a zero
    /// target says "nothing for this person". Collapsing the two would make the
    /// unallocated figure count every untargeted person as planned-$0 and read
    /// as if the whole budget were already divided up.
    var plannedAmount: MoneyAmount?
    var createdAt: Date

    static let defaultEmoji = "🎁"

    /// Offered in the picker; any emoji the keyboard can produce is accepted too.
    static let emojiChoices = [
        "🎁", "🎄", "❤️", "⭐️", "🧸", "🍪",
        "👩", "👨", "👧", "👦", "🧑", "👵",
        "👴", "🐶", "🐱", "☕️", "📚", "🎮"
    ]

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = GiftRecipient.defaultEmoji,
        plannedAmount: MoneyAmount? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.plannedAmount = plannedAmount
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, plannedAmount, createdAt
    }

    /// Only `name` is worth failing a row over — a person with no name can't be
    /// shown or picked. Everything else falls back, so a file written by a
    /// slightly different build does not cost the user a person.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        let storedEmoji = (try? container.decode(String.self, forKey: .emoji)) ?? ""
        emoji = storedEmoji.isEmpty ? Self.defaultEmoji : storedEmoji
        plannedAmount = (try? container.decodeIfPresent(MoneyAmount.self, forKey: .plannedAmount)) ?? nil
        createdAt = ((try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil) ?? .distantPast
    }
}

/// Something bought for someone, and what it cost.
struct GiftPurchase: Codable, Hashable, Identifiable {
    var id: UUID
    /// The person this was bought for.
    ///
    /// `nil` means unassigned, which happens when a stored id no longer matches
    /// anyone in the season. Unassigned purchases are still listed and still
    /// count toward the season total — a purchase whose person went missing must
    /// not become money the dashboard spends but never shows.
    var recipientID: UUID?
    var name: String
    var amount: MoneyAmount
    var note: String
    var date: Date

    init(
        id: UUID = UUID(),
        recipientID: UUID?,
        name: String,
        amount: MoneyAmount,
        note: String = "",
        date: Date
    ) {
        self.id = id
        self.recipientID = recipientID
        self.name = name
        self.amount = amount
        self.note = note
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, recipientID, name, amount, note, date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        recipientID = (try? container.decodeIfPresent(UUID.self, forKey: .recipientID)) ?? nil
        // A purchase with no description or no amount is not a purchase; those
        // two are the only reasons to drop the row.
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(MoneyAmount.self, forKey: .amount)
        note = ((try? container.decodeIfPresent(String.self, forKey: .note)) ?? nil) ?? ""
        date = ((try? container.decodeIfPresent(Date.self, forKey: .date)) ?? nil) ?? .distantPast
    }
}

/// One holiday period: its own budget, its own people, its own purchases.
///
/// Nothing in here is reachable from monthly budget arithmetic, and the monthly
/// rollover never reads or writes it, so closing out a month leaves holiday
/// spending exactly as it was.
struct HolidaySeason: Codable, Hashable, Identifiable {
    var id: UUID
    var label: String
    /// `.zero` means "no budget set yet" rather than "a budget of zero".
    ///
    /// A holiday budget of literally zero carries no useful meaning, whereas an
    /// unset one does: the dashboard invites you to set one instead of showing a
    /// $0 budget that is already fully spent and permanently red.
    var budget: MoneyAmount
    var recipients: [GiftRecipient]
    var purchases: [GiftPurchase]
    var startedAt: Date
    /// Set when the season is archived; `nil` while it is the active season.
    var closedAt: Date?

    /// How many people one season may hold. Generous enough that no real list
    /// hits it; it exists so a corrupt or hostile file cannot grow without bound.
    static let recipientLimit = 100

    init(
        id: UUID = UUID(),
        label: String,
        budget: MoneyAmount = .zero,
        recipients: [GiftRecipient] = [],
        purchases: [GiftPurchase] = [],
        startedAt: Date,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.budget = budget
        self.recipients = recipients
        self.purchases = purchases
        self.startedAt = startedAt
        self.closedAt = closedAt
    }

    static func makeEmpty(now: Date = .now, calendar: Calendar = .current) -> HolidaySeason {
        HolidaySeason(
            label: defaultLabel(now: now, calendar: calendar),
            startedAt: now
        )
    }

    static func defaultLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        "Holiday \(calendar.component(.year, from: now))"
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, budget, recipients, purchases, startedAt, closedAt
    }

    /// Element-wise, like the monthly ledger: one unreadable gift must cost that
    /// gift, not the season, and one unreadable person must not take every
    /// purchase's owner with them.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recorder = decoder.sproutDecodeIssueRecorder

        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        let storedLabel = ((try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil) ?? ""
        startedAt = ((try? container.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil) ?? .distantPast
        label = storedLabel.isEmpty ? HolidaySeason.defaultLabel(now: startedAt) : storedLabel
        budget = (try? container.decodeIfPresent(MoneyAmount.self, forKey: .budget)) ?? .zero
        recipients = SproutLossyDecoding.elements(
            GiftRecipient.self,
            in: container,
            forKey: .recipients,
            onDroppedElement: { recorder?.recordDroppedGiftRecipient() },
            onUnreadableList: { recorder?.recordUnreadableGiftRecipientList() }
        )
        purchases = SproutLossyDecoding.elements(
            GiftPurchase.self,
            in: container,
            forKey: .purchases,
            onDroppedElement: { recorder?.recordDroppedGiftPurchase() },
            onUnreadableList: { recorder?.recordUnreadableGiftPurchaseList() }
        )
        closedAt = (try? container.decodeIfPresent(Date.self, forKey: .closedAt)) ?? nil
    }

    var hasBudget: Bool { budget > .zero }

    var spent: MoneyAmount {
        purchases.reduce(.zero) { $0 + $1.amount }
    }

    var remaining: MoneyAmount { budget - spent }

    var purchaseCount: Int { purchases.count }

    /// Sum of the per-person targets that are actually set.
    var plannedTotal: MoneyAmount {
        recipients.reduce(.zero) { $0 + ($1.plannedAmount ?? .zero) }
    }

    /// Budget not yet promised to anyone. Negative when the targets overcommit it.
    var unallocated: MoneyAmount { budget - plannedTotal }

    func totalSpent(for recipientID: UUID?) -> MoneyAmount {
        purchases.reduce(.zero) { partial, purchase in
            purchase.recipientID == recipientID ? partial + purchase.amount : partial
        }
    }

    /// Newest first, with insertion order breaking ties so two gifts logged on
    /// the same day keep a stable order.
    func purchases(for recipientID: UUID?) -> [GiftPurchase] {
        purchases
            .enumerated()
            .filter { $0.element.recipientID == recipientID }
            .sorted { lhs, rhs in
                if lhs.element.date == rhs.element.date { return lhs.offset > rhs.offset }
                return lhs.element.date > rhs.element.date
            }
            .map(\.element)
    }

    /// Every gift, newest first.
    var purchasesNewestFirst: [GiftPurchase] {
        purchases
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date == rhs.element.date { return lhs.offset > rhs.offset }
                return lhs.element.date > rhs.element.date
            }
            .map(\.element)
    }

    /// Purchases whose person is missing. Surfaced in the UI so the money is
    /// never counted in the total while being absent from every list.
    var unassignedPurchaseCount: Int {
        purchases.reduce(0) { $0 + ($1.recipientID == nil ? 1 : 0) }
    }

    func recipient(with id: UUID?) -> GiftRecipient? {
        guard let id else { return nil }
        return recipients.first { $0.id == id }
    }

    /// People in the order they were added, which is the order the user built the
    /// list in. Ties fall back to the name so the order is deterministic for a
    /// file whose timestamps were lost.
    var recipientsInDisplayOrder: [GiftRecipient] {
        recipients.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

/// Typed text for a gift, parsed through the one shared money parser.
struct GiftPurchaseDraft: Equatable {
    var name = ""
    var amountText = ""
    var note = ""
    var date = Date()
    var recipientID: UUID?

    init(name: String = "", amountText: String = "", note: String = "", date: Date = Date(), recipientID: UUID? = nil) {
        self.name = name
        self.amountText = amountText
        self.note = note
        self.date = date
        self.recipientID = recipientID
    }

    /// `SproutMoneyText` is the only amount parser in the app on purpose. A
    /// second, subtly different one is how the same typed string ended up
    /// meaning two different amounts.
    var parsedAmount: MoneyAmount? { SproutMoneyText.parse(amountText) }

    var amountParseResult: SproutMoneyText.ParseResult { SproutMoneyText.evaluate(amountText) }
}

/// Typed text for a person.
struct GiftRecipientDraft: Equatable {
    var name = ""
    var emoji = GiftRecipient.defaultEmoji
    /// Empty means "no target", which is deliberately different from "0".
    var plannedAmountText = ""

    init(name: String = "", emoji: String = GiftRecipient.defaultEmoji, plannedAmountText: String = "") {
        self.name = name
        self.emoji = emoji
        self.plannedAmountText = plannedAmountText
    }

    init(recipient: GiftRecipient) {
        self.name = recipient.name
        self.emoji = recipient.emoji
        self.plannedAmountText = recipient.plannedAmount.map { SproutMoneyText.editableWhole($0) } ?? ""
    }

    var isPlannedAmountBlank: Bool {
        plannedAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `.success(nil)` is a legitimately absent target. Zero is accepted as a
    /// real target of nothing, matching the budget editor, which the shared
    /// parser refuses on its own.
    enum PlannedAmountResult: Equatable {
        case none
        case amount(MoneyAmount)
        case exceedsMaximum
        case invalid
    }

    var plannedAmountResult: PlannedAmountResult {
        if isPlannedAmountBlank { return .none }
        switch SproutMoneyText.evaluate(plannedAmountText) {
        case .valid(let amount):
            return .amount(amount)
        case .exceedsMaximum:
            return .exceedsMaximum
        case .invalid:
            return SproutMoneyText.isZeroAmount(plannedAmountText) ? .amount(.zero) : .invalid
        }
    }
}
