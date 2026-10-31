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
                VStack(alignment: .leading, spacing: 3) {
                    Text(footerLabel(hasBudget: hasBudget))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(footerValue(hasBudget: hasBudget))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                Text(tallyText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.trailing)
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

    /// Only meaningful once per-person targets exist; otherwise the slot shows
    /// the gift count rather than an "unplanned" figure equal to the whole
    /// budget, which would read as if nothing had been decided.
    private func footerLabel(hasBudget: Bool) -> String {
        guard hasBudget, store.holidayPlannedTotal > .zero else { return "Gifts logged" }
        return store.holidayUnallocated < .zero ? "Planned over budget by" : "Left to plan"
    }

    private func footerValue(hasBudget: Bool) -> String {
        guard hasBudget, store.holidayPlannedTotal > .zero else {
            return "\(store.holidayPurchaseCount)"
        }
        return SproutFormatters.currency(store.holidayUnallocated.magnitude)
    }

    private var tallyText: String {
        let people = store.holidayRecipients.count
        let gifts = store.holidayPurchaseCount
        if people == 0 {
            return "\(gifts) gift\(gifts == 1 ? "" : "s")"
        }
        return "\(gifts) gift\(gifts == 1 ? "" : "s") · \(people) \(people == 1 ? "person" : "people")"
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
