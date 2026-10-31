import SwiftUI

/// The holiday equivalent of `SummaryCardView`.
///
/// Deliberately *not* the same card. A holiday budget has no time dimension:
/// there is no daily allowance to divide a month into and no pace to be ahead
/// or behind of, so showing either would be inventing a figure. What matters
/// instead is how much of the budget is still unpromised, which is what the
/// bottom row shows.
struct HolidaySummaryCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let onEditBudget: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var headlineFontSize: CGFloat = 44

    var body: some View {
        let hasBudget = store.holidayHasBudget
        let spent = store.holidaySpent
        let remaining = store.holidayRemaining
        let progress = store.holidayProgress()
        let planning = planningFigure(hasBudget: hasBudget, remaining: remaining)

        VStack(alignment: .leading, spacing: 20) {
            // The season name is its own line rather than a prefix on the
            // AVAILABLE label: a custom name like "Christmas with the Kanes"
            // crammed onto one caption line shrank the whole thing to nothing.
            VStack(alignment: .leading, spacing: 6) {
                Text(store.holidaySeasonLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headlineLabel(hasBudget: hasBudget, remaining: remaining))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(SproutFormatters.currency(hasBudget ? remaining.magnitude : spent))
                            .font(.system(size: headlineFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    Button {
                        onEditBudget()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.sproutBerryDark)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.96), in: Circle())
                            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hasBudget ? "Edit holiday budget" : "Set holiday budget")
                }
            }

            if hasBudget {
                VStack(spacing: 9) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.16))

                            Capsule()
                                .fill(spendingColor(progress: progress, remaining: remaining))
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityElement()
                    .accessibilityLabel("Holiday budget progress")
                    .accessibilityValue("\(Int(progress * 100)) percent spent")

                    HStack {
                        Text("\(SproutFormatters.currency(spent)) spent")
                        Spacer()
                        Text("of \(SproutFormatters.currency(store.holidayBudget))")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                }
            } else {
                // No bar, because there is nothing to fill. Saying so beats an
                // empty track that looks like a budget you have not touched.
                Text("No holiday budget set yet. Tap the pencil to add one — it stays separate from your monthly budgets.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(Color.white.opacity(0.16))

            HStack(alignment: .center, spacing: 14) {
                // The planning slot is omitted entirely rather than filled with
                // a figure that would repeat the tally beside it or contradict
                // the headline above it. See `planningFigure`.
                if let planning {
                    VStack(alignment: .leading, spacing: 3) {
                        // Allowed to wrap, like the monthly card's equivalent
                        // slot. Forcing it onto one line turned "Targets exceed
                        // what's left by" into an ellipsis at accessibility
                        // sizes.
                        Text(planning.label)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.80))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(planning.value)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.white)
                    }

                    Spacer(minLength: 8)

                    Text(tallyText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(tallyText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(22)
        .background(AppSection.holiday.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.sproutBerryDark.opacity(0.2), radius: 18, x: 0, y: 10)
    }

    /// With no budget the headline figure is total spend, so it must not be
    /// labelled "available" — that was the exact mistake the monthly card made
    /// when two different numbers both claimed to be the amount available.
    private func headlineLabel(hasBudget: Bool, remaining: MoneyAmount) -> String {
        guard hasBudget else { return "SPENT SO FAR" }
        return remaining < .zero ? "OVER BUDGET" : "AVAILABLE"
    }

    /// The planning figure, or `nil` when there is nothing honest to put there.
    ///
    /// Three things had to be true at once, and none of them were:
    ///
    /// - It must never contradict the headline. The old figure was
    ///   `budget - targets` and ignored spending, so a season $120 over budget
    ///   showed "Left to plan $200" forty points below "OVER BUDGET $120".
    ///   `holidayUnreserved` subtracts spend, so it is always a slice of the
    ///   available balance rather than a rival claim about it.
    /// - It must not restate the tally beside it. The fallback used to read
    ///   "Gifts logged / 6" next to "6 gifts · 3 people".
    /// - It is only meaningful when someone actually has a target, and a list
    ///   of deliberate zero targets counts — which is why this asks
    ///   `holidayHasPerPersonTargets` rather than whether the total is positive.
    ///
    /// Once the budget is gone there is nothing left to plan with, so the slot
    /// disappears instead of reporting a second negative number.
    private func planningFigure(hasBudget: Bool, remaining: MoneyAmount) -> (label: String, value: String)? {
        guard hasBudget, store.holidayHasPerPersonTargets, remaining >= .zero else { return nil }

        let unreserved = store.holidayUnreserved
        if unreserved < .zero {
            return ("Targets exceed what's left by", SproutFormatters.currency(unreserved.magnitude))
        }
        return ("Left to plan", SproutFormatters.currency(unreserved))
    }

    /// Counts gifts, not rows: a return is money coming back, not something
    /// bought, so it must not be totted up as a gift.
    private var tallyText: String {
        let people = store.holidayRecipients.count
        let gifts = store.holidayGiftCount
        let returns = store.holidayReturnCount

        var parts = ["\(gifts) gift\(gifts == 1 ? "" : "s")"]
        if returns > 0 {
            parts.append("\(returns) return\(returns == 1 ? "" : "s")")
        }
        if people > 0 {
            parts.append("\(people) \(people == 1 ? "person" : "people")")
        }
        return parts.joined(separator: " · ")
    }

    private func spendingColor(progress: Double, remaining: MoneyAmount) -> Color {
        if remaining < .zero || progress >= 1 {
            return .sproutRedBright
        }
        if progress >= 0.8 {
            return .sproutAmberBright
        }
        return .sproutMint
    }
}
