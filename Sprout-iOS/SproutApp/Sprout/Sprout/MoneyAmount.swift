import Foundation

/// Money as an exact integer number of cents.
///
/// All budget arithmetic (sums, carryover, refunds, remaining) runs in cents so
/// it never accumulates binary floating-point error the way repeated `Double`
/// dollar addition does. `Double` appears only at the two boundaries where it is
/// unavoidable: parsing user-typed text and formatting for display.
struct MoneyAmount: Codable, Hashable, Comparable, Sendable {
    /// Signed cents. Negative values are meaningful (e.g. an over-budget remainder).
    var cents: Int

    /// Hard ceiling on any single stored amount, in cents ($1 trillion).
    ///
    /// Nothing a user can type comes close; this exists so a corrupt or hostile
    /// file can't seed a value whose sums overflow `Int` and trap at render time.
    /// Every arithmetic result is clamped back inside this range, which leaves
    /// ~1e7 headroom for summing before `Int` itself is at risk.
    static let maximumStorableCents = 100_000_000_000_000

    init(cents: Int) {
        self.cents = Self.clamped(cents)
    }

    /// Rounds to the nearest cent. Use only at the text-input boundary — never to
    /// re-derive money that is already exact in cents.
    ///
    /// Non-finite input yields zero rather than trapping: `Int(Double.nan)` and
    /// `Int(Double.infinity)` are runtime traps, and "Infinity" is a string a user
    /// can paste into the amount field.
    init(dollars: Double) {
        guard dollars.isFinite else {
            self.cents = 0
            return
        }
        let scaled = (dollars * 100).rounded()
        let ceiling = Double(Self.maximumStorableCents)
        if scaled >= ceiling {
            self.cents = Self.maximumStorableCents
        } else if scaled <= -ceiling {
            self.cents = -Self.maximumStorableCents
        } else {
            self.cents = Int(scaled)
        }
    }

    private static func clamped(_ cents: Int) -> Int {
        min(max(cents, -maximumStorableCents), maximumStorableCents)
    }

    /// Dollars for display and text seeding only. Not for arithmetic.
    var dollars: Double { Double(cents) / 100 }

    static let zero = MoneyAmount(cents: 0)

    /// Absolute value, in cents.
    var magnitude: MoneyAmount { MoneyAmount(cents: abs(cents)) }

    static func < (lhs: MoneyAmount, rhs: MoneyAmount) -> Bool { lhs.cents < rhs.cents }

    // Saturating rather than trapping. Values are already clamped on the way in,
    // so overflow is only reachable by summing an implausible number of rows —
    // and a budgeting app must not crash on arithmetic it can clamp instead.
    static func + (lhs: MoneyAmount, rhs: MoneyAmount) -> MoneyAmount {
        let (sum, overflowed) = lhs.cents.addingReportingOverflow(rhs.cents)
        return MoneyAmount(cents: overflowed ? (lhs.cents > 0 ? Int.max : Int.min) : sum)
    }

    static func - (lhs: MoneyAmount, rhs: MoneyAmount) -> MoneyAmount {
        let (difference, overflowed) = lhs.cents.subtractingReportingOverflow(rhs.cents)
        return MoneyAmount(cents: overflowed ? (lhs.cents > 0 ? Int.max : Int.min) : difference)
    }

    static prefix func - (value: MoneyAmount) -> MoneyAmount { MoneyAmount(cents: -value.cents) }
    static func += (lhs: inout MoneyAmount, rhs: MoneyAmount) { lhs = lhs + rhs }
    static func -= (lhs: inout MoneyAmount, rhs: MoneyAmount) { lhs = lhs - rhs }

    /// Divides the amount into an integer per-part cents value, truncating any
    /// sub-cent remainder. Used for display-only figures like a daily allowance.
    func dividedTruncating(by divisor: Int) -> MoneyAmount {
        guard divisor != 0 else { return .zero }
        return MoneyAmount(cents: cents / divisor)
    }

    // Canonical on-disk form (schema v2+) is Int cents. A pre-v2 file stored
    // dollars as a Double, so migration is driven by the schema version the store
    // injects into the decoder's userInfo: the JSON value alone is ambiguous
    // (`400` is $400 as a v1 Double but $4.00 as v2 cents).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if decoder.sproutSchemaVersion >= 2 {
            self.init(cents: try container.decode(Int.self))
        } else {
            self.init(dollars: try container.decode(Double.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cents)
    }
}

extension CodingUserInfoKey {
    /// Carries the on-disk schema version of the payload being decoded so
    /// `MoneyAmount` can interpret legacy dollar values correctly.
    static let sproutSchemaVersion = CodingUserInfoKey(rawValue: "com.sprout.schemaVersion")!
}

extension Decoder {
    /// The on-disk schema version of the payload, injected by the store before
    /// decoding. Defaults to the current version when unset, so a value that was
    /// freshly encoded (always cents) round-trips without a migration flag.
    var sproutSchemaVersion: Int {
        (userInfo[.sproutSchemaVersion] as? Int) ?? BudgetSnapshot.currentSchemaVersion
    }
}
