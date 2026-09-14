import SwiftUI

struct SummaryCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void

    /// `.system(size:)` is fixed, so the headline figure ignored Dynamic Type
    /// entirely. Scaling it keeps the card readable at accessibility sizes; the
    /// existing `minimumScaleFactor` keeps it inside the card at the extremes.
    @ScaledMetric(relativeTo: .largeTitle) private var remainingFontSize: CGFloat = 44

    var body: some View {
        let spent = max(store.netSpent(for: tab), .zero)
        let remaining = store.remaining(for: tab)
        let progress = store.progress(for: tab)
        let paceProgress = store.paceProgress()
        let paceStatus = store.spendingPaceStatus(for: tab)
        let dailyAllowance = store.dailyAllowance(for: tab)
        let carryover = store.carryover(for: tab)

        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining < .zero ? "OVER BUDGET" : "AVAILABLE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.80))

                    Text(SproutFormatters.currency(remaining.magnitude))
                        .font(.system(size: remainingFontSize, weight: .bold, design: .rounded))
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
                        .foregroundStyle(tab.accentDarkColor)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.96), in: Circle())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(tab.shortTitle.lowercased()) budget")
            }

            VStack(spacing: 9) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))

                        Capsule()
                            .fill(spendingColor(progress: progress, remaining: remaining))
                            .frame(width: geometry.size.width * progress)

                        Rectangle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 2, height: 16)
                            .offset(x: max(0, (geometry.size.width * paceProgress) - 1))
                    }
                }
                .frame(height: 8)
                .accessibilityElement()
                .accessibilityLabel("Budget progress")
                .accessibilityValue("\(Int(progress * 100)) percent spent")

                HStack {
                    Text("\(SproutFormatters.currency(spent)) spent")
                    Spacer()
                    // Not "budget": this is base + carryover, while the editor
                    // edits the base. Labelling both "budget" invited the user to
                    // add them together.
                    Text("\(SproutFormatters.currency(store.budget(for: tab))) available")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.85))
            }

            Divider()
                .overlay(Color.white.opacity(0.16))

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dailyAllowanceLabel(dailyAllowance))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.80))

                    // A closed month has one "day left" by construction, which made
                    // the per-day figure equal the entire remaining balance — the
                    // one number in the app whose job is to say what you may spend
                    // today, telling you to spend all of it. Show the leftover
                    // instead, which is what the figure actually means now.
                    Text(store.isViewingClosedMonth
                         ? SproutFormatters.currency(store.remaining(for: tab).magnitude)
                         : "\(SproutFormatters.currency(dailyAllowance.magnitude))/day")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: paceStatus))
                        .frame(width: 8, height: 8)

                    Text(statusTitle(for: paceStatus))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Spending pace: \(statusTitle(for: paceStatus))")
            }

            if carryover > .zero {
                Label(
                    "\(SproutFormatters.currency(carryover)) carried over",
                    systemImage: "arrow.turn.down.right"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(22)
        .background(tab.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: tab.accentDarkColor.opacity(0.2), radius: 18, x: 0, y: 10)
    }

    /// Day count comes from the store's displayed month, so a ledger the user has
    /// not rolled over yet is described by its own month rather than today's.
    private func dailyAllowanceLabel(_ dailyAllowance: MoneyAmount) -> String {
        // A per-day allowance is meaningless for a period that has already ended.
        if store.isViewingClosedMonth {
            // The dashboard banner says this month is "still open", so this must
            // not simultaneously call it ended.
            let remaining = store.remaining(for: tab)
            return remaining < .zero ? "\(store.currentMonthLabel) is over budget" : "Unspent in \(store.currentMonthLabel)"
        }
        if dailyAllowance < .zero { return "Daily overage" }
        let days = store.daysLeftInDisplayedMonth
        return "Daily allowance · \(days) day\(days == 1 ? "" : "s") left"
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

    private func statusColor(for status: SpendingPaceStatus) -> Color {
        switch status {
        case .belowPace:
            .sproutMint
        case .onPace:
            .sproutAmberBright
        case .aheadOfPace:
            .sproutRedBright
        }
    }

    private func statusTitle(for status: SpendingPaceStatus) -> String {
        switch status {
        case .belowPace:
            "Spending under plan"
        case .onPace:
            "Spending on plan"
        case .aheadOfPace:
            "Spending too fast"
        }
    }
}
