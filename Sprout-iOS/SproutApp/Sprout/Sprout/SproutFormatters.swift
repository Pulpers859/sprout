import Foundation

enum SproutFormatters {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter
    }()

    static func currency(_ money: MoneyAmount) -> String {
        currencyFormatter.string(from: NSNumber(value: money.dollars)) ?? "$0.00"
    }

    static func compactCurrency(_ money: MoneyAmount) -> String {
        if money == .zero { return currencyFormatter.currencySymbol + "0" }
        let value = money.dollars
        if value < 1 { return currency(money) }
        if value == value.rounded(.down) {
            return currencyFormatter.currencySymbol + "\(Int(value))"
        }
        return currency(money)
    }
}
