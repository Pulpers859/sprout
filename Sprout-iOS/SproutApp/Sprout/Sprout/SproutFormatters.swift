import Foundation

/// The single parser and serializer for user-typed money text.
///
/// Amount text used to be parsed with a locale `NumberFormatter` but written back
/// with `String(format: "%.2f", …)`, which always emits a `.` decimal separator.
/// In any locale where `.` is the *grouping* separator (de_DE, fr_FR, pt_BR, …)
/// that round trip silently multiplied the amount by 100 — a saved 12,50 came
/// back as 1.250,00. Parsing and seeding now share one representation so the
/// round trip is exact in every locale.
enum SproutMoneyText {
    /// Largest amount a single transaction or budget may hold.
    static let maximum = MoneyAmount(dollars: 999_999.99)

    enum ParseResult: Equatable {
        case valid(MoneyAmount)
        case exceedsMaximum
        case invalid
    }

    /// Parses an amount the user typed or that `editable(_:)` produced.
    ///
    /// Deliberately strict: only digits and the locale's own separators are
    /// accepted. That is what rejects `"-5"`, `"1e9"`, and `"Infinity"` — the last
    /// of which `Double.init` happily produces and `Int(_:)` then traps on.
    /// `locale` is injectable so the round trip can be tested in the locales where
    /// it actually broke, not only wherever the test runner happens to be set.
    static func evaluate(_ text: String, locale: Locale = .current) -> ParseResult {
        // A locale can report an empty separator; falling through to "" would make
        // the allowed-character set and the replacements below meaningless.
        let decimalSeparator = locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        let groupingSeparator = locale.groupingSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? ","

        let candidate = stripped(text, locale: locale)
        guard !candidate.isEmpty else { return .invalid }

        var allowed = CharacterSet(charactersIn: "0123456789")
        allowed.formUnion(CharacterSet(charactersIn: decimalSeparator))
        allowed.formUnion(CharacterSet(charactersIn: groupingSeparator))
        // The strict scan only knows Latin digits. A locale whose default
        // numbering system is not `latn` — Arabic-Indic, Devanagari, Bengali —
        // produces digits from the user's own keyboard that this would reject,
        // with a "greater than zero" error for a perfectly good amount. Hand
        // those to NumberFormatter, which understands the locale's own digits.
        guard candidate.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return evaluateWithLocaleFormatter(candidate, locale: locale)
        }

        var normalized = candidate
        if groupingSeparator != decimalSeparator {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }
        normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")

        guard normalized.filter({ $0 == "." }).count <= 1 else { return .invalid }
        guard let dollars = Double(normalized), dollars.isFinite, dollars > 0 else { return .invalid }
        guard dollars <= maximum.dollars else { return .exceedsMaximum }

        return .valid(MoneyAmount(dollars: dollars))
    }

    /// Removes currency decoration and grouping whitespace. Shared so every
    /// caller normalizes identically.
    private static func stripped(_ text: String, locale: Locale) -> String {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for symbol in [locale.currencySymbol, locale.currency?.identifier].compactMap({ $0 }) where !symbol.isEmpty {
            candidate = candidate.replacingOccurrences(of: symbol, with: "")
        }
        // Several locales group with a space; users type the plain one.
        return candidate
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The digits of an amount, with separators removed.
    private static func normalizedDigits(_ text: String, locale: Locale) -> String {
        let decimalSeparator = locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        let groupingSeparator = locale.groupingSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? ","
        var value = stripped(text, locale: locale)
        if groupingSeparator != decimalSeparator {
            value = value.replacingOccurrences(of: groupingSeparator, with: "")
        }
        return value.replacingOccurrences(of: decimalSeparator, with: "")
    }

    /// Fallback for non-Latin numbering systems. Still refuses anything the
    /// formatter does not consume in full, so trailing text cannot sneak through.
    private static func evaluateWithLocaleFormatter(_ candidate: String, locale: Locale) -> ParseResult {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.isLenient = false

        guard let number = formatter.number(from: candidate) else { return .invalid }
        let dollars = number.doubleValue
        guard dollars.isFinite, dollars > 0 else { return .invalid }
        guard dollars <= maximum.dollars else { return .exceedsMaximum }
        return .valid(MoneyAmount(dollars: dollars))
    }

    /// True when the text is a well-formed zero. `evaluate` rejects zero because
    /// no transaction may be zero, but a zero *budget* is a legitimate choice.
    static func isZeroAmount(_ text: String, locale: Locale = .current) -> Bool {
        let digits = normalizedDigits(text, locale: locale)
        return !digits.isEmpty && digits.allSatisfy { $0 == "0" }
    }

    static func parse(_ text: String, locale: Locale = .current) -> MoneyAmount? {
        if case .valid(let amount) = evaluate(text, locale: locale) { return amount }
        return nil
    }

    /// Seed text for an editable amount field, always with two decimal places and
    /// no grouping, using the locale's own decimal separator so `evaluate` reads
    /// it back to the identical cents value.
    static func editable(_ money: MoneyAmount, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        let cents = abs(money.cents)
        let sign = money.cents < 0 ? "-" : ""
        return "\(sign)\(cents / 100)\(separator)\(String(format: "%02d", cents % 100))"
    }

    /// Same as `editable(_:)` but drops a `.00` tail, for fields where a whole
    /// budget figure reads better than a padded one.
    static func editableWhole(_ money: MoneyAmount, locale: Locale = .current) -> String {
        money.cents % 100 == 0 ? String(money.cents / 100) : editable(money, locale: locale)
    }
}

enum SproutFormatters {
    /// Formatters are rebuilt when the device locale changes, so a region switch
    /// mid-session does not leave the app formatting in the previous currency.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var localeIdentifier = ""
        private var currency = NumberFormatter()
        private var compact = NumberFormatter()

        func withFormatters<T>(_ body: (NumberFormatter, NumberFormatter) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }

            let locale = Locale.current
            if locale.identifier != localeIdentifier {
                localeIdentifier = locale.identifier

                let currencyFormatter = NumberFormatter()
                currencyFormatter.numberStyle = .currency
                currencyFormatter.locale = locale
                currency = currencyFormatter

                let compactFormatter = NumberFormatter()
                compactFormatter.numberStyle = .currency
                compactFormatter.locale = locale
                compactFormatter.maximumFractionDigits = 0
                compactFormatter.minimumFractionDigits = 0
                compact = compactFormatter
            }

            return body(currency, compact)
        }
    }

    private static let cache = Cache()

    static var currencySymbol: String {
        cache.withFormatters { currency, _ in currency.currencySymbol ?? "$" }
    }

    static func currency(_ money: MoneyAmount) -> String {
        cache.withFormatters { currency, _ in
            currency.string(from: NSNumber(value: money.dollars)) ?? "$0.00"
        }
    }

    /// Whole-dollar rendering for dense surfaces like calendar cells. Anything
    /// with a cents tail, and anything under a whole unit, keeps its full format
    /// so a $0.40 day never reads as "$0" and $12.50 never rounds to "$13".
    static func compactCurrency(_ money: MoneyAmount) -> String {
        guard money == .zero || (money.magnitude.cents >= 100 && money.cents % 100 == 0) else {
            return currency(money)
        }

        return cache.withFormatters { currency, compact in
            compact.string(from: NSNumber(value: money.dollars))
                ?? currency.string(from: NSNumber(value: money.dollars))
                ?? "$0"
        }
    }
}
