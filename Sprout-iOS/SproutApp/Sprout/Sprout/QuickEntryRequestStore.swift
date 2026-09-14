import Combine
import Foundation

struct QuickEntryRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let tab: BudgetTab
    let mode: TransactionMode
    let createdAt: Date

    init(id: UUID = UUID(), tab: BudgetTab, mode: TransactionMode, createdAt: Date = .now) {
        self.id = id
        self.tab = tab
        self.mode = mode
        self.createdAt = createdAt
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
