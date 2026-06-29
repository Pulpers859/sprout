import Foundation

enum SproutFormatters {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter
    }()

    static func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func compactCurrency(_ value: Double) -> String {
        if value == 0 { return currencyFormatter.currencySymbol + "0" }
        if value < 1 { return currency(value) }
        if value == value.rounded(.down) {
            return currencyFormatter.currencySymbol + "\(Int(value))"
        }
        return currency(value)
    }
}
