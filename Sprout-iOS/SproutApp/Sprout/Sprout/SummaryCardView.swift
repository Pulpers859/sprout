import SwiftUI

struct SummaryCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void

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
                        .foregroundStyle(Color.white.opacity(0.68))

                    Text(SproutFormatters.currency(remaining.magnitude))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
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
                        .frame(width: 42, height: 42)
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
                    Text("\(SproutFormatters.currency(store.budget(for: tab))) budget")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.72))
            }

            Divider()
                .overlay(Color.white.opacity(0.16))

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        dailyAllowance < .zero
                        ? "Daily overage"
                        : "Daily allowance · \(SproutDate.daysLeftInMonth()) days left"
                    )
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))

                    Text("\(SproutFormatters.currency(dailyAllowance.magnitude))/day")
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
                .foregroundStyle(Color.white.opacity(0.82))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Spending pace: \(statusTitle(for: paceStatus))")
            }

            if carryover > .zero {
                Label(
                    "\(SproutFormatters.currency(carryover)) carried over",
                    systemImage: "arrow.turn.down.right"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .padding(22)
        .background(tab.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: tab.accentDarkColor.opacity(0.2), radius: 18, x: 0, y: 10)
    }

    private func spendingColor(progress: Double, remaining: Double) -> Color {
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
