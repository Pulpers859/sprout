import SwiftUI

struct SummaryCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void

    var body: some View {
        let spent = max(store.netSpent(for: tab), 0)
        let remaining = store.remaining(for: tab)
        let progress = store.progress(for: tab)
        let paceProgress = store.paceProgress()
        let paceStatus = store.spendingPaceStatus(for: tab)
        let dailyAllowance = store.dailyAllowance(for: tab)
        let carryover = store.carryover(for: tab)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()

                Button {
                    onEditBudget()
                } label: {
                    HStack(spacing: 6) {
                        Text("Budget: \(SproutFormatters.currency(store.budget(for: tab)))")
                        Image(systemName: "square.and.pencil")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.sproutTextSecondary)
                }
                .buttonStyle(.plain)
            }

            if carryover > 0 {
                HStack {
                    Spacer()
                    Text("Includes \(SproutFormatters.currency(carryover)) carried over from last month")
                        .font(.caption)
                        .foregroundStyle(Color.sproutTextMuted)
                }
            }

            HStack {
                Text("\(SproutFormatters.currency(spent)) spent")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextSecondary)

                Spacer()

                Text(
                    remaining < 0
                    ? "Over by \(SproutFormatters.currency(abs(remaining)))"
                    : "\(SproutFormatters.currency(remaining)) left"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(remaining < 0 ? Color.sproutRed : Color.sageDark)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sproutTrack)
                    Capsule()
                        .fill(Color.sproutPace)
                        .frame(width: geometry.size.width * paceProgress)
                    Capsule()
                        .fill(progressColor(for: paceStatus))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 10)

            VStack(spacing: 4) {
                Text(SproutFormatters.currency(remaining))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(remaining < 0 ? Color.sproutRed : Color.sproutText)

                Text("remaining")
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("\(SproutFormatters.currency(abs(dailyAllowance)))/day")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(dailyAllowance < 0 ? Color.sproutRed : Color.sageDark)

                Text(
                    dailyAllowance < 0
                    ? "over budget"
                    : "for the next \(SproutDate.daysLeftInMonth()) day\(SproutDate.daysLeftInMonth() == 1 ? "" : "s")"
                )
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    private func progressColor(for status: SpendingPaceStatus) -> Color {
        switch status {
        case .belowPace:
            .sage
        case .onPace:
            .sproutAmber
        case .aheadOfPace:
            .sproutRed
        }
    }
}
