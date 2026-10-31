import Combine
import Foundation

struct QuickEntryRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let section: AppSection
    /// Not read for `.holiday`, which has no expense/payment distinction.
    let mode: TransactionMode
    let createdAt: Date

    /// The monthly budget tab, for the call sites that only understand those.
    var tab: BudgetTab { section.budgetTab ?? .personal }

    init(id: UUID = UUID(), section: AppSection, mode: TransactionMode = .expense, createdAt: Date = .now) {
        self.id = id
        self.section = section
        self.mode = mode
        self.createdAt = createdAt
    }

    init(id: UUID = UUID(), tab: BudgetTab, mode: TransactionMode, createdAt: Date = .now) {
        self.init(id: id, section: AppSection(budgetTab: tab), mode: mode, createdAt: createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, section, mode, createdAt
        case tab
    }

    /// A request already sitting in `UserDefaults` when the app updates was
    /// written as `{tab, mode}`. Requests expire after ten minutes, so this
    /// matters briefly — but silently dropping one would look like the Shortcut
    /// simply not working, so the older shape is still read.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        if let section = try? container.decode(AppSection.self, forKey: .section) {
            self.section = section
        } else if let tab = try? container.decode(BudgetTab.self, forKey: .tab) {
            self.section = AppSection(budgetTab: tab)
        } else {
            self.section = .personal
        }
        mode = (try? container.decode(TransactionMode.self, forKey: .mode)) ?? .expense
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(section, forKey: .section)
        try container.encode(mode, forKey: .mode)
        try container.encode(createdAt, forKey: .createdAt)
        // Written so a build without holiday support can still read a pending
        // request rather than treating it as corrupt.
        try container.encode(section.budgetTab ?? .personal, forKey: .tab)
    }
}

enum QuickEntryRequestStore {
    static let key = "sprout.pendingQuickEntryRequest"

    /// A Shortcut or deep link that never actually reached the app leaves a
    /// pending request behind. Without an expiry it was replayed on the next cold
    /// launch — the user opens Sprout days later and is ambushed by a quick-add
    /// sheet they asked for on Tuesday.
    static let maximumAge: TimeInterval = 10 * 60

    static func save(_ request: QuickEntryRequest, defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    static func consume(now: Date = .now, defaults: UserDefaults = .standard) -> QuickEntryRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let request = try? decoder.decode(QuickEntryRequest.self, from: data) else { return nil }
        guard abs(now.timeIntervalSince(request.createdAt)) <= maximumAge else { return nil }
        return request
    }
}

@MainActor
final class QuickEntryCoordinator: ObservableObject {
    @Published private(set) var activeRequest: QuickEntryRequest?

    func present(_ request: QuickEntryRequest) {
        activeRequest = request
    }

    func consumePendingRequestIfNeeded() {
        guard let request = QuickEntryRequestStore.consume() else { return }
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }
}
