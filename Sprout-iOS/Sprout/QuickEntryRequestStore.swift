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
    private static let defaults = UserDefaults.standard
    private static let key = "sprout.pendingQuickEntryRequest"

    static func save(_ request: QuickEntryRequest) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    static func consume() -> QuickEntryRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return try? decoder.decode(QuickEntryRequest.self, from: data)
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
