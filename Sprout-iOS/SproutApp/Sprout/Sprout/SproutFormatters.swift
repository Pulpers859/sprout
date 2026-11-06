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

        guard let digits = latinDigits(of: candidate, locale: locale) else { return .invalid }
        let normalized = "\(digits.whole.isEmpty ? "0" : digits.whole).\(digits.fraction.isEmpty ? "0" : digits.fraction)"

        guard let dollars = Double(normalized), dollars.isFinite, dollars > 0 else { return .invalid }
        guard dollars <= maximum.dollars else { return .exceedsMaximum }

        return .valid(MoneyAmount(dollars: dollars))
    }

    private static func isLatinDigits(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }

    /// The locale's own grouping shape: how many digits sit in the last group, and
    /// how many in each group before it. The two differ — en_IN writes 12,34,56,789.
    private static func groupingSizes(for locale: Locale) -> (last: Int, interior: Int) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let last = formatter.groupingSize > 0 ? formatter.groupingSize : 3
        let secondary = formatter.secondaryGroupingSize
        return (last, secondary > 0 ? secondary : last)
    }

    /// Splits well-formed amount text into its integer and fraction digits, or
    /// returns `nil` if the text is not well formed. Accepts only Latin digits and
    /// the locale's own separators. `evaluate` screens non-Latin digits out before
    /// calling and routes them to `NumberFormatter`; `isZeroAmount` does not, so a
    /// zero written in native digits reads as "not zero" there. That predates this
    /// and is recorded in `docs/surface-drift.md`, not fixed here.
    ///
    /// Grouping is **validated**, not stripped. Stripping it read a fat-fingered
    /// `"1,2"` as `12` — a silent tenfold mis-entry on the one field in the app
    /// where the user is typing money. `stripped(_:locale:)` feeds this the
    /// locale's own separator even where that separator is a space, so the check
    /// applies in fr_FR and the like too rather than only where it is punctuation.
    /// Web has rejected malformed grouping since its parser was written.
    private static func latinDigits(of candidate: String, locale: Locale) -> (whole: String, fraction: String)? {
        let decimalSeparator = locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        let groupingSeparator = locale.groupingSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? ","

        let sections = candidate.components(separatedBy: decimalSeparator)
        guard sections.count <= 2 else { return nil }
        let fraction = sections.count == 2 ? sections[1] : ""
        guard fraction.isEmpty || isLatinDigits(fraction) else { return nil }

        var whole = sections[0]
        // When a locale groups and points with the same character there is no way
        // to tell the two apart, and the split above has already consumed every
        // separator, so there is nothing left here to validate.
        if groupingSeparator != decimalSeparator, whole.contains(groupingSeparator) {
            let groups = whole.components(separatedBy: groupingSeparator)
            let sizes = groupingSizes(for: locale)
            guard
                groups.count >= 2,
                groups.allSatisfy(isLatinDigits),
                groups[groups.count - 1].count == sizes.last,
                (1 ... sizes.interior).contains(groups[0].count),
                groups.dropFirst().dropLast().allSatisfy({ $0.count == sizes.interior })
            else {
                return nil
            }
            whole = groups.joined()
        }

        guard whole.isEmpty || isLatinDigits(whole) else { return nil }
        // "." on its own carries no amount at all.
        guard !whole.isEmpty || !fraction.isEmpty else { return nil }
        return (whole, fraction)
    }

    /// Removes currency decoration and grouping whitespace. Shared so every
    /// caller normalizes identically.
    private static func stripped(_ text: String, locale: Locale) -> String {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for symbol in [locale.currencySymbol, locale.currency?.identifier].compactMap({ $0 }) where !symbol.isEmpty {
            candidate = candidate.replacingOccurrences(of: symbol, with: "")
        }
        let grouping = locale.groupingSeparator ?? ""
        var result = candidate

        if !grouping.isEmpty, grouping.allSatisfy(\.isWhitespace) {
            // fr_FR and a dozen others group with U+202F or U+00A0. Deleting those
            // left `latinDigits` nothing to validate, so "1 2" still read as $12 in
            // every one of them — the exact mis-entry the grouping check exists to
            // catch, silently exempt in the locales whose separator *is* a space.
            // Rewrite each kind of space to the locale's own separator and let the
            // placement check judge it, which is what web's `parseAmount` does.
            for space in [" ", "\u{00A0}", "\u{202F}"] where space != grouping {
                result = result.replacingOccurrences(of: space, with: grouping)
            }
        } else {
            // Nothing groups with a space here, so a non-breaking one is stray
            // decoration and goes. A plain space stays, so a fat-fingered "1 2"
            // fails the strict scan rather than becoming $12.
            result = result
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: "\u{202F}", with: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Well formed, not merely zero-ish. This used to strip the separators and
        // look at what was left, so a mistyped "0,0" read as a deliberate zero
        // budget — the same permissiveness `evaluate` no longer allows.
        guard let digits = latinDigits(of: stripped(text, locale: locale), locale: locale) else {
            return false
        }
        let all = digits.whole + digits.fraction
        return !all.isEmpty && all.allSatisfy { $0 == "0" }
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
