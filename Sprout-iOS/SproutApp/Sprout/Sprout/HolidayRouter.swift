import Combine
import Foundation

/// Which holiday sheet or confirmation the app should show.
///
/// `ContentView` is the only place in the app that presents sheets, because
/// SwiftUI presents one sheet per view and a quick-entry request that arrives
/// while another sheet is up has to be held rather than silently dropped. The
/// holiday tab and the pushed per-person view are both descendants, so they ask
/// through this router instead of presenting for themselves — which also keeps
/// them inside `isPresentingAnySheet`.
@MainActor
final class HolidayRouter: ObservableObject {
    enum Sheet: Identifiable, Equatable {
        case addGift(recipient: GiftRecipientSelection, isReturn: Bool)
        case editGift(GiftPurchase)
        case addPerson
        case editPerson(GiftRecipient)
        case editBudget
        case renameSeason
        case startNewSeason
        case seasonHistory

        var id: String {
            switch self {
            case .addGift(let recipient, let isReturn):
                let kind = isReturn ? "return" : "gift"
                switch recipient {
                case .unspecified: "add-\(kind)-unspecified"
                case .nobody: "add-\(kind)-nobody"
                case .person(let id): "add-\(kind)-\(id.uuidString)"
                }
            case .editGift(let purchase):
                "editGift-\(purchase.id.uuidString)"
            case .addPerson:
                "addPerson"
            case .editPerson(let recipient):
                "editPerson-\(recipient.id.uuidString)"
            case .editBudget:
                "editBudget"
            case .renameSeason:
                "renameSeason"
            case .startNewSeason:
                "startNewSeason"
            case .seasonHistory:
                "seasonHistory"
            }
        }
    }

    enum Confirmation: Identifiable, Equatable {
        case removeGift(GiftPurchase)
        case removePerson(GiftRecipient)

        var id: String {
            switch self {
            case .removeGift(let purchase):
                "removeGift-\(purchase.id.uuidString)"
            case .removePerson(let recipient):
                "removePerson-\(recipient.id.uuidString)"
            }
        }
    }

    @Published var sheet: Sheet?
    @Published var confirmation: Confirmation?

    func present(_ sheet: Sheet) {
        self.sheet = sheet
    }

    func confirm(_ confirmation: Confirmation) {
        self.confirmation = confirmation
    }

    func dismiss() {
        sheet = nil
    }
}
